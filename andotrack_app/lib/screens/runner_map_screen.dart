import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import 'runner_dashboard_screen.dart';
import 'settings_screen.dart';
import '../services/notification_service.dart';

class RunnerMapScreen extends StatefulWidget {
  const RunnerMapScreen({super.key});

  @override
  State<RunnerMapScreen> createState() => _RunnerMapScreenState();
}

class _RunnerMapScreenState extends State<RunnerMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  // FIX 1: Changed from StreamSubscription<ConnectivityResult>? to List<ConnectivityResult>
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  LatLng? _myPosition;
  int? _runnerId;
  int? _raceId;

  List<_CheckpointData> _checkpoints = [];
  Set<int> _passedCheckpointIds = {};

  Position? _lastPosition;
  bool _gpsReady = false;
  bool _mapMoved = false;

  // ─── HUD tracking state ─────────────────────────────────
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _hudTimer;
  double _totalDistanceMeters = 0.0;
  Position? _prevPosition;

  // ─── Race status ─────────────────────────────────────────
  String _raceStatus = 'upcoming';
  String _raceName = '';

  // ─── Connectivity ─────────────────────────────────────────
  bool _isOnline = true;
  final List<Map<String, dynamic>> _offlineQueue = [];

  // ─── INIT ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _runnerId = prefs.getInt('user_id');
    _raceId = prefs.getInt('active_race_id') ?? 1;

    await _loadRaceStatus();
    await _startGPS();
    await _loadCheckpoints();
    _listenToPassedCheckpoints();
    _listenToConnectivity();

    // HUD timer: update elapsed display every second
    _hudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  // ─── RACE STATUS ──────────────────────────────────────────
  Future<void> _loadRaceStatus() async {
    try {
      final races = await ApiService.getRaces();
      final race = races.firstWhere(
        (r) => r['id'] == _raceId,
        orElse: () => <String, dynamic>{},
      );
      if (race.isNotEmpty && mounted) {
        setState(() {
          _raceStatus = race['status'] ?? 'upcoming';
          _raceName = race['name'] ?? 'Race #$_raceId';
        });
        if (_raceStatus == 'active') _stopwatch.start();
      }
    } catch (_) {}
  }

  // ─── CONNECTIVITY ─────────────────────────────────────────
  void _listenToConnectivity() {
    // FIX 1: Parameter is now List<ConnectivityResult>, check with .contains()
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);
      if (online && _offlineQueue.isNotEmpty) _syncOfflineQueue();
    });
  }

  Future<void> _syncOfflineQueue() async {
    final toSync = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();
    for (final pt in toSync) {
      FirebaseDatabase.instance
          .ref('races/${pt['raceId']}/runners/${pt['runnerId']}')
          .update({
        'lat': pt['lat'],
        'lng': pt['lng'],
        'speed': pt['speed'],
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  // ─── GPS ──────────────────────────────────────────────────
  Future<void> _startGPS() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _myPosition = LatLng(last.latitude, last.longitude);
          _lastPosition = last;
        });
        _mapController.move(_myPosition!, 16);
      }
    } catch (_) {}

    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 2),
      ),
    ).listen((pos) {
      if (!mounted) return;
      if (_gpsReady && pos.accuracy > 100) return;
      if (!_gpsReady && pos.accuracy <= 80) {
        setState(() => _gpsReady = true);
        if (_raceStatus == 'active') _stopwatch.start();
      }

      // Accumulate distance
      if (_prevPosition != null) {
        _totalDistanceMeters += Geolocator.distanceBetween(
          _prevPosition!.latitude,
          _prevPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      _prevPosition = pos;

      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myPosition = newPos;
        _lastPosition = pos;
      });

      if (!_mapMoved) {
        _mapController.move(newPos, _mapController.camera.zoom);
      }

      _pushToFirebase(pos);
      _checkCheckpointProximity(pos);
    }, onError: (e) => debugPrint('GPS error: $e'));
  }

  void _pushToFirebase(Position pos) {
    if (_runnerId == null || _raceId == null) return;
    final data = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed': pos.speed,
      'accuracy': pos.accuracy,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (_isOnline) {
      FirebaseDatabase.instance
          .ref('races/$_raceId/runners/$_runnerId')
          .update(data);
    } else {
      _offlineQueue.add({
        'raceId': _raceId,
        'runnerId': _runnerId,
        ...data,
      });
    }
  }

  // ─── CHECKPOINTS ──────────────────────────────────────────
  Future<void> _loadCheckpoints() async {
    if (_raceId == null) return;
    try {
      final data = await ApiService.getCheckpoints(_raceId!);
      if (mounted) {
        setState(() {
          _checkpoints = data
              .map((c) => _CheckpointData(
                    id: c['id'],
                    name: c['name'],
                    lat: (c['lat'] as num).toDouble(),
                    lng: (c['lng'] as num).toDouble(),
                    radiusMeters: (c['radius_meters'] as num).toInt(),
                    orderNumber: (c['order_number'] as num).toInt(),
                  ))
              .toList()
            ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber));
        });
      }
    } catch (e) {
      debugPrint('Failed to load checkpoints: $e');
    }
  }

  void _listenToPassedCheckpoints() {
    if (_runnerId == null || _raceId == null) return;
    FirebaseDatabase.instance
        .ref('races/$_raceId/runner_checkpoints/$_runnerId')
        .onValue
        .listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        _passedCheckpointIds = data.keys.map(int.parse).toSet();
      });
    });
  }

