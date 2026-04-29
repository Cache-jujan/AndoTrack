import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/firebase_service.dart';

class MapScreen extends StatefulWidget {
  final String raceId;
  final String runnerId;
  final List<Map<String, dynamic>> checkpoints; // from race join screen

  const MapScreen({
    super.key,
    required this.raceId,
    required this.runnerId,
    this.checkpoints = const [],
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLatLng;
  final FirebaseService _firebaseService = FirebaseService();

  final List<Map<String, dynamic>> _offlineQueue = [];
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _listenToConnectivity();
    _startTracking();
  }

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

  void _listenToConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      setState(() => _isOnline = online);

      if (online && _offlineQueue.isNotEmpty) {
        print('🌐 Back online! Syncing ${_offlineQueue.length} queued points...');
        _syncOfflineQueue();
      }
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
      print('📤 Synced queued point: ${point['lat']}, ${point['lng']}');
    }
  }

  void _startTracking() async {
    await _startForegroundService();

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _currentLatLng = latLng);

      if (_isOnline) {
        _firebaseService.updateRunnerLocation(
          raceId: widget.raceId,       // ✅ real race
          runnerId: widget.runnerId,   // ✅ real runner
          lat: position.latitude,
          lng: position.longitude,
          speed: position.speed,
        );
        print('📍 Sent to Firebase: ${position.latitude}, ${position.longitude}');
      } else {
        _offlineQueue.add({
          'raceId': widget.raceId,
          'runnerId': widget.runnerId,
          'lat': position.latitude,
          'lng': position.longitude,
          'speed': position.speed,
        });
        print('📦 Offline! Queued point #${_offlineQueue.length}: ${position.latitude}, ${position.longitude}');
      }
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLatLng == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Build checkpoint markers from the joined race
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
          child: const Icon(Icons.flag, size: 36, color: Colors.blue),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Race: ${widget.raceId}'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              _isOnline ? Icons.wifi : Icons.wifi_off,
              color: _isOnline ? Colors.green : Colors.red,
            ),
          )
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _currentLatLng!,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: 'com.example.andotrack_app',
          ),
          MarkerLayer(
            markers: [
              // Runner's own position
              Marker(
                point: _currentLatLng!,
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_pin,
                  size: 50,
                  color: Colors.red,
                ),
              ),
              // Checkpoint markers
              ...checkpointMarkers,
            ],
          ),
        ],
      ),
    );
  }
}