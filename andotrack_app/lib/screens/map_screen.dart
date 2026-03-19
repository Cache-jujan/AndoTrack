import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firebase_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  void _startTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      setState(() => _currentPosition = position);
      _firebaseService.updateRunnerLocation(
        raceId: 'race1', // hardcoded for now :>
        runnerId: 'test-runner-jan', // hardcoded for now :>
        lat: position.latitude,
        lng: position.longitude,
        speed: position.speed,
      );
      print ("Sent to Firebase: ${position.latitude}, ${position.longitude}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Tracking')),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(10.3157, 123.8854),
          zoom: 14,
        ),
        onMapCreated: (controller) => _mapController = controller,
        myLocationEnabled: true,
      ),
    );
  }
}