import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final int raceId;
  const LeaderboardScreen({super.key, required this.raceId});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getLeaderboard(widget.raceId);
      setState(() {
        _leaderboard = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _rankColor(int index) {
    if (index == 0) return const Color(0xFFFFD700);
    if (index == 1) return const Color(0xFFC0C0C0);
    if (index == 2) return const Color(0xFFCD7F32);
    return Colors.white.withOpacity(0.4);
  }

  String _speedDisplay(dynamic speed) {
    final s = (speed as num?)?.toDouble() ?? 0.0;
    return (s * 3.6).toStringAsFixed(1);
  }

  String _paceDisplay(dynamic speed) {
    final mps = (speed as num?)?.toDouble() ?? 0.0;
    if (mps < 0.3) return '--:--';
    final spk = 1000 / mps;
    final m = (spk ~/ 60).toString().padLeft(2, '0');
    final s = (spk % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showRunnerDetail(BuildContext context, int index, Map<String, dynamic> entry) {
    final rankColor = _rankColor(index);
    final runnerId = entry['runner_id']?.toString() ?? '?';
    final name = entry['name']?.toString() ?? 'Runner #$runnerId';
    final initials = _initials(name);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
            // Handle bar
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

            // Avatar + name
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rankColor.withOpacity(0.15),
                    border: Border.all(color: rankColor.withOpacity(0.4), width: 2),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: rankColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            index < 3
                                ? ['🥇 1st Place', '🥈 2nd Place', '🥉 3rd Place'][index]
                                : 'Rank #${index + 1}',
                            style: TextStyle(
                              color: rankColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '  ·  ID: $runnerId',
                            style: const TextStyle(
                              color: Color(0xFF444460),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(color: Color(0xFF1E1E2E), height: 1),
            const SizedBox(height: 16),

            // Stats grid
            Row(
              children: [
                _DetailStat(
                  label: 'Speed',
                  value: '${_speedDisplay(entry['speed'])} km/h',
                  color: index < 3 ? rankColor : const Color(0xFF00FF9C),
                ),
                _DetailStatDivider(),
                _DetailStat(
                  label: 'Pace',
                  value: '${_paceDisplay(entry['speed'])} /km',
                  color: Colors.white,
                ),
                _DetailStatDivider(),
                _DetailStat(
                  label: 'Last update',
                  value: entry['timestamp'] != null
                      ? _formatTimestamp(entry['timestamp'])
                      : '--',
                  color: Colors.white,
                ),
              ],
            ),

            if (entry['lat'] != null && entry['lng'] != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E1E2E)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Color(0xFF444460), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${(entry['lat'] as num).toStringAsFixed(5)},  '
                      '${(entry['lng'] as num).toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: Color(0xFF444460),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  String _formatTimestamp(dynamic ts) {
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    } catch (_) {
      return ts.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leaderboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Race ${widget.raceId} · Live rankings',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 11),
            ),
          ],
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFF00FF9C),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00FF9C), strokeWidth: 2),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFFF4D4D), size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.white38),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again',
                            style: TextStyle(color: Color(0xFF00FF9C))),
                      ),
                    ],
                  ),
                )
              : _leaderboard.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.leaderboard_rounded,
                              size: 64,
                              color: Colors.white.withOpacity(0.08)),
                          const SizedBox(height: 16),
                          Text('No runners yet',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(
                            'Rankings appear once runners are active',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF00FF9C),
                      backgroundColor: const Color(0xFF0D0D14),
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _leaderboard.length,
                        itemBuilder: (context, index) {
                          final entry = _leaderboard[index];
                          final rankColor = _rankColor(index);
                          final isTop3 = index < 3;
                          final runnerId =
                              entry['runner_id']?.toString() ?? '?';
                          final name = entry['name']?.toString() ??
                              'Runner #$runnerId';

                          return GestureDetector(
                            onTap: () =>
                                _showRunnerDetail(context, index, entry),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: isTop3
                                    ? rankColor.withOpacity(0.05)
                                    : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isTop3
                                      ? rankColor.withOpacity(0.25)
                                      : Colors.white.withOpacity(0.07),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Rank badge
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: rankColor.withOpacity(
                                          isTop3 ? 0.15 : 0.08),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: rankColor.withOpacity(
                                            isTop3 ? 0.5 : 0.2),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: rankColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Avatar initials circle
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: rankColor.withOpacity(0.1),
                                      border: Border.all(
                                          color: rankColor.withOpacity(0.3)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _initials(name),
                                        style: TextStyle(
                                          color: rankColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Runner name + ID subtext
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withOpacity(0.85),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'ID: $runnerId',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withOpacity(0.22),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Speed
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _speedDisplay(entry['speed']),
                                            style: TextStyle(
                                              color: isTop3
                                                  ? rankColor
                                                  : const Color(0xFF00FF9C),
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 2, left: 3),
                                            child: Text(
                                              'km/h',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.3),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${_paceDisplay(entry['speed'])} /km',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.22),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Chevron hint
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white.withOpacity(0.12),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// ─── DETAIL STAT ─────────────────────────────────────────────────────────────
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
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF444460), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DetailStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 0.5,
        height: 36,
        color: const Color(0xFF1E1E2E),
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}