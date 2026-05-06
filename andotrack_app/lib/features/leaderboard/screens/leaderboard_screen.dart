// MOVED TO: lib/features/leaderboard/screens/leaderboard_screen.dart

// ============================================================
// LeaderboardScreen — Organizer/embedded view
// ─────────────────────────────────────────────────────────────
// • Polls /leaderboard/{raceId} every 5 seconds (silent)
// • Displays rank, runner name (falls back to Runner #id),
//   speed (km/h), pace (/km), distance (if returned by API),
//   checkpoints hit (if returned by API)
// • Tap a row → bottom sheet with full runner detail
// • Live dot animation in header
// • Empty / error / loading states
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:andotrack_app/core/services/api_service.dart';

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
  Timer? _pollTimer;
  DateTime? _lastUpdated;

  static const _pollInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _isLoading = true; _error = null; });
    try {
      final data = await ApiService.getLeaderboard(widget.raceId);
      if (mounted) {
        setState(() {
          _leaderboard = data;
          _lastUpdated = DateTime.now();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--:--';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatTimestamp(dynamic ts) {
    try {
      if (ts is int) {
        final dt =
            DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
        return _formatTime(dt);
      }
      return '--';
    } catch (_) {
      return '--';
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  // ── Runner detail sheet ───────────────────────────────────────────────────

  void _showRunnerDetail(
      BuildContext context, int index, Map<String, dynamic> entry) {
    final rankColor = _rankColor(index);
    final runnerId = entry['runner_id']?.toString() ?? '?';
    final name =
        entry['name']?.toString() ?? 'Runner #$runnerId';
    final initials = _initials(name);
    final distKm = (entry['distance_km'] as num?)?.toDouble();
    final checkpointsHit = entry['checkpoints_hit'] as int?;

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
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            // Runner header
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rankColor.withOpacity(0.15),
                    border: Border.all(
                        color: rankColor.withOpacity(0.4), width: 2),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: TextStyle(
                            color: rankColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            index < 3
                                ? ['🥇 1st', '🥈 2nd', '🥉 3rd'][index]
                                : 'Rank #${index + 1}',
                            style: TextStyle(
                                color: rankColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          Text('  ·  ID: $runnerId',
                              style: const TextStyle(
                                  color: Color(0xFF444460),
                                  fontSize: 12)),
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

            // Stats row
            Row(
              children: [
                _DetailStat(
                    label: 'Speed',
                    value: '${_speedDisplay(entry['speed'])} km/h',
                    color: index < 3
                        ? rankColor
                        : const Color(0xFF00FF9C)),
                _DetailStatDivider(),
                _DetailStat(
                    label: 'Pace',
                    value: '${_paceDisplay(entry['speed'])} /km',
                    color: Colors.white),
                _DetailStatDivider(),
                _DetailStat(
                    label: 'Last seen',
                    value: entry['timestamp'] != null
                        ? _formatTimestamp(entry['timestamp'])
                        : '--',
                    color: Colors.white),
              ],
            ),

            // Distance + checkpoints (if API returns them)
            if (distKm != null || checkpointsHit != null) ...[
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF1E1E2E), height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (distKm != null)
                    Expanded(
                      child: _DetailStat(
                          label: 'Distance',
                          value: '${distKm.toStringAsFixed(2)} km',
                          color: const Color(0xFF00B4FF)),
                    ),
                  if (distKm != null && checkpointsHit != null)
                    _DetailStatDivider(),
                  if (checkpointsHit != null)
                    Expanded(
                      child: _DetailStat(
                          label: 'Checkpoints',
                          value: '$checkpointsHit',
                          color: const Color(0xFFFFB800)),
                    ),
                ],
              ),
            ],

            // GPS coords pill (if available)
            if (entry['lat'] != null && entry['lng'] != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E1E2E)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Color(0xFF444460), size: 14),
                    const SizedBox(width: 8),
                    Text(
                      '${(entry['lat'] as num).toStringAsFixed(5)}, '
                      '${(entry['lng'] as num).toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Color(0xFF666680),
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle:
            const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
        title: Row(
          children: [
            const Text('Leaderboard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 10),
            _LiveDot(),
          ],
        ),
        actions: [
          // Last updated
          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  _formatTime(_lastUpdated),
                  style: const TextStyle(
                      color: Color(0xFF444460), fontSize: 11),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFF00FF9C),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00FF9C), strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off,
                          color: Color(0xFF444460), size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFF666680), fontSize: 13),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _load(),
                        child: const Text('Retry',
                            style: TextStyle(color: Color(0xFF00FF9C))),
                      ),
                    ],
                  ),
                )
          : _leaderboard.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hourglass_empty,
                          color: Color(0xFF444460), size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Waiting for runners...',
                        style: TextStyle(
                            color: Color(0xFF666680), fontSize: 14),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Column headers
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 48),
                          const Expanded(
                            flex: 3,
                            child: Text('RUNNER',
                                style: TextStyle(
                                    color: Color(0xFF444460),
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const Expanded(
                            flex: 2,
                            child: Text('SPEED',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Color(0xFF444460),
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const Expanded(
                            flex: 2,
                            child: Text('PACE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Color(0xFF444460),
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 24),
                        ],
                      ),
                    ),

                    // Runner rows
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                            onTap: () => _showRunnerDetail(
                                context, index, entry),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isTop3
                                    ? rankColor.withOpacity(0.06)
                                    : const Color(0xFF0D0D14),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isTop3
                                      ? rankColor.withOpacity(0.25)
                                      : const Color(0xFF1E1E2E),
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    // Rank
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        isTop3
                                            ? ['🥇', '🥈', '🥉'][index]
                                            : '#${index + 1}',
                                        style: TextStyle(
                                          color: rankColor,
                                          fontSize: isTop3 ? 20 : 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Avatar
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            rankColor.withOpacity(0.1),
                                        border: Border.all(
                                            color: rankColor
                                                .withOpacity(0.3)),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _initials(name),
                                          style: TextStyle(
                                              color: rankColor,
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Name + sub-label
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.85),
                                              fontWeight:
                                                  FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          // Show distance if API provides it
                                          if (entry['distance_km'] !=
                                              null)
                                            Text(
                                              '${(entry['distance_km'] as num).toStringAsFixed(2)} km',
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(
                                                          0.25),
                                                  fontSize: 10),
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Speed
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _speedDisplay(
                                                    entry['speed']),
                                                style: TextStyle(
                                                  color: isTop3
                                                      ? rankColor
                                                      : const Color(
                                                          0xFF00FF9C),
                                                  fontSize: 16,
                                                  fontWeight:
                                                      FontWeight.bold,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets
                                                    .only(
                                                    bottom: 2, left: 2),
                                                child: Text('km/h',
                                                    style: TextStyle(
                                                        color: Colors
                                                            .white
                                                            .withOpacity(
                                                                0.3),
                                                        fontSize: 9)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Pace
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${_paceDisplay(entry['speed'])} /km',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withOpacity(0.25),
                                            fontSize: 11),
                                      ),
                                    ),

                                    // Chevron
                                    Icon(Icons.chevron_right,
                                        color: Colors.white
                                            .withOpacity(0.12),
                                        size: 18),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Footer
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: const Color(0xFF0D0D14),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_leaderboard.length} runner${_leaderboard.length == 1 ? '' : 's'} active',
                            style: const TextStyle(
                                color: Color(0xFF444460), fontSize: 11),
                          ),
                          Text(
                            'Updates every 5s',
                            style: const TextStyle(
                                color: Color(0xFF444460), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Live dot ──────────────────────────────────────────────────────────────────
class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
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
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(const Color(0xFF00FF9C),
              const Color(0xFF00FF9C).withOpacity(0.3), _ctrl.value),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00FF9C)
                  .withOpacity(0.5 * (1 - _ctrl.value)),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail stat ───────────────────────────────────────────────────────────────
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
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF444460), fontSize: 11),
              textAlign: TextAlign.center),
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
