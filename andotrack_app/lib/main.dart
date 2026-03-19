import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _checkLocationPermission();
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _checkLocationPermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    print('❌ Location services are disabled.');
    return;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      print('❌ Location permission denied.');
      return;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    print('❌ Location permission permanently denied.');
    return;
  }

  print('✅ Location permission granted.');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AndoTrack',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LocationGate(),
    );
  }
}

class LocationGate extends StatefulWidget {
  const LocationGate({super.key});

  @override
  State<LocationGate> createState() => _LocationGateState();
}

// 👇 Added WidgetsBindingObserver
class _LocationGateState extends State<LocationGate> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 👈 register observer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestLocation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 👈 clean up
    super.dispose();
  }

  // 👇 Re-checks location every time user returns from Settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRequestLocation();
    }
  }

  Future<void> _checkAndRequestLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _showLocationServiceDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await _showPermissionDeniedDialog();
      return;
    }

    // ✅ Location is ready
    print('✅ Location permission granted.');
  }

  Future<void> _showLocationServiceDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
          'AndoTrack needs your GPS to track race positions. '
          'Please turn on Location Services.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Turn On'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionDeniedDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permission Denied'),
        content: const Text(
          'Location permission was denied. '
          'Please enable it manually in App Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}