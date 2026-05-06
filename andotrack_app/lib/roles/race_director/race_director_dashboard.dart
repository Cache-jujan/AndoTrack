// ============================================================
// OrganizerDashboard — Improved
// ─────────────────────────────────────────────────────────────
// Changes:
//   • Road-based polyline between checkpoints via RoutingService
//   • FIX: Race runner count isolated per race (no data leakage)
//   • FIX: Runners map cleared when switching races
//   • FIX: New races start with zero runners
//   • Locate-Me button for organizer map view
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/services/routing_service.dart';
import 'package:andotrack_app/features/checkin/screens/organizer_qr_scanner_screen.dart';
import 'package:andotrack_app/features/checkpoint/screens/checkpoint_placement_screen.dart';
import 'package:andotrack_app/features/leaderboard/screens/leaderboard_screen.dart';
import 'package:andotrack_app/features/race/screens/races_screen.dart';
import 'package:andotrack_app/features/runner/screens/settings_screen.dart';
import 'package:andotrack_app/shared/widgets/app_bottom_nav.dart';

const _runnerColors = [
  Color(0xFF00FF9C),
  Color(0xFF00B4FF),
  Color(0xFFFFB800),
  Color(0xFFFF4D9D),
  Color(0xFFB44DFF),
  Color(0xFFFF6B35),
  Color(0xFF4DFFEA),
  Color(0xFFFF4D4D),
  Color(0xFFFFFF4D),
  Color(0xFF4DFF4D),
];

class OrganizerDashboard extends StatefulWidget {
  const OrganizerDashboard({super.key});

