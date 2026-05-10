// MOVED TO: lib/features/map/screens/runner_map_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/services/routing_service.dart';
import 'package:andotrack_app/core/services/notification_service.dart';
import 'package:andotrack_app/features/runner/screens/personal_results_screen.dart';
import 'package:andotrack_app/features/runner/screens/runner_stats_screen.dart';
import 'package:andotrack_app/features/runner/screens/settings_screen.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';

class RunnerMapScreen extends StatefulWidget {
  const RunnerMapScreen({super.key});

  @override
  State<RunnerMapScreen> createState() => _RunnerMapScreenState();
}

class _RunnerMapScreenState extends State<RunnerMapScreen>
    with SingleTickerProviderStateMixin {
  // ── Controllers ───────────────────────────────────────────
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  late AnimationController _livePulseCtrl;

  // ── Runner identity ───────────────────────────────────────
  int? _runnerId;       // user account ID — used for Firebase paths
  int? _runnerRecordId; // RaceRunner.id — used for checkpoint arrival API
  int? _raceId;

  // ── Map state ─────────────────────────────────────────────
  LatLng? _myPosition;
  List<_CheckpointData> _checkpoints = [];
  Set<int> _passedCheckpointIds = {};
  final Set<int> _notifiedCheckpointIds = {};
  List<LatLng> _routePolyline = [];
  List<LatLng> _remainingPolyline = [];

  Position? _lastPosition;
  bool _gpsReady = false;
  bool _mapMoved = false;

  // ── GPS cold-start phase flag ─────────────────────────────
  // true until the first position is available; stream starts with
  // distanceFilter: 0 and switches to 5 once the first fix arrives.
  bool _gpsInitPhase = true;

  // ── HUD ───────────────────────────────────────────────────
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _hudTimer;
  double _totalDistanceMeters = 0.0;
  Position? _prevPosition;

  // ── Race ─────────────────────────────────────────────────
  String _raceStatus = 'upcoming';
  String _raceName = '';
  String? _scheduledStart;
  Map<String, dynamic>? _raceData;

  // ── Connectivity + offline queue ──────────────────────────
  bool _isOnline = true;
  final List<Map<String, dynamic>> _offlineQueue = [];

  // ── Route building lock ───────────────────────────────────
  bool _buildingRoute = false;

  // ── Finish polling ────────────────────────────────────────
  Timer? _finishPollTimer;
  bool _raceFinished = false;

  // ── INIT ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _livePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _runnerId = prefs.getInt('user_id');
    _raceId = prefs.getInt('active_race_id');

    if (_raceId == null) return;

    await _loadRaceStatus();
    await _loadRunnerRecordId();

    await _startGPS();
    await _loadCheckpoints();
    _listenToPassedCheckpoints();
    _listenToConnectivity();

    _hudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Poll for race finish / status change every 15 s
    _finishPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollRaceStatus();
    });
  }

  // ── Race status ───────────────────────────────────────────

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
          _scheduledStart = race['scheduled_start'] as String?;
          _raceData = race;
        });
        if (_raceStatus == 'active') _stopwatch.start();
      }
    } catch (_) {}
  }

  Future<void> _pollRaceStatus() async {
    if (_raceFinished || _raceId == null) return;
    try {
      final races = await ApiService.getRaces();
      final race = races.firstWhere(
        (r) => r['id'] == _raceId,
        orElse: () => <String, dynamic>{},
      );
      if (race.isEmpty || !mounted) return;
      final newStatus = race['status'] as String? ?? '';

      if (newStatus == 'finished' && !_raceFinished) {
        _raceFinished = true;
        _stopwatch.stop();
        setState(() {
          _raceStatus = 'finished';
          _raceData = race;
        });
        _goToPersonalResults();
        return;
      }

      if (newStatus == 'active' && _raceStatus != 'active') {
        setState(() {
          _raceStatus = 'active';
          _raceData = race;
        });
        if (!_stopwatch.isRunning) _stopwatch.start();
      }
    } catch (_) {}
  }

  void _goToPersonalResults() {
    _finishPollTimer?.cancel();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalResultsScreen(
          raceId: _raceId!,
          raceName: _raceName,
          raceData: _raceData,
        ),
      ),
    );
  }

  // ── Runner record ID lookup ───────────────────────────────
  // The checkpoint arrival API requires the RaceRunner.id (registration
  // record), not the user account ID. Fetch the runner list and find the
  // entry whose user_id matches the logged-in user.

  Future<void> _loadRunnerRecordId() async {
    if (_runnerId == null || _raceId == null) return;
    try {
      final runners = await ApiService.getRaceRunners(_raceId!);
      final match = runners
          .where((r) => (r['user_id'] as num?)?.toInt() == _runnerId)
          .toList();
      if (match.isNotEmpty) {
        _runnerRecordId = (match.first['id'] as num?)?.toInt() ?? _runnerId;
        debugPrint('[Init] RaceRunner record: record_id=$_runnerRecordId user_id=$_runnerId');
      } else {
        _runnerRecordId = _runnerId;
        debugPrint('[Init] No RaceRunner record for user_id=$_runnerId — fallback to user_id');
      }
    } catch (e) {
      _runnerRecordId = _runnerId;
      debugPrint('[Init] Runner record lookup failed: $e — using user_id=$_runnerId');
    }
  }

  // ── Connectivity ──────────────────────────────────────────

  void _listenToConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.isNotEmpty &&
          !results.contains(ConnectivityResult.none);
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

  // ── GPS ───────────────────────────────────────────────────
  //
  // Two-phase cold-start strategy:
  //   Phase 1 (_gpsInitPhase == true):  distanceFilter: 0  — fires on any movement
  //   Phase 2 (_gpsInitPhase == false): distanceFilter: 5  — filters micro-jitter
  //
  // Fallback order before the stream starts:
  //   1. getLastKnownPosition()            — instant (OS cache)
  //   2. getCurrentPosition(medium)        — 2–5 s via cell/WiFi triangulation
  //   3. Phase-1 stream with filter: 0     — fires on first satellite event

  Future<void> _startGPS() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) _showPermissionDeniedBanner();
      return;
    }
    if (perm == LocationPermission.denied) return;

    // Fallback 1: last known position (instant — OS cache, no I/O wait)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _myPosition   = LatLng(last.latitude, last.longitude);
          _lastPosition = last;
          _gpsInitPhase = false;
        });
        _mapController.move(_myPosition!, 16);
      }
    } catch (_) {}

    // Fallback 2: medium-accuracy one-shot if still no position (2–5 s)
    if (_myPosition == null) {
      try {
        final medium = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        if (mounted) {
          setState(() {
            _myPosition   = LatLng(medium.latitude, medium.longitude);
            _lastPosition = medium;
            _gpsInitPhase = false;
          });
          _mapController.move(_myPosition!, 16);
        }
      } catch (_) {}
    }

    _subscribePositionStream();
  }

  // Subscribes the position stream. Uses distanceFilter: 0 during the init
  // phase (no position yet) and distanceFilter: 5 once a position exists.
  // When the first event arrives in init phase, switches to the filtered stream.
  void _subscribePositionStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy:         LocationAccuracy.high,
        distanceFilter:   _gpsInitPhase ? 0 : 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 2),
      ),
    ).listen((pos) {
      if (!mounted) return;
      if (_gpsReady && pos.accuracy > 100) return;

      // Remember whether we are switching from init phase this event
      final bool switchingToFiltered = _gpsInitPhase;

      final bool wasFirstFix = !_gpsReady && pos.accuracy <= 80;
      if (wasFirstFix) {
        setState(() => _gpsReady = true);
        if (_raceStatus == 'active') _stopwatch.start();
      }

      if (_prevPosition != null) {
        _totalDistanceMeters += Geolocator.distanceBetween(
          _prevPosition!.latitude,
          _prevPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      _prevPosition = pos;

      final bool hadNoPosition = _myPosition == null;
      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myPosition   = newPos;
        _lastPosition = pos;
        _gpsInitPhase = false;
      });

      if (!_mapMoved) {
        _mapController.move(newPos, _mapController.camera.zoom);
      }

      if (hadNoPosition || wasFirstFix) {
        _buildRemainingRoutePolyline();
      }

      // Only push to Firebase when race is active
      if (_raceStatus == 'active') {
        _pushToFirebase(pos);
      }
      _checkCheckpointProximity(pos);

      // First event in init phase — restart with distanceFilter: 5
      if (switchingToFiltered) {
        _subscribePositionStream();
      }
    }, onError: (e) => debugPrint('GPS error: $e'));
  }

  void _showPermissionDeniedBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'Location permission denied. Enable it in Settings to track your run.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D0D14),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings',
                style: TextStyle(color: Color(0xFF00FF9C))),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss',
                style: TextStyle(color: Color(0xFF444460))),
          ),
        ],
      ),
    );
  }

  void _centerOnMe() {
    if (_myPosition != null) {
      _mapController.move(_myPosition!, _mapController.camera.zoom);
      setState(() => _mapMoved = false);
    }
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
      _offlineQueue.add({'raceId': _raceId, 'runnerId': _runnerId, ...data});
    }
  }

  // ── Checkpoints ───────────────────────────────────────────

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
      await _buildFullRoutePolyline();
    } catch (e) {
      debugPrint('Failed to load checkpoints: $e');
    }
  }

  Future<void> _buildFullRoutePolyline() async {
    if (_checkpoints.length < 2 || _buildingRoute) return;
    _buildingRoute = true;
    try {
      final waypoints =
          _checkpoints.map((c) => LatLng(c.lat, c.lng)).toList();
      final pts = await RoutingService.getRoutePolyline(waypoints);
      if (mounted) setState(() => _routePolyline = pts);
      await _buildRemainingRoutePolyline();
    } finally {
      _buildingRoute = false;
    }
  }

  Future<void> _buildRemainingRoutePolyline() async {
    final next = _nextCheckpoint;
    if (next == null) {
      if (mounted) setState(() => _remainingPolyline = []);
      return;
    }
    if (_myPosition == null) return;

    final remaining = _checkpoints
        .where((c) => !_passedCheckpointIds.contains(c.id))
        .toList();

    final waypoints = [
      _myPosition!,
      ...remaining.map((c) => LatLng(c.lat, c.lng)),
    ];

    final pts = await RoutingService.getRoutePolyline(waypoints);
    if (mounted) setState(() => _remainingPolyline = pts);
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
      final newPassed = data.keys.map(int.parse).toSet();

      final gained = newPassed.difference(_passedCheckpointIds);
      setState(() => _passedCheckpointIds = newPassed);

      if (gained.isNotEmpty) {
        _buildRemainingRoutePolyline();
      }
    });
  }

  void _checkCheckpointProximity(Position pos) {
    final next = _nextCheckpoint;
    if (next == null) return;
    if (_notifiedCheckpointIds.contains(next.id)) return;

    // Client-side radius floor: never use less than 30 m regardless of what
    // the organizer set — GPS accuracy alone can be ±15–30 m.
    final effectiveRadius = max(next.radiusMeters.toDouble(), 30.0);
    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude, next.lat, next.lng,
    );

    debugPrint(
      '[Checkpoint] cp=${next.id} name="${next.name}" '
      'dist=${dist.toStringAsFixed(1)} m '
      'radius=${effectiveRadius.toStringAsFixed(0)} m '
      'runnerRecord=$_runnerRecordId',
    );

    if (dist <= effectiveRadius) {
      // 1. Update local state immediately — do NOT wait for Firebase echo.
      //    This unblocks _nextCheckpoint right away so the UI advances.
      setState(() => _passedCheckpointIds = {..._passedCheckpointIds, next.id});

      // 2. Lock deduplication AFTER local update.
      _notifiedCheckpointIds.add(next.id);

      // 3. Write to Firebase (best-effort, also drives _listenToPassedCheckpoints).
      FirebaseDatabase.instance
          .ref('races/$_raceId/runner_checkpoints/$_runnerId/${next.id}')
          .set(DateTime.now().toIso8601String());

      // 4. Notify backend using the RaceRunner record ID (not user account ID).
      final arrivalRunnerId = _runnerRecordId ?? _runnerId!;
      ApiService.arriveAtCheckpoint(next.id, arrivalRunnerId).then((_) {
        debugPrint('[Checkpoint] Server confirmed: cp=${next.id} runner=$arrivalRunnerId');
      }).catchError((e) {
        debugPrint('[Checkpoint] Server arrival failed: cp=${next.id} runner=$arrivalRunnerId error=$e');
      });

      NotificationService.showCheckpointPassed(next.name);
      HapticFeedback.mediumImpact();

      // _passedCheckpointIds now includes next.id, so remaining is correct.
      final remaining = _checkpoints.length - _passedCheckpointIds.length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Text('${next.name} reached!',
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              if (remaining > 0)
                Text('  ·  $remaining remaining',
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12)),
            ]),
            backgroundColor: const Color(0xFF00FF9C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  _CheckpointData? get _nextCheckpoint {
    try {
      final unpassed = _checkpoints
          .where((c) => !_passedCheckpointIds.contains(c.id))
          .toList()
        ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber));
      return unpassed.first;
    } catch (_) {
      return null;
    }
  }

  // ── HUD helpers ───────────────────────────────────────────

  bool get _isLive => _raceStatus == 'active';

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
    return km >= 1.0
        ? '${km.toStringAsFixed(2)} km'
        : '${_totalDistanceMeters.toStringAsFixed(0)} m';
  }

  String get _accuracyLabel {
    final acc = _lastPosition?.accuracy;
    if (acc == null) return '--';
    return '±${acc.toStringAsFixed(0)}m';
  }

  Color get _accuracyColor {
    final acc = _lastPosition?.accuracy;
    if (acc == null) return const Color(0xFF444460);
    if (acc <= 10) return const Color(0xFF00FF9C);
    if (acc <= 30) return const Color(0xFFFFB800);
    return const Color(0xFFFF4D4D);
  }

  String get _waitingBanner {
    if (_scheduledStart == null) return 'Waiting for organizer to start';
    try {
      final dt = DateTime.parse(_scheduledStart!).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return 'Race starts at $h:$m $ampm — waiting for organizer to start';
    } catch (_) {
      return 'Waiting for organizer to start';
    }
  }

  // ── Dispose ───────────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    _connectivitySub?.cancel();
    _hudTimer?.cancel();
    _finishPollTimer?.cancel();
    _stopwatch.stop();
    _livePulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────

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
              'Your GPS tracking will stop.',
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
            MaterialPageRoute(
                builder: (_) => const RunnerDashboardScreen()),
            (_) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Stack(
          children: [
            // Show loading state if GPS not ready yet, else show map
            if (_myPosition == null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF00FF9C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Getting your location…',
                      style: TextStyle(
                        color: Color(0xFF8888AA),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              _buildMap(),
            _buildTopBar(),
            if (!_isLive) _buildWaitingBanner(),
            _buildLocateMeButton(),
            _buildStatsButton(),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
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
        // CartoDB dark tiles — OSM was 403-blocked for Flutter apps
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: ['a', 'b', 'c', 'd'],
        ),

        if (_routePolyline.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePolyline,
                color: const Color(0xFF333348),
                strokeWidth: 3.0,
              ),
            ],
          ),

        if (_remainingPolyline.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _remainingPolyline,
                color: const Color(0xFF00B4FF).withOpacity(0.7),
                strokeWidth: 3.5,
              ),
            ],
          ),

        CircleLayer(
          circles: _checkpoints.map((c) {
            final isPassed = _passedCheckpointIds.contains(c.id);
            return CircleMarker(
              point: LatLng(c.lat, c.lng),
              radius: c.radiusMeters.toDouble(),
              color: (isPassed
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFF00B4FF))
                  .withOpacity(0.08),
              borderColor: (isPassed
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFF00B4FF))
                  .withOpacity(0.4),
              borderStrokeWidth: 1.5,
              useRadiusInMeter: true,
            );
          }).toList(),
        ),

        MarkerLayer(
          markers: [
            ..._checkpoints.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              final isPassed = _passedCheckpointIds.contains(c.id);
              final isNext = c.id == _nextCheckpoint?.id;
              return Marker(
                point: LatLng(c.lat, c.lng),
                width: 100,
                height: 44,
                child: _CheckpointMarker(
                  cp: c,
                  index: i,
                  isPassed: isPassed,
                  isNext: isNext,
                  isFirst: i == 0,
                  isLast: i == _checkpoints.length - 1,
                ),
              );
            }),

            if (_myPosition != null)
              Marker(
                point: _myPosition!,
                width: 56,
                height: 56,
                child: _PulseMarker(
                  isGpsReady: _gpsReady,
                  isLive: _isLive,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Single full-bleed glass bar — fixed height 52px, no nested pill container,
  // Expanded(_GpsPill) takes all remaining width so it can never overflow.
  Widget _buildTopBar() {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: const Color(0xFF0D0D14).withOpacity(0.92),
        padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 0),
        height: topPad + 52,
        child: Row(
          children: [
            _TopButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 6),
            const Text(
              'AndoTrack',
              style: TextStyle(
                color: Color(0xFF00FF9C),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            if (_isLive)
              _LiveBadge(controller: _livePulseCtrl)
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF444460).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF444460).withOpacity(0.3)),
                ),
                child: Text(
                  _raceStatus.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF666680),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            // Expanded absorbs all remaining space — _GpsPill can never push
            // outside Row bounds regardless of GPS text length or screen width.
            Expanded(
              child: _GpsPill(
                isReady: _gpsReady,
                accuracy: _lastPosition?.accuracy,
              ),
            ),
            const SizedBox(width: 6),
            _TopButton(
              icon: Icons.settings,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingBanner() {
    // Bar ends at padding.top + 52; add 8px gap.
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPad + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1500).withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFFFFB800).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded,
                color: Color(0xFFFFB800), size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _waitingBanner,
                style: const TextStyle(
                  color: Color(0xFFFFB800),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocateMeButton() {
    return Positioned(
      right: 16,
      bottom: 240,
      child: GestureDetector(
        onTap: _centerOnMe,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14),
            shape: BoxShape.circle,
            border: Border.all(
              color: _mapMoved
                  ? const Color(0xFF00B4FF).withOpacity(0.7)
                  : const Color(0xFF1E1E30),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4), blurRadius: 8),
            ],
          ),
          child: Icon(
            _mapMoved ? Icons.my_location : Icons.my_location_outlined,
            color: _mapMoved
                ? const Color(0xFF00B4FF)
                : Colors.white54,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsButton() {
    if (!_isLive || _raceId == null) return const SizedBox.shrink();
    return Positioned(
      right: 16,
      bottom: 296,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RunnerStatsScreen(raceId: _raceId!),
            ),
          );
        },
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF1E1E30)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4), blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.leaderboard_outlined,
              color: Colors.white54, size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HudStrip(
            speedKmh: _speedKmh,
            pace: _paceStr,
            distance: _distanceStr,
            accuracyLabel: _accuracyLabel,
            accuracyColor: _accuracyColor,
            isLive: _isLive,
            isOnline: _isOnline,
          ),
          _CheckpointProgressBar(
            checkpoints: _checkpoints,
            passedIds: _passedCheckpointIds,
            nextCheckpoint: _nextCheckpoint,
          ),
        ],
      ),
    );
  }
}

