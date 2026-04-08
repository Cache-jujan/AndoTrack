// ============================================================
// PUBLIC LEADERBOARD — Day 24
// Polls leaderboard endpoint every 5 seconds. Shows ranked
// table with pace + speed. Suitable for projector display.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PublicLeaderboardScreen extends StatefulWidget {
  final int raceId;
  const PublicLeaderboardScreen({super.key, required this.raceId});

  @override
  State<PublicLeaderboardScreen> createState() =>
      _PublicLeaderboardScreenState();
}

class _PublicLeaderboardScreenState extends State<PublicLeaderboardScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  DateTime? _lastUpdated;

  static const _pollInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _fetch();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      // getLeaderboard already returns List<Map<String, dynamic>>
      final entries = await ApiService.getLeaderboard(widget.raceId);
      if (mounted) {
        setState(() {
          _entries = entries;
          _lastUpdated = DateTime.now();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection error. Retrying...';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _formatSpeed(dynamic rawSpeed) {
    final mps = (rawSpeed as num?)?.toDouble() ?? 0.0;
    final kmh = mps * 3.6;
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  String _formatPace(dynamic rawSpeed) {
    final mps = (rawSpeed as num?)?.toDouble() ?? 0.0;
    if (mps <= 0) return '--:--/km';
    final secondsPerKm = 1000 / mps;
    final mins = (secondsPerKm ~/ 60).toString().padLeft(2, '0');
    final secs = (secondsPerKm % 60).toInt().toString().padLeft(2, '0');
    return '$mins:$secs/km';
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D0D20), Color(0xFF0A0A0F)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E1E30), width: 1),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.flag, color: Color(0xFF00FF9C), size: 28),
                  SizedBox(width: 10),
                  Text(
                    'ANDOTRACK',
                    style: TextStyle(
                      color: Color(0xFF00FF9C),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'LIVE LEADERBOARD — Race #${widget.raceId}',
                style: const TextStyle(
                  color: Color(0xFF888899),
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const Spacer(),
          _LivePulse(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00FF9C),
          strokeWidth: 2,
        ),
      );
    }

    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Color(0xFF444460), size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFF666680), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty,
                color: Color(0xFF444460), size: 48),
            SizedBox(height: 12),
            Text(
              'Waiting for runners to start...',
              style: TextStyle(color: Color(0xFF666680), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Column headers
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(width: 48),
              Expanded(
                flex: 3,
                child: Text(
                  'RUNNER',
                  style: TextStyle(
                    color: Color(0xFF444460),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'SPEED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF444460),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'PACE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF444460),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ..._entries.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final runner = entry.value;
          return _LeaderboardRow(
            rank: rank,
            runnerId: runner['runner_id']?.toString() ?? '?',
            speed: _formatSpeed(runner['speed']),
            pace: _formatPace(runner['speed']),
          );
        }),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: const Color(0xFF0D0D14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_entries.length} runners active',
            style: const TextStyle(color: Color(0xFF444460), fontSize: 11),
          ),
          if (_error != null)
            const Row(
              children: [
                Icon(Icons.warning_amber,
                    color: Color(0xFFFFB800), size: 12),
                SizedBox(width: 4),
                Text(
                  'Reconnecting...',
                  style:
                      TextStyle(color: Color(0xFFFFB800), fontSize: 11),
                ),
              ],
            ),
          Text(
            'Updated: ${_formatTime(_lastUpdated)}',
            style: const TextStyle(color: Color(0xFF444460), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── LIVE PULSE ───────────────────────────────────────────────────────────
class _LivePulse extends StatefulWidget {
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(
                const Color(0xFF00FF9C),
                const Color(0xFF00FF9C).withOpacity(0.3),
                _ctrl.value,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FF9C)
                      .withOpacity(0.5 * (1 - _ctrl.value)),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Color(0xFF00FF9C),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LEADERBOARD ROW ──────────────────────────────────────────────────────
class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final String runnerId;
  final String speed;
  final String pace;

  const _LeaderboardRow({
    required this.rank,
    required this.runnerId,
    required this.speed,
    required this.pace,
  });

  Color get _rankColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return const Color(0xFF444460);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color:
            isTop3 ? _rankColor.withOpacity(0.06) : const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3
              ? _rankColor.withOpacity(0.3)
              : const Color(0xFF1E1E2E),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '#$rank',
                style: TextStyle(
                  color: _rankColor,
                  fontSize: rank <= 3 ? 20 : 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Text(
                'Runner #$runnerId',
                style: TextStyle(
                  color: isTop3 ? Colors.white : const Color(0xFFCCCCDD),
                  fontSize: 14,
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
                  color: isTop3 ? _rankColor : const Color(0xFF888899),
                  fontSize: 13,
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
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}