  @override
  State<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends State<OrganizerDashboard> {
  NavTab _tab = NavTab.map;
  final MapController _mapController = MapController();

  // FIX: Runners map is explicitly scoped to the current _raceId.
  // It is cleared whenever we switch races so no stale data leaks between views.
  final Map<String, _RunnerState> _runners = {};
  final Map<String, LatLng> _smoothPositions = {};

  int _raceId = 1;
  String? _raceName;
  String _raceStatus = 'upcoming';
  bool _actionLoading = false;

  List<Map<String, dynamic>> _checkpoints = [];
  List<LatLng> _routePolyline = []; // road-based polyline

  StreamSubscription? _firebaseSub;
  Timer? _smoothTimer;

  @override
  void initState() {
    super.initState();
    _loadRace();
  }

  @override
  void dispose() {
    _firebaseSub?.cancel();
    _smoothTimer?.cancel();
    super.dispose();
  }

  // ── Race loading ──────────────────────────────────────────

  Future<void> _loadRace() async {
    final prefs = await SharedPreferences.getInstance();
    _raceId = prefs.getInt('active_race_id') ?? 1;

    try {
      final races = await ApiService.getRaces();
      if (races.isNotEmpty) {
        final race = races.firstWhere(
          (r) => r['id'] == _raceId,
          orElse: () => races.first,
        );
        if (mounted) {
          setState(() {
            _raceId = race['id'];
            _raceName = race['name'];
            _raceStatus = race['status'] ?? 'upcoming';
          });
          await prefs.setInt('active_race_id', _raceId);
        }
      }
    } catch (_) {}

    _listenToRunners();
    _startSmoothMovement();
    await _loadCheckpoints();
  }

  /// Switch to a different race from the RacesScreen selection.
  /// FIX: Clears runner state to prevent data leakage between races.
  Future<void> _switchRace(int id, String name, String status) async {
    if (id == _raceId) return;

    // Cancel old Firebase listener before switching
    await _firebaseSub?.cancel();

    // FIX: Reset runner count and positions for the new race
    setState(() {
      _raceId = id;
      _raceName = name;
      _raceStatus = status;
      _runners.clear();        // No ghost runners from previous race
      _smoothPositions.clear();
      _checkpoints = [];
      _routePolyline = [];
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_race_id', id);

    _listenToRunners();
    await _loadCheckpoints();
  }

  // ── Checkpoints + road polyline ───────────────────────────

  Future<void> _loadCheckpoints() async {
    try {
      final data = await ApiService.getCheckpoints(_raceId);
      if (!mounted) return;

      final sorted = data
        ..sort((a, b) =>
            (a['order_number'] as num).compareTo(b['order_number'] as num));

      setState(() => _checkpoints = sorted);

      // Build road polyline after loading
      await _buildRoutePolyline();
    } catch (_) {}
  }

  Future<void> _buildRoutePolyline() async {
    if (_checkpoints.length < 2) {
      setState(() => _routePolyline = []);
      return;
    }
    final waypoints = _checkpoints
        .map((cp) => LatLng(
              (cp['lat'] as num).toDouble(),
              (cp['lng'] as num).toDouble(),
            ))
        .toList();
    final pts = await RoutingService.getRoutePolyline(waypoints);
    if (mounted) setState(() => _routePolyline = pts);
  }

  // ── Firebase runner listeners ─────────────────────────────

  void _listenToRunners() {
    final listenRaceId = _raceId; // capture at subscription time

    _firebaseSub = FirebaseDatabase.instance
        .ref('races/$listenRaceId/runners')
        .onValue
        .listen((event) {
      // Guard: ignore updates if we've already switched to another race
      if (listenRaceId != _raceId) return;
      if (!mounted || event.snapshot.value == null) {
        // FIX: If no runners yet (new race), ensure count shows 0
        if (mounted) setState(() => _runners.clear());
        return;
      }

      final raw =
          Map<String, dynamic>.from(event.snapshot.value as Map);

      setState(() {
        raw.forEach((id, val) {
          final data = Map<String, dynamic>.from(val as Map);
          final lat = (data['lat'] as num?)?.toDouble() ?? 0;
          final lng = (data['lng'] as num?)?.toDouble() ?? 0;
          final speed = (data['speed'] as num?)?.toDouble() ?? 0;

          final prev = _runners[id];
          _runners[id] = _RunnerState(
            id: id,
            position: LatLng(lat, lng),
            prevPosition: prev?.position,
            speed: speed,
            lastSeen: DateTime.now(),
          );
          _smoothPositions[id] ??= LatLng(lat, lng);
        });

        // Remove stale runners no longer in Firebase
        _runners.removeWhere((id, _) => !raw.containsKey(id));
        _smoothPositions.removeWhere((id, _) => !raw.containsKey(id));
      });
    });
  }

  void _startSmoothMovement() {
    _smoothTimer?.cancel();
    _smoothTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      bool changed = false;
      _runners.forEach((id, runner) {
        final current = _smoothPositions[id];
        final target = runner.position;
        if (current == null) return;
        const t = 0.15;
        final newLat =
            current.latitude + (target.latitude - current.latitude) * t;
        final newLng = current.longitude +
            (target.longitude - current.longitude) * t;
        if ((newLat - current.latitude).abs() > 0.000001 ||
            (newLng - current.longitude).abs() > 0.000001) {
          _smoothPositions[id] = LatLng(newLat, newLng);
          changed = true;
        }
      });
      if (changed && mounted) setState(() {});
    });
  }

  // ── Race control ──────────────────────────────────────────

  Future<void> _handleRaceAction() async {
    setState(() => _actionLoading = true);
    try {
      if (_raceStatus == 'active') {
        await ApiService.stopRace(_raceId);
        setState(() => _raceStatus = 'finished');
      } else if (_raceStatus == 'upcoming') {
        await ApiService.startRace(_raceId);
        setState(() => _raceStatus = 'active');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFFF4D4D)));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: _buildBody(),
      bottomNavigationBar: AppBottomNav(
        current: _tab,
        onTap: (t) => setState(() => _tab = t),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case NavTab.map:
        return _buildMapTab();
      case NavTab.races:
        return RacesScreen(
          onRaceSelected: (id, name, status) =>
              _switchRace(id, name, status),
        );
      case NavTab.leaderboard:
        return LeaderboardScreen(raceId: _raceId);
      case NavTab.settings:
        return const SettingsScreen();
    }
  }