// ── LIVE badge ────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  final AnimationController controller;
  const _LiveBadge({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final opacity = 0.6 + 0.4 * controller.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF00FF9C).withOpacity(0.15 * opacity),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: const Color(0xFF00FF9C).withOpacity(0.5 * opacity)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFF00FF9C).withOpacity(0.6),
                    const Color(0xFF00FF9C),
                    controller.value,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Color.lerp(
                    const Color(0xFF00CC7A),
                    const Color(0xFF00FF9C),
                    controller.value,
                  ),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── HUD strip ─────────────────────────────────────────────────────────────────

class _HudStrip extends StatelessWidget {
  final double speedKmh;
  final String pace;
  final String distance;
  final String accuracyLabel;
  final Color accuracyColor;
  final bool isLive;
  final bool isOnline;

  const _HudStrip({
    required this.speedKmh,
    required this.pace,
    required this.distance,
    required this.accuracyLabel,
    required this.accuracyColor,
    required this.isLive,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _HudTile(
                  value: speedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                  accent: isLive),
              _HudDivider(),
              _HudTile(value: pace, unit: '/km pace'),
              _HudDivider(),
              _HudTile(value: distance, unit: 'dist.'),
              _HudDivider(),
              _HudTile(
                value: accuracyLabel,
                unit: 'GPS acc.',
                customColor: accuracyColor,
              ),
            ],
          ),
          if (isLive) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF00FF9C)
                        : const Color(0xFFFF4D4D),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isOnline ? 'Broadcasting' : 'Offline — queued',
                  style: TextStyle(
                    color: isOnline
                        ? const Color(0xFF00FF9C)
                        : const Color(0xFFFF4D4D),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HudTile extends StatelessWidget {
  final String value;
  final String unit;
  final bool accent;
  final Color? customColor;
  const _HudTile(
      {required this.value,
      required this.unit,
      this.accent = false,
      this.customColor});

  @override
  Widget build(BuildContext context) {
    final color = customColor ??
        (accent ? const Color(0xFF00FF9C) : Colors.white);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(unit,
              style: const TextStyle(
                  color: Color(0xFF444460), fontSize: 10)),
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

// ── Checkpoint marker ─────────────────────────────────────────────────────────

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
      bg = isPassed
          ? const Color(0xFF00FF9C)
          : const Color(0xFFFF4D4D);
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }
}

// ── Checkpoint progress bar ───────────────────────────────────────────────────

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
    final passed =
        checkpoints.where((c) => passedIds.contains(c.id)).length;
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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 2),
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

