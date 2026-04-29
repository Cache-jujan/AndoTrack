import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class RunnerStatsScreen extends StatefulWidget {
  final int raceId;

  const RunnerStatsScreen({
    super.key,
    required this.raceId,
  });

  @override
  State<RunnerStatsScreen> createState() => _RunnerStatsScreenState();
}

class _RunnerStatsScreenState extends State<RunnerStatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loadingStats = true;

  List<Map<String, dynamic>> _leaderboard = [];
  int? _myRank;
  int? _myUserId;
  bool _loadingLeaderboard = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadLeaderboard();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _myUserId = prefs.getInt('user_id'));
  }

  Future<void> _loadStats() async {
    try {
      final data = await ApiService.getRunnerStats(widget.raceId);

      if (mounted) {
        setState(() {
          _stats = data;
          _loadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingStats = false);
      }
    }
  }

  Future<void> _loadLeaderboard() async {
    try {
      final data = await ApiService.getLeaderboard(widget.raceId);

      if (mounted) {
        setState(() {
          _leaderboard = data;
          _loadingLeaderboard = false;
        });

        if (_myUserId != null) _findRank();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLeaderboard = false);
    }
  }

  void _findRank() {
    for (int i = 0; i < _leaderboard.length; i++) {
      if (_leaderboard[i]['runner_id'] == _myUserId ||
          _leaderboard[i]['user_id'] == _myUserId) {
        setState(() => _myRank = i + 1);
        return;
      }
    }
  }

  // ── API-based computed values ─────────────────────────────

  String get _paceStr {
    if (_stats == null) return '--:--';

    final pace = _stats!['pace_sec_per_km'];
    if (pace == null) return '--:--';

    final m = (pace ~/ 60).toString().padLeft(2, '0');
    final s = (pace % 60).toInt().toString().padLeft(2, '0');

    return '$m:$s /km';
  }

  String get _distanceStr {
    if (_stats == null) return '--';

    final raw = _stats!['distance_m'];
    final dist = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;

    return dist >= 1000
        ? '${(dist / 1000).toStringAsFixed(2)} km'
        : '${dist.toStringAsFixed(0)} m';
  }

  String get _elapsedStr {
    if (_stats == null) return '--:--';

    final secs = _stats!['elapsed_sec'] ?? 0;
    final d = Duration(seconds: secs);

    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');

    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String get _etaStr {
    if (_stats == null) return '--:--';

    final secs = _stats!['eta_next_sec'];
    if (secs == null) return '--:--';

    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toInt().toString().padLeft(2, '0');

    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingStats) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00FF9C),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        foregroundColor: Colors.white,
        title: const Text(
          'Race Stats',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: const Color(0xFF1E1E30)),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF00FF9C),
        backgroundColor: const Color(0xFF0D0D14),
        onRefresh: () async {
          await _loadStats();
          await _loadLeaderboard();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionLabel('Live metrics'),
            const SizedBox(height: 10),
            _metricsGrid(),
            const SizedBox(height: 20),
            _sectionLabel('Leaderboard'),
            const SizedBox(height: 10),
            _leaderboardCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── UI helpers ───────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF444460),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );

  Widget _metricsGrid() {
    return Column(
      children: [
        Row(
          children: [
            _MetricCard(
              label: 'Pace',
              value: _paceStr,
              accent: true,
              icon: Icons.speed,
            ),
            const SizedBox(width: 10),
            _MetricCard(
              label: 'Distance',
              value: _distanceStr,
              icon: Icons.straighten,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MetricCard(
              label: 'Elapsed',
              value: _elapsedStr,
              icon: Icons.timer_outlined,
            ),
            const SizedBox(width: 10),
            _MetricCard(
              label: 'ETA',
              value: _etaStr,
              icon: Icons.navigation_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _leaderboardCard() {
    if (_loadingLeaderboard) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
            color: Color(0xFF00FF9C),
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_leaderboard.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E1E30)),
        ),
        child: const Center(
          child: Text(
            'No leaderboard data yet',
            style: TextStyle(color: Color(0xFF444460), fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E30)),
      ),
      child: Column(
        children: _leaderboard.take(10).toList().asMap().entries.map((entry) {
          final i = entry.key;
          final runner = entry.value;
          final isMe = runner['runner_id'] == _myUserId ||
              runner['user_id'] == _myUserId;
          final rank = i + 1;
          final name = runner['name'] ?? runner['runner_name'] ?? 'Runner $rank';
          final dist = (runner['distance_covered'] as num?)?.toDouble() ?? 0;

          final distStr = dist >= 1000
              ? '${(dist / 1000).toStringAsFixed(2)} km'
              : '${dist.toStringAsFixed(0)} m';

          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe
                  ? const Color(0xFF00FF9C).withValues(alpha: 0.06)
                  : Colors.transparent,
              border: i < _leaderboard.length - 1
                  ? const Border(
                      bottom: BorderSide(color: Color(0xFF1E1E30), width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                _RankBadge(rank: rank),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isMe ? '$name (you)' : name,
                    style: TextStyle(
                      color: isMe
                          ? const Color(0xFF00FF9C)
                          : const Color(0xFFCCCCDD),
                      fontSize: 13,
                      fontWeight:
                          isMe ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  distStr,
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 12),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Metric Card ────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool accent;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent
                ? const Color(0xFF00FF9C).withValues(alpha: 0.3)
                : const Color(0xFF1E1E30),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 13,
                    color: accent
                        ? const Color(0xFF00FF9C)
                        : const Color(0xFF444460)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                        color: Color(0xFF444460), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: accent ? const Color(0xFF00FF9C) : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rank Badge ─────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (rank == 1) color = const Color(0xFFFFD700);
    else if (rank == 2) color = const Color(0xFFAAAAAA);
    else if (rank == 3) color = const Color(0xFFCD7F32);
    else color = const Color(0xFF444460);

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Text(
          '$rank',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}