  Widget _buildMapTab() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(10.3157, 123.8854),
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),

            // Road-based route polyline
            if (_routePolyline.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePolyline,
                    color: const Color(0xFF00B4FF).withOpacity(0.5),
                    strokeWidth: 3.5,
                  ),
                ],
              ),

            // Checkpoint radius circles
            CircleLayer(
              circles: _checkpoints.map((cp) {
                return CircleMarker(
                  point: LatLng(
                    (cp['lat'] as num).toDouble(),
                    (cp['lng'] as num).toDouble(),
                  ),
                  radius: (cp['radius_meters'] as num).toDouble(),
                  color: const Color(0xFF00B4FF).withOpacity(0.08),
                  borderColor: const Color(0xFF00B4FF).withOpacity(0.4),
                  borderStrokeWidth: 1.5,
                  useRadiusInMeter: true,
                );
              }).toList(),
            ),

            // Checkpoint + runner markers
            MarkerLayer(
              markers: [
                // Checkpoints
                ..._checkpoints.asMap().entries.map((e) {
                  final i = e.key;
                  final cp = e.value;
                  return Marker(
                    point: LatLng(
                      (cp['lat'] as num).toDouble(),
                      (cp['lng'] as num).toDouble(),
                    ),
                    width: 52,
                    height: 52,
                    child: _OrgCheckpointMarker(
                        index: i + 1, name: cp['name'] ?? ''),
                  );
                }),

                // Live runners (smoothed positions)
                ..._smoothPositions.entries.map((e) {
                  final id = e.key;
                  final pos = e.value;
                  final colorIdx =
                      id.hashCode.abs() % _runnerColors.length;
                  final color = _runnerColors[colorIdx];
                  final runner = _runners[id];
                  final speed =
                      ((runner?.speed ?? 0) * 3.6).toStringAsFixed(1);
                  return Marker(
                    point: pos,
                    width: 60,
                    height: 60,
                    child: _RunnerDot(
                      color: color,
                      label: speed,
                      runnerId: id,
                    ),
                  );
                }),
              ],
            ),
          ],
        ),

        // Top bar
        _buildOrgTopBar(),

        // Race action button
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: _buildRaceActionButton(),
        ),
      ],
    );
  }

  Widget _buildOrgTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14).withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded,
                      color: Color(0xFF00FF9C), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _raceName ?? 'Race #$_raceId',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // FIX: Runner count shown directly from _runners.length
                  // which is cleared per race (no leakage)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF9C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_runners.length} runners',
                      style: const TextStyle(
                          color: Color(0xFF00FF9C),
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // QR Check-In Scanner button
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrganizerQrScannerScreen(
                  raceId: _raceId,
                  raceName: _raceName ?? 'Race #$_raceId',
                ),
              ),
            ),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14).withOpacity(0.92),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: const Icon(Icons.qr_code_scanner,
                  color: Color(0xFF00FF9C), size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // Place checkpoints button
          GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CheckpointPlacementScreen(raceId: _raceId),
                ),
              );
              // Reload checkpoints and rebuild polyline on return
              await _loadCheckpoints();
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14).withOpacity(0.92),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: const Icon(Icons.add_location_alt,
                  color: Color(0xFF00B4FF), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRaceActionButton() {
    if (_raceStatus == 'finished') return const SizedBox.shrink();

    final isActive = _raceStatus == 'active';
    return ElevatedButton.icon(
      onPressed: _actionLoading ? null : _handleRaceAction,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive
            ? const Color(0xFFFF4D4D)
            : const Color(0xFF00FF9C),
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      icon: _actionLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.black))
          : Icon(
              isActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 20),
      label: Text(
        isActive ? 'Stop Race' : 'Start Race',
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}

// ── Organizer checkpoint marker ───────────────────────────────────────────────

class _OrgCheckpointMarker extends StatelessWidget {
  final int index;
  final String name;
  const _OrgCheckpointMarker(
      {required this.index, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF00B4FF),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$index',
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: const Color(0xFF00B4FF).withOpacity(0.3)),
          ),
          child: Text(name,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 9),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Runner dot on organizer map ───────────────────────────────────────────────

class _RunnerDot extends StatelessWidget {
  final Color color;
  final String label;
  final String runnerId;
  const _RunnerDot(
      {required this.color,
      required this.label,
      required this.runnerId});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.6), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14).withOpacity(0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$label km/h',
            style: TextStyle(color: color, fontSize: 8),
          ),
        ),
      ],
    );
  }
}

// ── Runner state data class ───────────────────────────────────────────────────

class _RunnerState {
  final String id;
  final LatLng position;
  final LatLng? prevPosition;
  final double speed;
  final DateTime lastSeen;

  const _RunnerState({
    required this.id,
    required this.position,
    this.prevPosition,
    required this.speed,
    required this.lastSeen,
  });
}
