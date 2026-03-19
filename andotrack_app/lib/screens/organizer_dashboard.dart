import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/race_runners_providers.dart';
import '../models/runner_model.dart';

class OrganizerDashboard extends ConsumerStatefulWidget {
  final String raceId;

  const OrganizerDashboard({super.key, required this.raceId});

  @override
  ConsumerState<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends ConsumerState<OrganizerDashboard> {
  final MapController _mapController = MapController();
  bool _followFirstRunner = true;

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

  @override
  Widget build(BuildContext context) {
    final runnersAsync = ref.watch(raceRunnersProvider(widget.raceId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Race ${widget.raceId} — Live Map'),
        backgroundColor: Colors.blue,
        actions: [
          // Re-center button
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Re-center on runners',
            onPressed: () {
              setState(() => _followFirstRunner = true);
              runnersAsync.whenData((runners) {
                _panToFirstRunner(runners);
              });
            },
          ),
        ],
      ),
      body: runnersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text('Error: $err', textAlign: TextAlign.center),
            ],
          ),
        ),
        data: (runners) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _panToFirstRunner(runners);
          });

          return Stack(
            children: [

              // ── MAP ──────────────────────────────────────────
              FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: LatLng(10.3157, 123.8854), // Cebu City
                  initialZoom: 14,
                ),
                children: [

                  // OpenStreetMap tiles — 100% free, no API key
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.andotrack_app',
                  ),

                  // Runner markers layer
                  MarkerLayer(
                    markers: runners.map((runner) {
                      return Marker(
                        point: LatLng(runner.lat, runner.lng),
                        width: 60,
                        height: 60,
                        child: GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text('Runner ${runner.runnerId}'),
                                content: Text(
                                  'Lat: ${runner.lat.toStringAsFixed(5)}\n'
                                  'Lng: ${runner.lng.toStringAsFixed(5)}\n'
                                  'Speed: ${runner.speed.toStringAsFixed(1)} m/s\n'
                                  'Updated: ${_formatTime(runner.lastUpdated)}',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Runner ID label above the dot
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  runner.runnerId.length > 4
                                      ? runner.runnerId.substring(0, 4)
                                      : runner.runnerId,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Blue moving dot
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.4),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ],
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

              // ── RUNNER COUNT BADGE (top left) ─────────────────
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.directions_run,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        runners.isEmpty
                            ? 'Waiting for runners...'
                            : '${runners.length} runner${runners.length == 1 ? '' : 's'} active',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── RUNNER LIST PANEL (bottom) ────────────────────
              if (runners.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 8),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle visual
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: runners.length,
                            itemBuilder: (context, index) {
                              final runner = runners[index];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.blue,
                                  child: Text(
                                    runner.runnerId.length > 2
                                        ? runner.runnerId
                                            .substring(0, 2)
                                            .toUpperCase()
                                        : runner.runnerId.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text('Runner ${runner.runnerId}'),
                                subtitle: Text(
                                  '${runner.lat.toStringAsFixed(5)}, '
                                  '${runner.lng.toStringAsFixed(5)}  •  '
                                  '${runner.speed.toStringAsFixed(1)} m/s',
                                ),
                                trailing: Text(
                                  _formatTime(runner.lastUpdated),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                // Tap a row → pan map to that runner
                                onTap: () {
                                  _mapController.move(
                                    LatLng(runner.lat, runner.lng),
                                    17.0,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}