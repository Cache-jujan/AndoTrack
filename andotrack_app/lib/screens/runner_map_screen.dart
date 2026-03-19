import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firebase_service.dart';
import '../services/api_service.dart';
import '../services/checkpoint_service.dart'; // ← added
import 'login_screen.dart';

class RunnerMapScreen extends StatefulWidget {
  const RunnerMapScreen({super.key});

  @override
  State<RunnerMapScreen> createState() => _RunnerMapScreenState();
}

class _RunnerMapScreenState extends State<RunnerMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final FirebaseService _firebaseService = FirebaseService();

  Position? _currentPosition;
  bool _isTracking = false;
  List<Map<String, dynamic>> _checkpoints = []; // ← added

  final String _raceId = 'race1';
  late final String _runnerId;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const String _darkTileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _runnerId = 'runner_${DateTime.now().millisecondsSinceEpoch}';
    _loadCheckpoints(); // ← added

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _startTracking();
  }

  // ── Load checkpoints ──────────────────────────────────
  Future<void> _loadCheckpoints() async {
    final data = await CheckpointService.getCheckpoints(1);
    setState(() => _checkpoints = data.cast<Map<String, dynamic>>());
  }

  @override
  void dispose() {
    _isTracking = false;
    _pulseController.dispose();
    super.dispose();
  }

  void _startTracking() {
    setState(() => _isTracking = true);

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (!mounted || !_isTracking) return;

      setState(() => _currentPosition = position);

      _mapController.move(LatLng(position.latitude, position.longitude), 17.0);

      _firebaseService.updateRunnerLocation(
        raceId: _raceId,
        runnerId: _runnerId,
        lat: position.latitude,
        lng: position.longitude,
        speed: position.speed,
      );
    });
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Color _accuracyColor(double accuracy) {
    if (accuracy <= 10) return const Color(0xFF00FF9C);
    if (accuracy <= 30) return const Color(0xFFFFB800);
    return const Color(0xFFFF4D4D);
  }

  String _speedToKmh(double speedMs) {
    final kmh = speedMs * 3.6;
    if (kmh < 0.5) return '0.0';
    return kmh.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // ── Dark Map ──────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: pos != null
                  ? LatLng(pos.latitude, pos.longitude)
                  : const LatLng(10.3157, 123.8854),
              initialZoom: 17,
            ),
            children: [
              TileLayer(
                urlTemplate: _darkTileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.andotrack_app',
              ),

              // ── Checkpoint radius circles ─────────────
              CircleLayer(
                circles: _checkpoints.map((cp) => CircleMarker(
                  point: LatLng(
                    (cp['lat'] as num).toDouble(),
                    (cp['lng'] as num).toDouble(),
                  ),
                  radius: (cp['radius_meters'] as num).toDouble(),
                  color: const Color(0xFF00B4FF).withOpacity(0.08),
                  borderColor: const Color(0xFF00B4FF).withOpacity(0.4),
                  borderStrokeWidth: 1.5,
                  useRadiusInMeter: true,
                )).toList(),
              ),

              // ── Checkpoint markers ────────────────────
              MarkerLayer(
                markers: _checkpoints.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cp = entry.value;
                  return Marker(
                    point: LatLng(
                      (cp['lat'] as num).toDouble(),
                      (cp['lng'] as num).toDouble(),
                    ),
                    width: 48,
                    height: 56,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B4FF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00B4FF).withOpacity(0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF00B4FF).withOpacity(0.3)),
                          ),
                          child: Text(
                            cp['name'] ?? '',
                            style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              // ── Runner marker ─────────────────────────
              if (pos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 80,
                      height: 80,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.scale(
                                scale: _pulseAnimation.value,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF00FF9C).withOpacity(0.3), width: 2),
                                  ),
                                ),
                              ),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF00FF9C).withOpacity(0.15),
                                  border: Border.all(color: const Color(0xFF00FF9C).withOpacity(0.6), width: 1.5),
                                ),
                              ),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF00FF9C),
                                  boxShadow: [BoxShadow(color: Color(0xFF00FF9C), blurRadius: 8, spreadRadius: 2)],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0, height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFF0A0A0F).withOpacity(0.95), Colors.transparent],
                ),
              ),
            ),
          ),

          // App bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF9C).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00FF9C).withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.directions_run, color: Color(0xFF00FF9C), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text('AndoTrack', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF9C).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00FF9C).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF9C))),
                          const SizedBox(width: 5),
                          const Text('LIVE', style: TextStyle(color: Color(0xFF00FF9C), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _logout,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.logout, color: Colors.white54, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom stats panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: pos == null
                      ? const _GpsSearchingWidget()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 36, height: 3,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(2)),
                            ),
                            Row(
                              children: [
                                _DarkStatCard(label: 'SPEED', value: _speedToKmh(pos.speed), unit: 'km/h', icon: Icons.speed_rounded, color: const Color(0xFF00FF9C)),
                                const SizedBox(width: 10),
                                _DarkStatCard(label: 'ACCURACY', value: '+/-${pos.accuracy.toStringAsFixed(0)}', unit: 'm', icon: Icons.my_location_rounded, color: _accuracyColor(pos.accuracy)),
                                const SizedBox(width: 10),
                                _DarkStatCard(
                                  label: 'SIGNAL',
                                  value: pos.accuracy <= 10 ? 'GREAT' : pos.accuracy <= 30 ? 'OK' : 'WEAK',
                                  unit: '',
                                  icon: Icons.wifi_tethering_rounded,
                                  color: _accuracyColor(pos.accuracy),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withOpacity(0.07)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_rounded, size: 14, color: const Color(0xFF00FF9C).withOpacity(0.8)),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${pos.latitude.toStringAsFixed(6)},  ${pos.longitude.toStringAsFixed(6)}',
                                      style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace', letterSpacing: 0.3),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF9C), boxShadow: [BoxShadow(color: Color(0xFF00FF9C), blurRadius: 4)])),
                                  const SizedBox(width: 6),
                                  const Text('Broadcasting', style: TextStyle(color: Color(0xFF00FF9C), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsSearchingWidget extends StatelessWidget {
  const _GpsSearchingWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF00FF9C).withOpacity(0.8))),
          const SizedBox(width: 12),
          const Text('Acquiring GPS signal...', style: TextStyle(color: Colors.white38, fontSize: 13, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class _DarkStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _DarkStatCard({required this.label, required this.value, required this.unit, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold, height: 1)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(unit, style: TextStyle(color: color.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w500)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}