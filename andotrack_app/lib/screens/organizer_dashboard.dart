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

  // Checkpoints for polyline
  List<Map<String, dynamic>> _checkpoints = [];

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
    _loadCheckpoints();
  }

  Future<void> _loadCheckpoints() async {
    try {
      final data = await ApiService.getCheckpoints(_raceId);
      if (mounted) {
        setState(() {
          _checkpoints = data
            ..sort((a, b) =>
                (a['order_number'] as num).compareTo(b['order_number'] as num));
        });
      }
    } catch (_) {}
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

  // Show runner detail bottom sheet when a marker is tapped
  void _showRunnerDetail(_RunnerState runner) {
    final speedKmh = runner.speed * 3.6;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF1E1E2E))),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: runner.color.withOpacity(0.15),
                    border: Border.all(
                        color: runner.color.withOpacity(0.4), width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _initials(runner.name),
                      style: TextStyle(
                          color: runner.color,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        runner.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'ID: ${runner.id}',
                        style: const TextStyle(
                            color: Color(0xFF444460), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Status dot
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF9C).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF00FF9C).withOpacity(0.3)),
                  ),
                  child: const Text(
                    '● Tracking',
                    style: TextStyle(
                        color: Color(0xFF00FF9C),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF1E1E2E), height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                _DetailStat(
                  label: 'Speed',
                  value: '${speedKmh.toStringAsFixed(1)} km/h',
                  color: runner.color,
                ),
                Container(
                    width: 0.5,
                    height: 36,
                    color: const Color(0xFF1E1E2E),
                    margin: const EdgeInsets.symmetric(horizontal: 4)),
                _DetailStat(
                  label: 'Pace',
                  value: runner.speed > 0.3
                      ? '${(1000 ~/ runner.speed ~/ 60).toString().padLeft(2, '0')}:${((1000 / runner.speed).toInt() % 60).toString().padLeft(2, '0')} /km'
                      : '--:-- /km',
                  color: Colors.white,
                ),
                Container(
                    width: 0.5,
                    height: 36,
                    color: const Color(0xFF1E1E2E),
                    margin: const EdgeInsets.symmetric(horizontal: 4)),
                _DetailStat(
                  label: 'Position',
                  value:
                      '${runner.position.latitude.toStringAsFixed(4)}, ${runner.position.longitude.toStringAsFixed(4)}',
                  color: const Color(0xFF666680),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _mapController.move(runner.position, 17);
                },
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('Locate on map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: runner.color,
                  side: BorderSide(color: runner.color.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
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
              _checkpoints = [];
            });
            _listenToRunners();
            _loadCheckpoints();
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
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CheckpointPlacementScreen(raceId: _raceId),
                  ),
                );
                _loadCheckpoints(); // refresh after returning
              },
            )
          : null,
    );
  }

  Widget _buildMap() {
    // Build checkpoint polyline points
    final polylinePoints = _checkpoints
        .map((c) => LatLng(
              (c['lat'] as num).toDouble(),
              (c['lng'] as num).toDouble(),
            ))
        .toList();

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

            // Checkpoint route polyline
            if (polylinePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    color: const Color(0xFF00B4FF).withOpacity(0.5),
                    strokeWidth: 2.5,
                    isDotted: true,
                  ),
                ],
              ),

            // Checkpoint circle radii
            CircleLayer(
              circles: _checkpoints.asMap().entries.map((entry) {
                final i = entry.key;
                final cp = entry.value;
                final isFirst = i == 0;
                final isLast = i == _checkpoints.length - 1;
                final color = isFirst
                    ? const Color(0xFF00FF9C)
                    : isLast
                        ? const Color(0xFFFF4D4D)
                        : const Color(0xFF00B4FF);
                return CircleMarker(
                  point: LatLng(
                    (cp['lat'] as num).toDouble(),
                    (cp['lng'] as num).toDouble(),
                  ),
                  radius: (cp['radius_meters'] as num).toDouble(),
                  useRadiusInMeter: true,
                  color: color.withOpacity(0.08),
                  borderColor: color.withOpacity(0.4),
                  borderStrokeWidth: 1.5,
                );
              }).toList(),
            ),

            // Checkpoint markers (start/end/numbered)
            MarkerLayer(
              markers: [
                ..._checkpoints.asMap().entries.map((entry) {
                  final i = entry.key;
                  final cp = entry.value;
                  final isFirst = i == 0;
                  final isLast = i == _checkpoints.length - 1;
                  return Marker(
                    point: LatLng(
                      (cp['lat'] as num).toDouble(),
                      (cp['lng'] as num).toDouble(),
                    ),
                    width: 50,
                    height: 56,
                    child: _CheckpointPin(
                      label: cp['name'] ?? '${i + 1}',
                      index: i,
                      isFirst: isFirst,
                      isLast: isLast,
                    ),
                  );
                }),
              ],
            ),

            // Runner markers (tappable)
            MarkerLayer(
              markers: _runners.entries.map((e) {
                final pos = _smoothPositions[e.key] ?? e.value.position;
                return Marker(
                  point: pos,
                  width: 130,
                  height: 52,
                  child: GestureDetector(
                    onTap: () => _showRunnerDetail(e.value),
                    child: _RunnerMarker(runner: e.value),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Anomaly alerts overlay
        AnomalyAlertOverlay(raceId: _raceId),

        // Summary strip + race control
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary stats strip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E1E30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                        _StatusPill(status: _raceStatus),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _SummaryTile(
                          value: '${_runners.length}',
                          label: 'Runners',
                          color: const Color(0xFF00FF9C),
                        ),
                        _SummaryDivider(),
                        _SummaryTile(
                          value: '${_checkpoints.length}',
                          label: 'Checkpoints',
                          color: const Color(0xFF00B4FF),
                        ),
                        _SummaryDivider(),
                        _SummaryTile(
                          value: _raceStatus == 'active'
                              ? 'Live'
                              : _raceStatus == 'finished'
                                  ? 'Done'
                                  : 'Ready',
                          label: 'Status',
                          color: _raceStatus == 'active'
                              ? const Color(0xFF00FF9C)
                              : _raceStatus == 'finished'
                                  ? const Color(0xFF666680)
                                  : const Color(0xFFFFB800),
                        ),
                        if (!_actionLoading &&
                            (_raceStatus == 'upcoming' ||
                                _raceStatus == 'active')) ...[
                          _SummaryDivider(),
                          GestureDetector(
                            onTap: _raceStatus == 'upcoming'
                                ? _startRace
                                : _stopRace,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _raceStatus == 'upcoming'
                                    ? const Color(0xFF00FF9C).withOpacity(0.15)
                                    : const Color(0xFFFF4D4D).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _raceStatus == 'upcoming'
                                      ? const Color(0xFF00FF9C).withOpacity(0.4)
                                      : const Color(0xFFFF4D4D).withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _raceStatus == 'upcoming'
                                        ? Icons.play_arrow
                                        : Icons.stop,
                                    size: 14,
                                    color: _raceStatus == 'upcoming'
                                        ? const Color(0xFF00FF9C)
                                        : const Color(0xFFFF4D4D),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _raceStatus == 'upcoming'
                                        ? 'Start'
                                        : 'Stop',
                                    style: TextStyle(
                                      color: _raceStatus == 'upcoming'
                                          ? const Color(0xFF00FF9C)
                                          : const Color(0xFFFF4D4D),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (_actionLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00FF9C)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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

// ─── CHECKPOINT PIN ──────────────────────────────────────────────────────────
class _CheckpointPin extends StatelessWidget {
  final String label;
  final int index;
  final bool isFirst;
  final bool isLast;

  const _CheckpointPin({
    required this.label,
    required this.index,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    if (isFirst) {
      color = const Color(0xFF00FF9C);
      icon = Icons.flag;
    } else if (isLast) {
      color = const Color(0xFFFF4D4D);
      icon = Icons.flag_rounded;
    } else {
      color = const Color(0xFF00B4FF);
      icon = Icons.location_on;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 1)
            ],
          ),
          child: Icon(icon, color: Colors.black, size: 14),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(
            isFirst ? 'Start' : isLast ? 'Finish' : '${index + 1}',
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ─── STATUS PILL ─────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'active':
        color = const Color(0xFF00FF9C);
        label = '● LIVE';
        break;
      case 'finished':
        color = const Color(0xFF666680);
        label = '■ FINISHED';
        break;
      default:
        color = const Color(0xFFFFB800);
        label = '○ UPCOMING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      ),
    );
  }
}

// ─── SUMMARY TILES ───────────────────────────────────────────────────────────
class _SummaryTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _SummaryTile(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF444460), fontSize: 10)),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 0.5,
        height: 28,
        color: const Color(0xFF1E1E30),
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );
}

// ─── DETAIL STAT (bottom sheet) ──────────────────────────────────────────────
class _DetailStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _DetailStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF444460), fontSize: 11),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ─── RUNNER MARKER ───────────────────────────────────────────────────────────
class _RunnerMarker extends StatelessWidget {
  final _RunnerState runner;
  const _RunnerMarker({required this.runner});

  @override
  Widget build(BuildContext context) {
    final speedKmh = runner.speed * 3.6;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D14).withOpacity(0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: runner.color.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                runner.name,
                style: TextStyle(
                    color: runner.color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              if (runner.speed > 0)
                Text(
                  '${speedKmh.toStringAsFixed(1)} km/h',
                  style: const TextStyle(
                      color: Color(0xFF666680), fontSize: 9),
                ),
            ],
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
                  spreadRadius: 1)
            ],
          ),
        ),
      ],
    );
  }
}

// ─── DATA CLASSES ─────────────────────────────────────────────────────────────
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