void _checkCheckpointProximity(Position pos) {
    final next = _nextCheckpoint;
    if (next == null) return;
    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude, next.lat, next.lng,
    );
    if (dist <= next.radiusMeters) {
      FirebaseDatabase.instance
          .ref('races/$_raceId/runner_checkpoints/$_runnerId/${next.id}')
          .set(DateTime.now().toIso8601String());

      ApiService.arriveAtCheckpoint(next.id, _runnerId!);
      NotificationService.showCheckpointPassed(next.name);

      HapticFeedback.mediumImpact();
      final remaining = _checkpoints.length - _passedCheckpointIds.length - 1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.black, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${next.name} reached!',
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
                if (remaining > 0)
                  Text(
                    '  ·  $remaining remaining',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
              ],
            ),
            backgroundColor: const Color(0xFF00FF9C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  _CheckpointData? get _nextCheckpoint {
    try {
      return _checkpoints
          .firstWhere((c) => !_passedCheckpointIds.contains(c.id));
    } catch (_) {
      return null;
    }
  }

  // ─── HUD HELPERS ──────────────────────────────────────────
  double get _speedKmh =>
      ((_lastPosition?.speed ?? 0) * 3.6).clamp(0, 99.9);

  String get _paceStr {
    final spd = _lastPosition?.speed ?? 0;
    if (spd < 0.3) return '--:--';
    final spk = 1000 / spd;
    final m = (spk ~/ 60).toString().padLeft(2, '0');
    final s = (spk % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _distanceStr {
    final km = _totalDistanceMeters / 1000;
    return km >= 1.0 ? '${km.toStringAsFixed(2)} km' : '${_totalDistanceMeters.toStringAsFixed(0)} m';
  }

  String get _elapsedStr {
    final e = _stopwatch.elapsed;
    final h = e.inHours;
    final m = (e.inMinutes % 60).toString().padLeft(2, '0');
    final s = (e.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0D0D14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Leave race tracking?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text(
              'Your GPS tracking will stop and your position will no longer update.',
              style: TextStyle(color: Color(0xFF888899), fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay',
                    style: TextStyle(color: Color(0xFF00FF9C))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave',
                    style: TextStyle(color: Color(0xFF666680))),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const RunnerDashboardScreen()),
            (_) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Stack(
          children: [
            // ── MAP ─────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _myPosition ?? const LatLng(10.3157, 123.8854),
                initialZoom: 16,
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && !_mapMoved) {
                    setState(() => _mapMoved = true);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
                // Route polyline
                if (_checkpoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _checkpoints
                            .map((c) => LatLng(c.lat, c.lng))
                            .toList(),
                        color: const Color(0xFF00B4FF).withOpacity(0.4),
                        strokeWidth: 2.5,
                        isDotted: true,
                      ),
                    ],
                  ),
                // Checkpoint radius circles
                CircleLayer(
                  circles: _checkpoints.map((cp) {
                    final isPassed = _passedCheckpointIds.contains(cp.id);
                    final isNext = cp.id == _nextCheckpoint?.id;
                    return CircleMarker(
                      point: LatLng(cp.lat, cp.lng),
                      radius: cp.radiusMeters.toDouble(),
                      useRadiusInMeter: true,
                      color: isPassed
                          ? const Color(0xFF00FF9C).withOpacity(0.12)
                          : isNext
                              ? const Color(0xFF00B4FF).withOpacity(0.15)
                              : Colors.white.withOpacity(0.04),
                      borderColor: isPassed
                          ? const Color(0xFF00FF9C)
                          : isNext
                              ? const Color(0xFF00B4FF)
                              : const Color(0xFF333348),
                      borderStrokeWidth: isNext ? 2.5 : 1.5,
                    );
                  }).toList(),
                ),
                MarkerLayer(
                  markers: [
                    // Checkpoints
                    ..._checkpoints.asMap().entries.map((entry) {
                      final i = entry.key;
                      final cp = entry.value;
                      final isPassed = _passedCheckpointIds.contains(cp.id);
                      final isNext = cp.id == _nextCheckpoint?.id;
                      final isLast = i == _checkpoints.length - 1;
                      final isFirst = i == 0;
                      return Marker(
                        point: LatLng(cp.lat, cp.lng),
                        width: isNext ? 140 : 110,
                        height: 52,
                        child: _CheckpointMarker(
                          cp: cp,
                          index: i,
                          isPassed: isPassed,
                          isNext: isNext,
                          isFirst: isFirst,
                          isLast: isLast,
                        ),
                      );
                    }),
                    // Runner pulse
                    if (_myPosition != null)
                      Marker(
                        point: _myPosition!,
                        width: 60,
                        height: 60,
                        child: _PulseMarker(isGpsReady: _gpsReady),
                      ),
                  ],
                ),
              ],
            ),

            // ── OFFLINE BANNER ──────────────────────────────
            if (!_isOnline)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: const Color(0xFFFFB800),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off,
                          color: Colors.black, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Offline · ${_offlineQueue.length} point${_offlineQueue.length == 1 ? '' : 's'} queued',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── TOP BAR ─────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (_isOnline ? 8 : 34),
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _TopButton(
                    icon: Icons.arrow_back,
                    onTap: () async {
                      final leave = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF0D0D14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: const Text('Leave race tracking?',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 16)),
                          content: const Text(
                            'Your GPS tracking will stop.',
                            style: TextStyle(
                                color: Color(0xFF888899), fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Stay',
                                  style:
                                      TextStyle(color: Color(0xFF00FF9C))),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Leave',
                                  style:
                                      TextStyle(color: Color(0xFF666680))),
                            ),
                          ],
                        ),
                      );
                      if (leave == true && context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RunnerDashboardScreen()),
                          (_) => false,
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  // Race status pill
                  _RaceStatusPill(
                      status: _raceStatus, raceName: _raceName),
                  const Spacer(),
                  // GPS pill
                  _GpsPill(
                      isReady: _gpsReady,
                      accuracy: _lastPosition?.accuracy),
                  const SizedBox(width: 8),
                  _TopButton(
                    icon: Icons.my_location,
                    onTap: () {
                      setState(() => _mapMoved = false);
                      if (_myPosition != null) {
                        _mapController.move(
                            _myPosition!, _mapController.camera.zoom);
                      }
                    },
                  ),
                ],
              ),
            ),

            // ── BOTTOM: HUD + CHECKPOINT BAR ─────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HUD stats
                  _HudStrip(
                    speedKmh: _speedKmh,
                    pace: _paceStr,
                    distance: _distanceStr,
                    elapsed: _elapsedStr,
                  ),
                  // Checkpoint progress
                  if (_checkpoints.isNotEmpty)
                    _CheckpointProgressBar(
                      checkpoints: _checkpoints,
                      passedIds: _passedCheckpointIds,
                      nextCheckpoint: _nextCheckpoint,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _connectivitySub?.cancel();
    _hudTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}

