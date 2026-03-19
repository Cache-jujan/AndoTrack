import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/firebase_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLatLng;
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _initForegroundTask(); // sets up the foreground service
    _startTracking();
  }

  // Sets up the notification that keeps GPS alive when screen locks
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
        eventAction: ForegroundTaskEventAction.repeat(3000), // every 3 seconds
        autoRunOnBoot: false,
      ),
    );
  }

  // Starts the foreground service (shows persistent notification)
  Future<void> _startForegroundService() async {
    await FlutterForegroundTask.startService(
      notificationTitle: 'AndoTrack',
      notificationText: 'GPS tracking your race...',
    );
  }

  void _startTracking() async {
    await _startForegroundService(); // start notification first

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);

      setState(() => _currentLatLng = latLng);

      _firebaseService.updateRunnerLocation(
        raceId: 'race1',
        runnerId: 'test-runner-jan',
        lat: position.latitude,
        lng: position.longitude,
        speed: position.speed,
      );

      print("Sent to Firebase: ${position.latitude}, ${position.longitude}");
    });
  }

  @override
  void dispose() {
    // Stop the foreground service when screen is closed
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

    return Scaffold(
      appBar: AppBar(title: const Text('Live Tracking')),
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
            ],
          ),
        ],
      ),
    );
  }
}