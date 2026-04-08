import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'settings_screen.dart';

class RunnerMapScreen extends StatefulWidget {
  const RunnerMapScreen({super.key});

  @override
  State<RunnerMapScreen> createState() => _RunnerMapScreenState();
}

class _RunnerMapScreenState extends State<RunnerMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;

  LatLng? _myPosition;
  int? _runnerId;
  int? _raceId;

  List<_CheckpointData> _checkpoints = [];
  Set<int> _passedCheckpointIds = {};

  Position? _lastPosition;
  bool _gpsReady = false;       // true once accuracy < 50 m (relaxed from 30)
  bool _mapMoved = false;       // prevent re-centering if user panned

  // ─── INIT ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _runnerId = prefs.getInt('user_id');
    _raceId = prefs.getInt('active_race_id') ?? 1;

    await _startGPS();
    await _loadCheckpoints();
    _listenToPassedCheckpoints();
  }

  // ─── GPS: TWO-PHASE ACQUISITION (fast lock → high accuracy) ──────────────
  //
  // Phase 1 — immediate: grab last-known position (no satellite wait at all)
  // Phase 2 — coarse stream at LocationAccuracy.medium (~10-30 s to lock)
  //            Mark gpsReady once accuracy < 50 m so the pill turns green fast
  // Phase 3 — after first decent fix, switch to high accuracy for tracking
  Future<void> _startGPS() async {
    // --- Permission ---
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    // --- Phase 1: last-known (instant, 0 ms) ---
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

    // --- Phase 2+3: stream that starts coarse then we just keep it running ---
    // Using LocationAccuracy.best here but with a lenient _gpsReady threshold
    // so the pill turns green quickly even on a coarse fix.
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,          // update every 5 m (was 3 — less noise)
        forceLocationManager: false, // use fused provider (faster first fix)
        intervalDuration: const Duration(seconds: 2),
      ),
    ).listen((pos) {
      if (!mounted) return;

      // Relax: accept anything ≤ 80 m while acquiring, ≤ 100 m once ready
      // (original code was 50 / 30 — way too strict for first fix)
      if (_gpsReady && pos.accuracy > 100) return;

      if (!_gpsReady && pos.accuracy <= 80) {
        setState(() => _gpsReady = true);
      }

      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myPosition = newPos;
        _lastPosition = pos;
      });

      // Only auto-center if user hasn't manually panned
      if (!_mapMoved) {
        _mapController.move(newPos, _mapController.camera.zoom);
      }

      _pushToFirebase(pos);
      _checkCheckpointProximity(pos);
    }, onError: (e) {
      debugPrint('GPS stream error: $e');
    });
  }

  void _pushToFirebase(Position pos) {
    if (_runnerId == null || _raceId == null) return;
    FirebaseDatabase.instance
        .ref('races/$_raceId/runners/$_runnerId')
        .update({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed': pos.speed,
      'accuracy': pos.accuracy,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ─── CHECKPOINTS ──────────────────────────────────────────────────────────
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
      final data =
          Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        _passedCheckpointIds = data.keys.map(int.parse).toSet();
      });
    });
  }

  void _checkCheckpointProximity(Position pos) {
    final next = _nextCheckpoint;
    if (next == null) return;

    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      next.lat, next.lng,
    );

    if (dist <= next.radiusMeters) {
      FirebaseDatabase.instance
          .ref('races/$_raceId/runner_checkpoints/$_runnerId/${next.id}')
          .set(DateTime.now().toIso8601String());

      ApiService.arriveAtCheckpoint(next.id, _runnerId!);
    }
  }

  _CheckpointData? get _nextCheckpoint {
    try {
      return _checkpoints.firstWhere(
        (c) => !_passedCheckpointIds.contains(c.id),
      );
    } catch (_) {
      return null;
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // ── MAP ────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _myPosition ?? const LatLng(10.3157, 123.8854),
              initialZoom: 16,
              // Detect when user manually pans so we stop auto-centering
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
                        ? const Color(0xFF00FF9C).withOpacity(0.15)
                        : isNext
                            ? const Color(0xFF00B4FF).withOpacity(0.18)
                            : Colors.white.withOpacity(0.05),
                    borderColor: isPassed
                        ? const Color(0xFF00FF9C)
                        : isNext
                            ? const Color(0xFF00B4FF)
                            : const Color(0xFF444460),
                    borderStrokeWidth: isNext ? 2.5 : 1.5,
                  );
                }).toList(),
              ),
              // Checkpoint labels + pin markers
              MarkerLayer(
                markers: [
                  ..._checkpoints.map((cp) {
                    final isPassed = _passedCheckpointIds.contains(cp.id);
                    final isNext = cp.id == _nextCheckpoint?.id;
                    return Marker(
                      point: LatLng(cp.lat, cp.lng),
                      width: isNext ? 140 : 100,
                      height: 50,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPassed
                                  ? const Color(0xFF00FF9C).withOpacity(0.9)
                                  : isNext
                                      ? const Color(0xFF00B4FF)
                                          .withOpacity(0.9)
                                      : const Color(0xFF1C1C2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isPassed
                                    ? const Color(0xFF00FF9C)
                                    : isNext
                                        ? const Color(0xFF00B4FF)
                                        : const Color(0xFF444460),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPassed
                                      ? Icons.check_circle
                                      : isNext
                                          ? Icons.navigation
                                          : Icons.radio_button_unchecked,
                                  size: 12,
                                  color: isPassed
                                      ? Colors.black
                                      : isNext
                                          ? Colors.black
                                          : const Color(0xFF666680),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    cp.name,
                                    style: TextStyle(
                                      color: isPassed || isNext
                                          ? Colors.black
                                          : const Color(0xFF888899),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // Runner pulse marker
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

          // ── TOP BAR ────────────────────────────────────────────────────
          // GPS pill (center) + re-center button + settings button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                // Settings / logout
                _TopButton(
                  icon: Icons.settings_outlined,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()),
                  ),
                ),
                const Spacer(),
                // GPS status pill
                _GpsPill(
                  isReady: _gpsReady,
                  accuracy: _lastPosition?.accuracy,
                ),
                const Spacer(),
                // Re-center button
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

          // ── CHECKPOINT PROGRESS BAR (bottom) ───────────────────────────
          if (_checkpoints.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _CheckpointProgressBar(
                checkpoints: _checkpoints,
                passedIds: _passedCheckpointIds,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}

// ─── TOP ICON BUTTON ───────────────────────────────────────────────────────
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
          border: Border.all(
              color: const Color(0xFF1E1E30), width: 1),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }
}

// ─── GPS STATUS PILL ───────────────────────────────────────────────────────
class _GpsPill extends StatelessWidget {
  final bool isReady;
  final double? accuracy;

  const _GpsPill({required this.isReady, this.accuracy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14).withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isReady
              ? const Color(0xFF00FF9C).withOpacity(0.6)
              : const Color(0xFFFFB800).withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReady ? Icons.gps_fixed : Icons.gps_not_fixed,
            size: 13,
            color: isReady
                ? const Color(0xFF00FF9C)
                : const Color(0xFFFFB800),
          ),
          const SizedBox(width: 6),
          Text(
            isReady
                ? 'GPS ±${accuracy?.toStringAsFixed(0) ?? '--'}m'
                : 'Acquiring GPS...',
            style: TextStyle(
              color: isReady
                  ? const Color(0xFF00FF9C)
                  : const Color(0xFFFFB800),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PULSE MARKER ──────────────────────────────────────────────────────────
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
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
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
                BoxShadow(color: color.withOpacity(0.6), blurRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CHECKPOINT PROGRESS BAR ───────────────────────────────────────────────
class _CheckpointProgressBar extends StatelessWidget {
  final List<_CheckpointData> checkpoints;
  final Set<int> passedIds;

  const _CheckpointProgressBar({
    required this.checkpoints,
    required this.passedIds,
  });

  @override
  Widget build(BuildContext context) {
    final passed =
        checkpoints.where((c) => passedIds.contains(c.id)).length;
    final total = checkpoints.length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D14),
        border: Border(
          top: BorderSide(color: Color(0xFF1E1E30), width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
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
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (passed == total && total > 0)
                const Text(
                  '🏁 All done!',
                  style: TextStyle(
                    color: Color(0xFF00FF9C),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: checkpoints.map((cp) {
              final isPassed = passedIds.contains(cp.id);
              final isNext = !isPassed &&
                  checkpoints
                          .where((c) => !passedIds.contains(c.id))
                          .firstOrNull
                          ?.id ==
                      cp.id;
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
                            : const Color(0xFF2A2A3D),
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

// ─── DATA CLASS ────────────────────────────────────────────────────────────
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