// ─── RACE STATUS PILL ───────────────────────────────────────────────────────
class _RaceStatusPill extends StatelessWidget {
  final String status;
  final String raceName;
  const _RaceStatusPill({required this.status, required this.raceName});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'active':
        color = const Color(0xFF00FF9C);
        label = '● Live';
        break;
      case 'finished':
        color = const Color(0xFF666680);
        label = 'Finished';
        break;
      default:
        color = const Color(0xFFFFB800);
        label = 'Not started';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14).withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          if (raceName.isNotEmpty) ...[
            Text(
              '  ·  ',
              style: TextStyle(
                  color: color.withOpacity(0.4), fontSize: 11),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                raceName,
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── HUD STRIP ──────────────────────────────────────────────────────────────
class _HudStrip extends StatelessWidget {
  final double speedKmh;
  final String pace;
  final String distance;
  final String elapsed;

  const _HudStrip({
    required this.speedKmh,
    required this.pace,
    required this.distance,
    required this.elapsed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          _HudTile(
              value: speedKmh.toStringAsFixed(1), unit: 'km/h', accent: true),
          _HudDivider(),
          _HudTile(value: pace, unit: '/km pace'),
          _HudDivider(),
          _HudTile(value: distance, unit: 'dist.'),
          _HudDivider(),
          _HudTile(value: elapsed, unit: 'elapsed'),
        ],
      ),
    );
  }
}

