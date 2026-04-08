// ============================================================
// ORGANIZER DASHBOARD — Full screen with all features:
// Day 19: Start/Stop race controls
// Day 21: Anomaly alerts overlay
// Day 27: All runners on map with name labels + smooth movement
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/races_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/checkpoint_placement_screen.dart';
import '../widgets/anomaly_alert_widget.dart';

// Runner colors — up to 10 distinct runners
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

  final Map<String, _RunnerState> _runners = {};
  final Map<String, LatLng> _smoothPositions = {};

  int _raceId = 1;
  String? _raceName;
  String _raceStatus = 'upcoming';
  bool _actionLoading = false;

  StreamSubscription? _firebaseSub;
  Timer? _smoothTimer;

  @override
  void initState() {
    super.initState();
    _loadRace();
  }

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
        setState(() {
          _raceId = race['id'];
          _raceName = race['name'];
          _raceStatus = race['status'] ?? 'upcoming';
        });
        await prefs.setInt('active_race_id', _raceId);
      }
    } catch (_) {}

    _listenToRunners();
    _startSmoothMovement();
  }

  void _listenToRunners() {
    _firebaseSub?.cancel();
    FirebaseDatabase.instance
        .ref('races/$_raceId/runners')
        .onValue
        .listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);

      setState(() {
        data.forEach((runnerId, value) {
          final d = Map<String, dynamic>.from(value);
          final lat = (d['lat'] as num?)?.toDouble();
          final lng = (d['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) return;

          if (!_runners.containsKey(runnerId)) {
            _runners[runnerId] = _RunnerState(
              id: runnerId,
              name: d['name'] ?? 'Runner #$runnerId',
              color: _runnerColors[_runners.length % _runnerColors.length],
              position: LatLng(lat, lng),
              speed: (d['speed'] as num?)?.toDouble() ?? 0,
            );
            _smoothPositions[runnerId] = LatLng(lat, lng);
          } else {
            _runners[runnerId] = _runners[runnerId]!.copyWith(
              targetPosition: LatLng(lat, lng),
              speed: (d['speed'] as num?)?.toDouble() ?? 0,
              name: d['name'] ?? _runners[runnerId]!.name,
            );
          }
        });
      });
    });
  }

  void _startSmoothMovement() {
    _smoothTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      bool changed = false;
      _runners.forEach((id, runner) {
        final target = runner.targetPosition ?? runner.position;
        final current = _smoothPositions[id] ?? runner.position;
        final lat = _lerp(current.latitude, target.latitude, 0.3);
        final lng = _lerp(current.longitude, target.longitude, 0.3);
        final newPos = LatLng(lat, lng);
        if ((newPos.latitude - current.latitude).abs() > 0.000001 ||
            (newPos.longitude - current.longitude).abs() > 0.000001) {
          _smoothPositions[id] = newPos;
          changed = true;
        }
      });
      if (changed && mounted) setState(() {});
    });
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Future<void> _startRace() async {
    final confirm = await _showConfirm(
      'Start Race',
      'Start "${_raceName ?? 'Race #$_raceId'}"?',
      'Start',
      const Color(0xFF00FF9C),
    );
    if (!confirm) return;
    setState(() => _actionLoading = true);
    try {
      await ApiService.startRace(_raceId);
      setState(() => _raceStatus = 'active');
      _showSnack('Race started! 🏁', const Color(0xFF00FF9C));
    } catch (e) {
      _showSnack('Failed: $e', const Color(0xFFFF4D4D));
    } finally {
      setState(() => _actionLoading = false);
    }
  }

  Future<void> _stopRace() async {
    final confirm = await _showConfirm(
      'Stop Race',
      'End "${_raceName ?? 'Race #$_raceId'}"? This ends the race for all runners.',
      'Stop',
      const Color(0xFFFF4D4D),
    );
    if (!confirm) return;
    setState(() => _actionLoading = true);
    try {
      await ApiService.stopRace(_raceId);
      setState(() => _raceStatus = 'finished');
      _showSnack('Race finished!', const Color(0xFFFFB800));
    } catch (e) {
      _showSnack('Failed: $e', const Color(0xFFFF4D4D));
    } finally {
      setState(() => _actionLoading = false);
    }
  }

  Future<bool> _showConfirm(
      String title, String msg, String action, Color color) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0D0D14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            content: Text(msg,
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 13)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF666680))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(action,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.black)),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: IndexedStack(
        index: _tab.index,
        children: [
          _buildMap(),
          LeaderboardScreen(raceId: _raceId),
          RacesScreen(onRaceSelected: (id, name, status) {
            setState(() {
              _raceId = id;
              _raceName = name;
              _raceStatus = status;
              _tab = NavTab.map;
            });
            _listenToRunners();
          }),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        current: _tab,
        onTap: (t) => setState(() => _tab = t),
      ),
      floatingActionButton: _tab == NavTab.map
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00FF9C),
              foregroundColor: Colors.black,
              child: const Icon(Icons.add_location_alt),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CheckpointPlacementScreen(raceId: _raceId),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMap() {
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
            MarkerLayer(
              markers: _runners.entries.map((e) {
                final pos = _smoothPositions[e.key] ?? e.value.position;
                return Marker(
                  point: pos,
                  width: 120,
                  height: 52,
                  child: _RunnerMarker(runner: e.value),
                );
              }).toList(),
            ),
          ],
        ),

        // Day 21: Anomaly alerts
        AnomalyAlertOverlay(raceId: _raceId),

        // Day 19: Race control panel
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: _RaceControlPanel(
            raceName: _raceName ?? 'Race #$_raceId',
            status: _raceStatus,
            runnerCount: _runners.length,
            loading: _actionLoading,
            onStart: _raceStatus == 'upcoming' ? _startRace : null,
            onStop: _raceStatus == 'active' ? _stopRace : null,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _firebaseSub?.cancel();
    _smoothTimer?.cancel();
    super.dispose();
  }
}

