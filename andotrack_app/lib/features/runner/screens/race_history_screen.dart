import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/leaderboard/screens/final_results_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  RaceHistoryScreen — shows finished races for the current runner
// ─────────────────────────────────────────────────────────────────────────────
class RaceHistoryScreen extends StatefulWidget {
  const RaceHistoryScreen({super.key});

  @override
  State<RaceHistoryScreen> createState() => _RaceHistoryScreenState();
}

class _RaceHistoryScreenState extends State<RaceHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _userId = await ApiService.getUserId();
      final races = await ApiService.getRaces();
      // Filter to finished races where this user was registered
      final finished = <Map<String, dynamic>>[];
      for (final race in races) {
        if (race['status'] != 'finished') continue;
        try {
          final raceId = race['id'] as int;
          final runners = await ApiService.getRaceRunners(raceId);
          final match = runners
              .cast<Map<String, dynamic>>()
              .where((r) => r['user_id'] == _userId);
          if (match.isNotEmpty) {
            final runner = match.first;
            finished.add({
              ...race,
              '_finish_time': runner['finish_time'],
              '_rank': runner['rank'],
            });
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _history = finished;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load history.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Text(
                'Race History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00FF9C),
                        strokeWidth: 2,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.history,
                                  color: Color(0xFF444460), size: 48),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: const TextStyle(
                                      color: Color(0xFF666680),
                                      fontSize: 13)),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Retry',
                                    style: TextStyle(
                                        color: Color(0xFF00B4FF))),
                              ),
                            ],
                          ),
                        )
                      : _history.isEmpty
                          ? _buildEmpty()
                          : RefreshIndicator(
                              color: const Color(0xFF00FF9C),
                              backgroundColor: const Color(0xFF0D0D14),
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 24),
                                itemCount: _history.length,
                                itemBuilder: (ctx, i) => _HistoryCard(
                                  race: _history[i],
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FinalResultsScreen(
                                        raceId: _history[i]['id'] as int,
                                        raceName: _history[i]['name']
                                            ?.toString(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.history_toggle_off_rounded,
                size: 56,
                color: Colors.white.withOpacity(0.06),
              ),
              const SizedBox(height: 16),
              const Text(
                'No finished races yet',
                style: TextStyle(color: Color(0xFF444460), fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Complete a race to see it here',
                style: TextStyle(color: Color(0xFF2E2E48), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  History Card
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback onTap;

  const _HistoryCard({required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = race['name']?.toString() ?? 'Race';
    final distance = race['distance_km'];
    final scheduled = race['scheduled_start'];
    final finishTime = race['_finish_time']?.toString();

    String? dateLabel;
    if (scheduled != null) {
      try {
        final dt = DateTime.parse(scheduled);
        const months = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        dateLabel = '${months[dt.month]} ${dt.day}, ${dt.year}';
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + Finished badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D4D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFF4D4D).withOpacity(0.4)),
                    ),
                    child: const Text(
                      'FINISHED',
                      style: TextStyle(
                        color: Color(0xFFFF4D4D),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Date · Distance row
              Row(
                children: [
                  if (dateLabel != null) ...[
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: Color(0xFF444460)),
                    const SizedBox(width: 4),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                          color: Color(0xFF666680), fontSize: 12),
                    ),
                    if (distance != null) const SizedBox(width: 10),
                  ],
                  if (distance != null) ...[
                    const Icon(Icons.place_outlined,
                        size: 12, color: Color(0xFF444460)),
                    const SizedBox(width: 4),
                    Text(
                      '${distance}K',
                      style: const TextStyle(
                          color: Color(0xFF666680), fontSize: 12),
                    ),
                  ],
                ],
              ),

              // Finish time banner
              if (finishTime != null && finishTime.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF9C).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00FF9C).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        size: 14,
                        color: Color(0xFF00FF9C),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Finish Time: $finishTime',
                        style: const TextStyle(
                          color: Color(0xFF00FF9C),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