class _HudTile extends StatelessWidget {
  final String value;
  final String unit;
  final bool accent;
  const _HudTile(
      {required this.value, required this.unit, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color:
                  accent ? const Color(0xFF00FF9C) : Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: const TextStyle(
                color: Color(0xFF444460), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _HudDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 0.5,
        height: 32,
        color: const Color(0xFF1E1E30),
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

// ─── CHECKPOINT MARKER ──────────────────────────────────────────────────────
class _CheckpointMarker extends StatelessWidget {
  final _CheckpointData cp;
  final int index;
  final bool isPassed;
  final bool isNext;
  final bool isFirst;
  final bool isLast;

  const _CheckpointMarker({
    required this.cp,
    required this.index,
    required this.isPassed,
    required this.isNext,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    if (isFirst && !isPassed) {
      bg = const Color(0xFF00FF9C);
      fg = Colors.black;
      icon = Icons.flag;
    } else if (isLast) {
      bg = isPassed ? const Color(0xFF00FF9C) : const Color(0xFFFF4D4D);
      fg = Colors.black;
      icon = Icons.flag_rounded;
    } else if (isPassed) {
      bg = const Color(0xFF00FF9C);
      fg = Colors.black;
      icon = Icons.check_circle;
    } else if (isNext) {
      bg = const Color(0xFF00B4FF);
      fg = Colors.black;
      icon = Icons.navigation;
    } else {
      bg = const Color(0xFF1C1C2E);
      fg = const Color(0xFF666680);
      icon = Icons.radio_button_unchecked;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg.withOpacity(isNext || isPassed ? 0.92 : 0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isNext
                  ? const Color(0xFF00B4FF)
                  : isPassed
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFF333348),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: fg),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  cp.name,
                  style: TextStyle(
                      color: fg,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── CHECKPOINT PROGRESS BAR ────────────────────────────────────────────────
class _CheckpointProgressBar extends StatelessWidget {
  final List<_CheckpointData> checkpoints;
  final Set<int> passedIds;
  final _CheckpointData? nextCheckpoint;

  const _CheckpointProgressBar({
    required this.checkpoints,
    required this.passedIds,
    required this.nextCheckpoint,
  });

  @override
  Widget build(BuildContext context) {
    final passed = checkpoints.where((c) => passedIds.contains(c.id)).length;
    final total = checkpoints.length;
    final allDone = passed == total && total > 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0F),
        border: Border(top: BorderSide(color: Color(0xFF1E1E30))),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Checkpoints  $passed / $total',
                style: const TextStyle(
                    color: Color(0xFFCCCCDD),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              if (allDone)
                const Text('🏁 All done!',
                    style: TextStyle(
                        color: Color(0xFF00FF9C),
                        fontSize: 12,
                        fontWeight: FontWeight.bold))
              else if (nextCheckpoint != null)
                Text(
                  'Next: ${nextCheckpoint!.name}',
                  style: const TextStyle(
                      color: Color(0xFF00B4FF), fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: checkpoints.map((cp) {
              final isPassed = passedIds.contains(cp.id);
              final isNext = cp.id == nextCheckpoint?.id;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: isPassed
                        ? const Color(0xFF00FF9C)
                        : isNext
                            ? const Color(0xFF00B4FF)
                            : const Color(0xFF1E1E30),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── TOP BUTTON ─────────────────────────────────────────────────────────────
class _TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14).withOpacity(0.92),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF1E1E30)),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }
}

// ─── GPS PILL ────────────────────────────────────────────────────────────────
class _GpsPill extends StatelessWidget {
  final bool isReady;
  final double? accuracy;
  const _GpsPill({required this.isReady, this.accuracy});

  @override
  Widget build(BuildContext context) {
    final color =
        isReady ? const Color(0xFF00FF9C) : const Color(0xFFFFB800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14).withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              isReady ? Icons.gps_fixed : Icons.gps_not_fixed,
              size: 13,
              color: color),
          const SizedBox(width: 5),
          Text(
            isReady
                ? 'GPS ±${accuracy?.toStringAsFixed(0) ?? '--'}m'
                : 'Acquiring…',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── PULSE MARKER ────────────────────────────────────────────────────────────
class _PulseMarker extends StatefulWidget {
  final bool isGpsReady;
  const _PulseMarker({required this.isGpsReady});

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isGpsReady
        ? const Color(0xFF00FF9C)
        : const Color(0xFFFFB800);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 40 + (_anim.value * 16),
            height: 40 + (_anim.value * 16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12 * (1 - _anim.value)),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.6), blurRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── DATA CLASS ──────────────────────────────────────────────────────────────
class _CheckpointData {
  final int id;
  final String name;
  final double lat;
  final double lng;
  final int radiusMeters;
  final int orderNumber;

  _CheckpointData({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.orderNumber,
  });
}