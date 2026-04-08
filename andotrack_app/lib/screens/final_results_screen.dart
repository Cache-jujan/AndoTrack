// ============================================================
// FINAL RESULTS SCREEN — Day 28
// Shown after race ends on runner app, organizer dashboard,
// and public leaderboard. Fetches final leaderboard data.
// ============================================================

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class FinalResultsScreen extends StatefulWidget {
  final int raceId;
  final String? raceName;
  final bool isOrganizer;

  const FinalResultsScreen({
    super.key,
    required this.raceId,
    this.raceName,
    this.isOrganizer = false,
  });

  @override
  State<FinalResultsScreen> createState() => _FinalResultsScreenState();
}

class _FinalResultsScreenState extends State<FinalResultsScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String? _error;
  late AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getLeaderboard(widget.raceId);
      final leaderboard =
          List<Map<String, dynamic>>.from(data['leaderboard'] ?? []);
      if (mounted) {
        setState(() {
          _results = leaderboard;
          _loading = false;
        });
        _entryCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load results. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  String _formatSpeed(dynamic raw) {
    final mps = (raw as num?)?.toDouble() ?? 0.0;
    return '${(mps * 3.6).toStringAsFixed(1)} km/h';
  }

  String _formatPace(dynamic raw) {
    final mps = (raw as num?)?.toDouble() ?? 0.0;
    if (mps <= 0) return '--:--';
    final spk = 1000 / mps;
    final m = (spk ~/ 60).toString().padLeft(2, '0');
    final s = (spk % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s /km';
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00FF9C),
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFFF4D4D), size: 48),
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFF666680), fontSize: 14)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _load();
                      },
                      child: const Text('Retry',
                          style: TextStyle(color: Color(0xFF00B4FF))),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (_results.isNotEmpty) _buildPodium(),
            _buildResultsList(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 120,
      backgroundColor: const Color(0xFF0A0A0F),
      pinned: true,
      automaticallyImplyLeading: widget.isOrganizer,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D0D20), Color(0xFF0A0A0F)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🏁 RACE FINISHED',
                    style: TextStyle(
                      color: Color(0xFF00FF9C),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.raceName ?? 'Race #${widget.raceId}',
                    style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPodium() {
    final top = _results.take(3).toList();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (top.length > 1)
              Expanded(child: _PodiumBlock(rank: 2, entry: top[1], height: 90)),
            const SizedBox(width: 8),
            if (top.isNotEmpty)
              Expanded(
                  child: _PodiumBlock(rank: 1, entry: top[0], height: 120)),
            const SizedBox(width: 8),
            if (top.length > 2)
              Expanded(child: _PodiumBlock(rank: 3, entry: top[2], height: 70)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final entry = _results[i];
            final rank = i + 1;
            final delay = Duration(milliseconds: 80 * i);

            return FutureBuilder(
              future: Future.delayed(delay),
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox.shrink();
                }
                return _ResultRow(
                  rank: rank,
                  runnerId: entry['runner_id']?.toString() ?? '?',
                  speed: _formatSpeed(entry['speed']),
                  pace: _formatPace(entry['speed']),
                );
              },
            );
          },
          childCount: _results.length,
        ),
      ),
    );
  }
}

// ─── PODIUM BLOCK ──────────────────────────────────────────────────────────
class _PodiumBlock extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> entry;
  final double height;

  const _PodiumBlock(
      {required this.rank, required this.entry, required this.height});

  static const _medals = ['🥇', '🥈', '🥉'];
  static const _colors = [
    Color(0xFFFFD700),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[rank - 1];
    return Column(
      children: [
        Text(
          _medals[rank - 1],
          style: const TextStyle(fontSize: 28),
        ),
        const SizedBox(height: 4),
        Text(
          'Runner #${entry['runner_id'] ?? '?'}',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: color.withOpacity(0.4), width: 1),
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── RESULT ROW ────────────────────────────────────────────────────────────
class _ResultRow extends StatelessWidget {
  final int rank;
  final String runnerId;
  final String speed;
  final String pace;

  const _ResultRow({
    required this.rank,
    required this.runnerId,
    required this.speed,
    required this.pace,
  });

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final rankColor = isTop3
        ? [
            const Color(0xFFFFD700),
            const Color(0xFFC0C0C0),
            const Color(0xFFCD7F32)
          ][rank - 1]
        : const Color(0xFF444460);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isTop3
            ? rankColor.withOpacity(0.06)
            : const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3
              ? rankColor.withOpacity(0.3)
              : const Color(0xFF1E1E2E),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: rankColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              'Runner #$runnerId',
              style: TextStyle(
                color: isTop3 ? Colors.white : const Color(0xFFCCCCDD),
                fontSize: 13,
                fontWeight:
                    isTop3 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              speed,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isTop3 ? rankColor : const Color(0xFF888899),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              pace,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF666680),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}