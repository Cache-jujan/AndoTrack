import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/services/notification_service.dart';
import 'package:andotrack_app/features/auth/screens/login_screen.dart';
import 'package:andotrack_app/features/race/screens/public_race_dashboard.dart';
import 'package:andotrack_app/roles/race_director/shell/race_director_shell.dart';
import 'package:andotrack_app/roles/checkin_staff/shell/checkin_staff_shell.dart';
import 'package:andotrack_app/roles/kit_staff/shell/kit_staff_shell.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseAuth.instance.signInAnonymously().ignore();
  await NotificationService.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AndoTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthGate(),
    );
  }
}

// Checks stored JWT on startup and routes to the right screen
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestLocation();
      _checkExistingSession();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRequestLocation();
    }
  }

  Future<void> _checkExistingSession() async {
    final token = await ApiService.getToken();
    final role = await ApiService.getRole();

    if (token == null || role == null) return;
    if (!mounted) return;

    if (role == 'organizer' || role == 'race_director') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RaceDirectorShell()),
      );
    } else if (role == 'checkin_staff') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CheckinStaffShell()),
      );
    } else if (role == 'kit_staff') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const KitStaffShell()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RunnerDashboardScreen()),
      );
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
    return kIsWeb ? const PublicRaceDashboard() : const LoginScreen();
  }
}