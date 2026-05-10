import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';
import 'package:andotrack_app/features/race/screens/race_detail_screen.dart';

class PersonalResultsScreen extends StatefulWidget {
  final int raceId;
  final String raceName;
  final Map<String, dynamic>? raceData;

  const PersonalResultsScreen({
    super.key,
    required this.raceId,
    required this.raceName,
    this.raceData,
  });

  @override
  State<PersonalResultsScreen> createState() => _PersonalResultsScreenState();
}

class _PersonalResultsScreenState extends State<PersonalResultsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _result;
  int? _runnerId;
  bool _loading = true;
  String? _error;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _runnerId = prefs.getInt('user_id');
    if (_runnerId == null) {
      setState(() { _error = 'Not logged in.'; _loading = false; });
      return;
    }
    try {
      final data = await ApiService.getRunnerResults(_runnerId!);
      final results = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final myResult = results.firstWhere(
        (r) => r['race_id'] == widget.raceId,
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _result = myResult.isNotEmpty ? myResult : null;
          _loading = false;
        });
        _fadeCtrl.forward();
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load results.'; _loading = false; });
    }
  }

  // finished_at is a real UTC-aware field — use .toLocal(), not parsePht().
  String _formatFinishTime(String? raw) {
    if (raw == null) return '--:--:--';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    } catch (_) {
      return raw;
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw);
      const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _share() {
    if (_result == null) return;
    final rank    = _result!['rank'];
    final pace    = _result!['pace_formatted'] ?? '--';
    final dist    = _result!['distance_km']?.toStringAsFixed(2) ?? '--';
    final segment = _result!['segment']?.toString();
    final segText = segment != null ? ' | Segment: ${segment[0].toUpperCase()}${segment.substring(1)}' : '';
    final text =
        '🏅 I finished ${widget.raceName}!\n'
        'Rank: #$rank | Pace: $pace | Distance: ${dist}km$segText\n'
        '#AndoTrack #Running';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Result copied to clipboard!'),
        backgroundColor: const Color(0xFF00FF9C).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF9C), strokeWidth: 2))
            : _error != null
                ? _buildError()
                : FadeTransition(
                    opacity: _fadeAnim,
                    child: _buildContent(),
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF4D4D), size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFF888899), fontSize: 14)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
              child: const Text('Retry', style: TextStyle(color: Color(0xFF00B4FF))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final result       = _result;
    final rank         = result?['rank'] as int?;
    final distKm       = (result?['distance_km'] as num?)?.toDouble();
    final paceFormatted = result?['pace_formatted'] as String?;
    final finishedAt   = result?['finished_at'] as String?;
    final segment      = result?['segment'] as String?;
    final splits       = (result?['splits'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return CustomScrollView(
      slivers: [
        // ── Header ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 24, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1A0D), Color(0xFF0A0A0F)],
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00FF9C).withOpacity(0.1),
                    border: Border.all(
                        color: const Color(0xFF00FF9C).withOpacity(0.4),
                        width: 2),
                  ),
                  child: const Icon(Icons.emoji_events_rounded,
                      color: Color(0xFF00FF9C), size: 36),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Race Complete!',
                  style: TextStyle(
                    color: Color(0xFF00FF9C),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.raceName,
                  style: const TextStyle(color: Color(0xFF888899), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                if (finishedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(finishedAt),
                    style: const TextStyle(color: Color(0xFF555570), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Finish time (hero stat) ────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  const Text(
                    'FINISH TIME',
                    style: TextStyle(
                      color: Color(0xFF666680),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatFinishTime(finishedAt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Segment badge ─────────────────────────────────────
        if (segment != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _SegmentBadge(segment: segment),
            ),
          ),

        // ── Stats row (rank, pace, distance) ──────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'RANK',
                    value: rank != null ? '#$rank' : '--',
                    accent: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: 'PACE',
                    value: paceFormatted ?? '--:--',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: 'DISTANCE',
                    value: distKm != null
                        ? '${distKm.toStringAsFixed(2)} km'
                        : '-- km',
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Checkpoint splits ─────────────────────────────────
        if (splits.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'CHECKPOINT SPLITS',
                style: TextStyle(
                  color: Color(0xFF666680),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Column(
                  children: List.generate(splits.length, (i) {
                    final split   = splits[i];
                    final name    = split['checkpoint_name'] ?? 'Checkpoint ${i + 1}';
                    final passedAt = split['passed_at'] as String?;
                    final isLast  = i == splits.length - 1;
                    return _SplitRow(
                      number: i + 1,
                      name:   name,
                      time:   _formatFinishTime(passedAt),
                      isLast: isLast,
                    );
                  }),
                ),
              ),
            ),
          ),
        ],

        // ── Buttons ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).padding.bottom + 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share Result',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF9C),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () {
                      if (widget.raceData != null) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RaceDetailScreen(race: widget.raceData!),
                          ),
                          (_) => false,
                        );
                      } else {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RunnerDashboardScreen()),
                          (_) => false,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF888899),
                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      widget.raceData != null ? 'View My Race' : 'Back to Home',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.raceData != null)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RunnerDashboardScreen()),
                          (_) => false,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF555570),
                        side: BorderSide(color: Colors.white.withOpacity(0.06)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Back to Home',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Segment badge ─────────────────────────────────────────────────────────────

class _SegmentBadge extends StatelessWidget {
  final String segment;
  const _SegmentBadge({required this.segment});

  static Color _color(String s) {
    switch (s) {
      case 'competitive':  return const Color(0xFFFFB800);
      case 'recreational': return const Color(0xFF009688);
      case 'casual':       return const Color(0xFF8888AA);
      default:             return const Color(0xFF3A3A55);
    }
  }

  static String _label(String s) {
    switch (s) {
      case 'competitive':  return '🏆 Competitive Runner — Top 20%';
      case 'recreational': return '🏃 Recreational Runner — Middle 50%';
      case 'casual':       return '🚶 Casual Runner — Bottom 30%';
      default:             return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(segment);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            'YOUR SEGMENT',
            style: TextStyle(
              color:         color.withOpacity(0.7),
              fontSize:      9,
              fontWeight:    FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _label(segment),
            style: TextStyle(
              color:      color,
              fontSize:   15,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool   accent;
  const _StatCard({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? const Color(0xFF00FF9C).withOpacity(0.3)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666680),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent ? const Color(0xFF00FF9C) : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Split row ─────────────────────────────────────────────────────────────────
class _SplitRow extends StatelessWidget {
  final int    number;
  final String name;
  final String time;
  final bool   isLast;
  const _SplitRow({
    required this.number,
    required this.name,
    required this.time,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final isFinish = isLast;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFF1E1E30), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isFinish
                  ? const Color(0xFF00FF9C).withOpacity(0.15)
                  : const Color(0xFF1E1E30),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isFinish
                  ? const Icon(Icons.flag_rounded,
                      size: 13, color: Color(0xFF00FF9C))
                  : Text(
                      '$number',
                      style: const TextStyle(
                          color: Color(0xFF666680),
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: isFinish ? const Color(0xFF00FF9C) : Colors.white,
                fontSize: 13,
                fontWeight: isFinish ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: Color(0xFF888899),
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