// ─── RUNNER MARKER ─────────────────────────────────────────────────────────
class _RunnerMarker extends StatelessWidget {
  final _RunnerState runner;
  const _RunnerMarker({required this.runner});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14).withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: runner.color.withOpacity(0.6), width: 1),
          ),
          child: Text(
            runner.name,
            style: TextStyle(
              color: runner.color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: runner.color,
            boxShadow: [
              BoxShadow(
                color: runner.color.withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── RACE CONTROL PANEL ───────────────────────────────────────────────────
class _RaceControlPanel extends StatelessWidget {
  final String raceName;
  final String status;
  final int runnerCount;
  final bool loading;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  const _RaceControlPanel({
    required this.raceName,
    required this.status,
    required this.runnerCount,
    required this.loading,
    this.onStart,
    this.onStop,
  });

  Color get _statusColor {
    switch (status) {
      case 'active':
        return const Color(0xFF00FF9C);
      case 'finished':
        return const Color(0xFFFF4D4D);
      default:
        return const Color(0xFFFFB800);
    }
  }

  String get _statusLabel {
    switch (status) {
      case 'active':
        return '● LIVE';
      case 'finished':
        return '■ FINISHED';
      default:
        return '○ UPCOMING';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            raceName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(_statusLabel,
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              const Spacer(),
              Text('👟 $runnerCount',
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 10)),
            ],
          ),
          if (onStart != null || onStop != null) ...[
            const SizedBox(height: 8),
            if (loading)
              const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00FF9C),
                  ),
                ),
              )
            else if (onStart != null)
              _ActionButton(
                label: 'Start Race',
                color: const Color(0xFF00FF9C),
                icon: Icons.play_arrow,
                onTap: onStart!,
              )
            else if (onStop != null)
              _ActionButton(
                label: 'Stop Race',
                color: const Color(0xFFFF4D4D),
                icon: Icons.stop,
                onTap: onStop!,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.label,
      required this.color,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ─── DATA CLASS ────────────────────────────────────────────────────────────
class _RunnerState {
  final String id;
  final String name;
  final Color color;
  final LatLng position;
  final LatLng? targetPosition;
  final double speed;

  _RunnerState({
    required this.id,
    required this.name,
    required this.color,
    required this.position,
    this.targetPosition,
    this.speed = 0,
  });

  _RunnerState copyWith(
      {LatLng? targetPosition, double? speed, String? name}) {
    return _RunnerState(
      id: id,
      name: name ?? this.name,
      color: color,
      position: position,
      targetPosition: targetPosition ?? this.targetPosition,
      speed: speed ?? this.speed,
    );
  }
}