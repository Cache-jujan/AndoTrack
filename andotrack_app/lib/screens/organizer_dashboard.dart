import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/race_runners_providers.dart';
import '../models/runner_model.dart';
import '../widgets/app_bottom_nav.dart';
import 'settings_screen.dart';
import 'checkpoint_placement_screen.dart';
import '../services/checkpoint_service.dart';

class OrganizerDashboard extends ConsumerStatefulWidget {
  final String raceId;

  const OrganizerDashboard({super.key, required this.raceId});

  @override
  ConsumerState<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends ConsumerState<OrganizerDashboard> {
  final MapController _mapController = MapController();
  bool _followFirstRunner = true;
  NavTab _currentTab = NavTab.map;
  List<Map<String, dynamic>> _checkpoints = []; // ← added

  static const String _darkTileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  @override
  void initState() {
    super.initState();
    _loadCheckpoints(); // ← added
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  // ── Load checkpoints from API ─────────────────────────
  Future<void> _loadCheckpoints() async {
    final data = await CheckpointService.getCheckpoints(
      int.tryParse(widget.raceId) ?? 1,
    );
    setState(() => _checkpoints = data.cast<Map<String, dynamic>>());
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _panToFirstRunner(List<RunnerModel> runners) {
    if (_followFirstRunner && runners.isNotEmpty) {
      _mapController.move(
        LatLng(runners.first.lat, runners.first.lng),
        16.0,
      );
      _followFirstRunner = false;
    }
  }

  Color _runnerColor(int index) {
    const colors = [
      Color(0xFF00FF9C),
      Color(0xFF00B4FF),
      Color(0xFFFFB800),
      Color(0xFFFF4D9E),
      Color(0xFFBD00FF),
    ];
    return colors[index % colors.length];
  }

  Widget _buildMapView(List<RunnerModel> runners) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(10.3157, 123.8854),
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: _darkTileUrl,
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.andotrack_app',
            ),

            // ── Checkpoint radius circles ─────────────────
            CircleLayer(
              circles: _checkpoints.map((cp) => CircleMarker(
                point: LatLng(
                  (cp['lat'] as num).toDouble(),
                  (cp['lng'] as num).toDouble(),
                ),
                radius: (cp['radius_meters'] as num).toDouble(),
                color: const Color(0xFF00B4FF).withOpacity(0.1),
                borderColor: const Color(0xFF00B4FF).withOpacity(0.5),
                borderStrokeWidth: 1.5,
                useRadiusInMeter: true,
              )).toList(),
            ),

            // ── Checkpoint markers ────────────────────────
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
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0D14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF00B4FF).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          cp['name'] ?? '',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

            // ── Runner markers ────────────────────────────
            MarkerLayer(
              markers: runners.asMap().entries.map((entry) {
                final index = entry.key;
                final runner = entry.value;
                final color = _runnerColor(index);
                return Marker(
                  point: LatLng(runner.lat, runner.lng),
                  width: 72,
                  height: 72,
                  child: GestureDetector(
                    onTap: () => _showRunnerDialog(runner, color),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withOpacity(0.1),
                            border: Border.all(
                              color: color.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                        ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Top gradient
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 110,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A0A0F).withOpacity(0.95),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Runner count badge
        Positioned(
          top: 12,
          left: 16,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_run_rounded, size: 15, color: Color(0xFF00FF9C)),
                  const SizedBox(width: 6),
                  Text(
                    runners.isEmpty ? 'Waiting for runners...' : '${runners.length} active',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Recenter button
        Positioned(
          right: 16,
          top: 12,
          child: SafeArea(
            child: GestureDetector(
              onTap: () {
                setState(() => _followFirstRunner = true);
                final runners = ref.read(raceRunnersProvider(widget.raceId)).valueOrNull ?? [];
                _panToFirstRunner(runners);
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded, color: Color(0xFF00FF9C), size: 20),
              ),
            ),
          ),
        ),

        // Runner list panel
        if (runners.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Text('RUNNERS', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF00FF9C).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text('${runners.length}', style: const TextStyle(color: Color(0xFF00FF9C), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: runners.length,
                      itemBuilder: (context, index) {
                        final runner = runners[index];
                        final color = _runnerColor(index);
                        return GestureDetector(
                          onTap: () => _mapController.move(LatLng(runner.lat, runner.lng), 17.0),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color.withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                  child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold))),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Runner ${index + 1}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                                      Text('${runner.lat.toStringAsFixed(4)}, ${runner.lng.toStringAsFixed(4)}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, fontFamily: 'monospace')),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${(runner.speed * 3.6).toStringAsFixed(1)} km/h', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text(_formatTime(runner.lastUpdated), style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Empty state
        if (runners.isEmpty)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF00FF9C).withOpacity(0.6))),
                  const SizedBox(width: 12),
                  Text('Waiting for runners to join...', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showRunnerDialog(RunnerModel runner, Color color) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D0D14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: color.withOpacity(0.3))),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: const Icon(Icons.directions_run, color: Colors.black, size: 18)),
                  const SizedBox(width: 12),
                  Text(runner.runnerId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 16),
              _DialogRow(label: 'Latitude', value: runner.lat.toStringAsFixed(6), color: color),
              _DialogRow(label: 'Longitude', value: runner.lng.toStringAsFixed(6), color: color),
              _DialogRow(label: 'Speed', value: '${(runner.speed * 3.6).toStringAsFixed(1)} km/h', color: color),
              _DialogRow(label: 'Updated', value: _formatTime(runner.lastUpdated), color: color),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(backgroundColor: color.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: Text('Close', style: TextStyle(color: color)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runnersAsync = ref.watch(raceRunnersProvider(widget.raceId));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AndoTrack', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
            Text('Race ${widget.raceId} · Live', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
          ],
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
      ),
      floatingActionButton: _currentTab == NavTab.map
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00B4FF),
              tooltip: 'Place Checkpoints',
              child: const Icon(Icons.flag_rounded, color: Colors.black),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckpointPlacementScreen(
                      raceId: int.tryParse(widget.raceId) ?? 1,
                    ),
                  ),
                );
                _loadCheckpoints(); // ← reload after returning
              },
            )
          : null,
      body: _currentTab == NavTab.settings
          ? const SettingsScreen()
          : runnersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00FF9C), strokeWidth: 2)),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFFF4D4D)),
                    const SizedBox(height: 12),
                    Text('Error: $err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
              data: (runners) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _panToFirstRunner(runners));
                return _buildMapView(runners);
              },
            ),
      bottomNavigationBar: AppBottomNav(
        currentTab: _currentTab,
        onTabSelected: (tab) => setState(() => _currentTab = tab),
      ),
    );
  }
}

class _DialogRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DialogRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}