// ── Top button ────────────────────────────────────────────────────────────────

class _TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A28),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF2A2A40)),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}

// ── GPS pill ──────────────────────────────────────────────────────────────────

class _GpsPill extends StatelessWidget {
  final bool isReady;
  final double? accuracy;
  const _GpsPill({required this.isReady, this.accuracy});

  @override
  Widget build(BuildContext context) {
    final color =
        isReady ? const Color(0xFF00FF9C) : const Color(0xFFFFB800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF111120),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReady ? Icons.gps_fixed : Icons.gps_not_fixed,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              isReady
                  ? 'GPS ±${accuracy?.toStringAsFixed(0) ?? '--'}m'
                  : 'Acquiring…',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulse marker ──────────────────────────────────────────────────────────────

class _PulseMarker extends StatefulWidget {
  final bool isGpsReady;
  final bool isLive;
  const _PulseMarker({required this.isGpsReady, required this.isLive});

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
        duration: const Duration(milliseconds: 1500))
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
    final color = widget.isLive
        ? const Color(0xFF00FF9C)
        : widget.isGpsReady
            ? const Color(0xFF00B4FF)
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

// ── Data class ────────────────────────────────────────────────────────────────

class _CheckpointData {
  final int id;
  final String name;
  final double lat;
  final double lng;
  final int radiusMeters;
  final int orderNumber;

  const _CheckpointData({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.orderNumber,
  });
}
