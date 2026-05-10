// MOVED TO: lib/features/map/screens/map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:andotrack_app/core/services/location_service.dart';
import 'package:andotrack_app/core/services/firebase_service.dart';

class MapScreen extends StatefulWidget {
  final String raceId;
  final String runnerId;
  final List<Map<String, dynamic>> checkpoints;

  const MapScreen({
    super.key,
    required this.raceId,
    required this.runnerId,
    this.checkpoints = const [],
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final FirebaseService _firebaseService = FirebaseService();

  LatLng? _currentLatLng;
  bool _isLocating = false;
  bool _locationDenied = false;

  final List<Map<String, dynamic>> _offlineQueue = [];
  bool _isOnline = true;

  // Pulsing animation for the current-location marker
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initForegroundTask();
    _listenToConnectivity();
    _startTrackingWithAutoCenter();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  // ── Foreground service ───────────────────────────────────────────────────

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'andotrack_gps',
        channelName: 'AndoTrack GPS',
        channelDescription: 'Keeps GPS running during your race',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(3000),
        autoRunOnBoot: false,
      ),
    );
  }

  Future<void> _startForegroundService() async {
    await FlutterForegroundTask.startService(
      notificationTitle: 'AndoTrack',
      notificationText: 'GPS tracking your race...',
    );
  }

  // ── Connectivity ─────────────────────────────────────────────────────────

  void _listenToConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (mounted) setState(() => _isOnline = online);
      if (online && _offlineQueue.isNotEmpty) _syncOfflineQueue();
    });
  }

  Future<void> _syncOfflineQueue() async {
    final toSync = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();
    for (final point in toSync) {
      _firebaseService.updateRunnerLocation(
        raceId: point['raceId'],
        runnerId: point['runnerId'],
        lat: point['lat'],
        lng: point['lng'],
        speed: point['speed'],
      );
    }
  }

  // ── Location + tracking ──────────────────────────────────────────────────

  /// On startup: request permission → get current position → center map →
  /// then begin the continuous stream.
  Future<void> _startTrackingWithAutoCenter() async {
    await _startForegroundService();

    final granted = await LocationService.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() => _locationDenied = true);
        _showPermissionDialog();
      }
      return;
    }

    // Auto-center on first fix
    final initialPos = await LocationService.getCurrentLatLng();
    if (initialPos != null && mounted) {
      setState(() => _currentLatLng = initialPos);
      // Smooth animated move to current position
      _animateToPosition(initialPos, zoom: 16.5);
    }

    // Start continuous stream
    LocationService.getLocationStream().listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      if (mounted) setState(() => _currentLatLng = latLng);

      if (_isOnline) {
        _firebaseService.updateRunnerLocation(
          raceId: widget.raceId,
          runnerId: widget.runnerId,
          lat: position.latitude,
          lng: position.longitude,
          speed: position.speed,
        );
      } else {
        _offlineQueue.add({
          'raceId': widget.raceId,
          'runnerId': widget.runnerId,
          'lat': position.latitude,
          'lng': position.longitude,
          'speed': position.speed,
        });
      }
    });
  }

  /// "My Location" button handler — re-centers map on current position with
  /// smooth animation and shows a brief loading indicator.
  Future<void> _recenterOnMe() async {
    if (_isLocating) return;
    if (mounted) setState(() => _isLocating = true);

    try {
      final granted = await LocationService.requestPermission();
      if (!granted) {
        _showPermissionDialog();
        return;
      }

      final pos = await LocationService.getCurrentLatLng();
      if (pos == null) {
        _showSnack('Could not get your location. Try again.');
        return;
      }

      if (mounted) setState(() => _currentLatLng = pos);
      _animateToPosition(pos, zoom: 17.0);
    } catch (_) {
      _showSnack('Could not get your location. Try again.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Smooth animated camera pan + zoom using flutter_map's moveAndRotate.
  void _animateToPosition(LatLng target, {double zoom = 16.0}) {
    _mapController.move(target, zoom);
  }

  // ── Dialogs / snackbars ──────────────────────────────────────────────────

  void _showPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.location_off_rounded, color: Color(0xFFFF4D4D), size: 20),
          SizedBox(width: 8),
          Text('Location Required',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          'AndoTrack needs your GPS to track your race position.\n\n'
          'Please enable location permission in Settings.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B4FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final checkpointMarkers = widget.checkpoints.map((cp) {
      final lat = cp['lat'] as double;
      final lng = cp['lng'] as double;
      final name = cp['name'] ?? 'Checkpoint';
      return Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 40,
        child: Tooltip(
          message: name,
          child: const Icon(Icons.flag_rounded, size: 36, color: Color(0xFFFFB800)),
        ),
      );
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        elevation: 0,
        title: Text(
          'Race #${widget.raceId}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          // Online / offline indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Row(
                key: ValueKey(_isOnline),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: _isOnline ? const Color(0xFF00FF9C) : const Color(0xFFFF4D4D),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: _isOnline ? const Color(0xFF00FF9C) : const Color(0xFFFF4D4D),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          _currentLatLng == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: Color(0xFF00B4FF),
                        strokeWidth: 2,
                      ),
                      SizedBox(height: 16),
                      Text('Getting your location…',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLatLng!,
                    initialZoom: 16.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.andotrack_app',
                    ),
                    MarkerLayer(
                      markers: [
                        // ── Current position marker (distinct blue) ──────
                        if (_currentLatLng != null)
                          Marker(
                            point: _currentLatLng!,
                            width: 56,
                            height: 56,
                            child: _CurrentPositionMarker(
                              animation: _pulseAnimation,
                            ),
                          ),
                        // ── Checkpoint markers ────────────────────────────
                        ...checkpointMarkers,
                      ],
                    ),
                  ],
                ),

          // ── My Location FAB ──────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 32,
            child: _MyLocationButton(
              isLocating: _isLocating,
              onTap: _recenterOnMe,
            ),
          ),

          // ── Offline queue badge ──────────────────────────────────────────
          if (!_isOnline && _offlineQueue.isNotEmpty)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4D4D).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.4), blurRadius: 8),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${_offlineQueue.length} point${_offlineQueue.length == 1 ? '' : 's'} queued',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),

          // ── Location denied banner ────────────────────────────────────────
          if (_locationDenied)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFF4D4D).withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.location_off_rounded,
                      color: Color(0xFFFF4D4D), size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Location permission required to track your position.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Geolocator.openAppSettings();
                    },
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: const Text('Settings',
                        style: TextStyle(
                            color: Color(0xFF00B4FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Current position marker with pulse animation ─────────────────────────────

class _CurrentPositionMarker extends StatelessWidget {
  final Animation<double> animation;

  const _CurrentPositionMarker({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Container(
              width: 52 * animation.value,
              height: 52 * animation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00B4FF)
                    .withOpacity(0.15 * animation.value),
                border: Border.all(
                  color:
                      const Color(0xFF00B4FF).withOpacity(0.3 * animation.value),
                  width: 1.5,
                ),
              ),
            ),
            // Inner accuracy ring
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00B4FF).withOpacity(0.18),
                border: Border.all(
                  color: const Color(0xFF00B4FF).withOpacity(0.6),
                  width: 2,
                ),
              ),
            ),
            // Core dot
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF00B4FF),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF00B4FF),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── My Location FAB ───────────────────────────────────────────────────────────

class _MyLocationButton extends StatelessWidget {
  final bool isLocating;
  final VoidCallback onTap;

  const _MyLocationButton({
    required this.isLocating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          shape: BoxShape.circle,
          border: Border.all(
            color: isLocating
                ? const Color(0xFF00B4FF)
                : const Color(0xFF00B4FF).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00B4FF)
                  .withOpacity(isLocating ? 0.4 : 0.15),
              blurRadius: isLocating ? 16 : 8,
              spreadRadius: isLocating ? 2 : 0,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isLocating
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(
                  color: Color(0xFF00B4FF),
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.my_location_rounded,
                color: Color(0xFF00B4FF),
                size: 22,
              ),
      ),
    );
  }
}