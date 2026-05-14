import 'dart:async';
import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF0A0A0F);
const _kSurface   = Color(0xFF0D0D18);
const _kBorder    = Color(0xFF1E1E32);
const _kGreen     = Color(0xFF00FF9C);
const _kBlue      = Color(0xFF00B4FF);
const _kAmber     = Color(0xFFFFB800);
const _kPurple    = Color(0xFF8B5CF6);
const _kGold      = Color(0xFFFFD700);
const _kSilver    = Color(0xFFC0C0C0);
const _kBronze    = Color(0xFFCD7F32);
const _kTextPri   = Colors.white;
const _kTextSub   = Color(0xFF8888AA);
const _kTextMuted = Color(0xFF3A3A55);

const _hdr = TextStyle(
  color:         _kTextMuted,
  fontSize:      9,
  fontWeight:    FontWeight.w700,
  letterSpacing: 0.5,
);

// ─────────────────────────────────────────────────────────────────────────────

class PublicRaceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const PublicRaceDetailScreen({super.key, required this.race});

  @override
  State<PublicRaceDetailScreen> createState() =>
      _PublicRaceDetailScreenState();
}

class _PublicRaceDetailScreenState extends State<PublicRaceDetailScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _racingRunners   = [];
  List<Map<String, dynamic>> _finishedRunners = [];
  int     _registeredCount = 0;
  bool    _loading         = true;
  String? _error;
  Timer?  _pollTimer;
  Timer?  _clockTimer;
  DateTime? _lastUpdated;

  int get _raceId => (widget.race['id'] as num).toInt();

  double get _distKm =>
      (widget.race['distance_km'] as num?)?.toDouble() ?? 0;

  // Active runners panel shows the racing list (already has dist + pace)
  List<Map<String, dynamic>> get _activeRunners => _racingRunners;

  // Leaderboard panel shows finished runners; falls back to racing by distance
  List<Map<String, dynamic>> get _leaderboardRows =>
      _finishedRunners.isNotEmpty
          ? _finishedRunners
          : List.of(_racingRunners)
            ..sort((a, b) =>
                ((b['distance_km'] as num?) ?? 0)
                    .compareTo((a['distance_km'] as num?) ?? 0));

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadAll());
    // Tick every second so the "X s ago" badge stays current
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _lastUpdated != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        ApiService.getPublicLeaderboard(_raceId),
        ApiService.getPublicRaceRunnerCount(_raceId),
      ]);
      final lb    = results[0] as Map<String, List<Map<String, dynamic>>>;
      final count = results[1] as int;
      if (!mounted) return;
      setState(() {
        _racingRunners   = lb['racing']   ?? [];
        _finishedRunners = lb['finished'] ?? [];
        _registeredCount = count;
        _loading         = false;
        _error           = null;
        _lastUpdated     = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      if (_loading) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _updatedLabel() {
    if (_lastUpdated == null) return 'Updating…';
    final secs = DateTime.now().difference(_lastUpdated!).inSeconds;
    if (secs < 5)  return 'Updated just now';
    if (secs < 60) return 'Updated ${secs}s ago';
    return 'Updated ${(secs / 60).floor()}m ago';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _buildTopBar(),
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
              ),
            )
          else if (_error != null)
            Expanded(child: _buildError())
          else ...[
            _buildStatsRow(),
            Expanded(child: _buildBody()),
          ],
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final status = widget.race['status']?.toString() ?? '';
    final name   = widget.race['name']?.toString() ?? 'Race';

    String statusLabel;
    Color  statusColor;
    switch (status) {
      case 'active':
        statusLabel = 'LIVE';     statusColor = _kGreen;     break;
      case 'finished':
        statusLabel = 'FINISHED'; statusColor = _kTextMuted; break;
      default:
        statusLabel = 'UPCOMING'; statusColor = _kPurple;
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: _kTextSub),
            label: const Text('All Races',
                style: TextStyle(color: _kTextSub, fontSize: 13)),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color:      _kTextPri,
                fontSize:   15,
                fontWeight: FontWeight.w700,
                overflow:   TextOverflow.ellipsis,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        statusColor.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withValues(alpha:0.35)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color:         statusColor,
                fontSize:      9,
                fontWeight:    FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _StatCard(
              label: 'REGISTERED',
              value: '$_registeredCount',
              color: _kBlue),
          const SizedBox(width: 10),
          _StatCard(
              label: 'RACING',
              value: '${_racingRunners.length}',
              color: _kAmber),
          const SizedBox(width: 10),
          _StatCard(
              label: 'FINISHED',
              value: '${_finishedRunners.length}',
              color: _kGreen),
          const SizedBox(width: 10),
          _StatCard(
            label: 'DISTANCE',
            value: _distKm > 0 ? '${_distKm.toStringAsFixed(0)} km' : '—',
            color: _kPurple,
          ),
        ],
      ),
    );
  }

  // ── Body (two-column) ──────────────────────────────────────────────────────

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: _buildRunnerPanel()),
          const SizedBox(width: 16),
          Expanded(flex: 5, child: _buildLeaderboardPanel()),
        ],
      ),
    );
  }

  // ── Left: Active runners ───────────────────────────────────────────────────

  Widget _buildRunnerPanel() {
    return Container(
      decoration: BoxDecoration(
        color:        _kSurface,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.people_outline_rounded,
                    size: 14, color: _kTextSub),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Active Runners',
                    style: TextStyle(
                      color:      _kTextPri,
                      fontSize:   13,
                      fontWeight: FontWeight.w700,
                      overflow:   TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:        _kAmber.withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kAmber.withValues(alpha:0.35)),
                  ),
                  child: Text(
                    '${_activeRunners.length}',
                    style: const TextStyle(
                      color:      _kAmber,
                      fontSize:   10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: _kBorder, height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _kBorder.withValues(alpha:0.3),
            child: const Row(
              children: [
                SizedBox(width: 32,
                    child: Text('RNK', style: _hdr)),
                Expanded(child: Text('NAME', style: _hdr)),
                SizedBox(width: 70,
                    child: Text('DIST', style: _hdr,
                        textAlign: TextAlign.right)),
                SizedBox(width: 72,
                    child: Text('PACE', style: _hdr,
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
          Expanded(
            child: _activeRunners.isEmpty
                ? const Center(
                    child: Text('No active runners',
                        style: TextStyle(color: _kTextMuted, fontSize: 12)))
                : ListView.builder(
                    itemCount: _activeRunners.length,
                    itemBuilder: (_, i) {
                      final r    = _activeRunners[i];
                      final rank = (r['rank'] as int?) ?? (i + 1);
                      final name = r['name']?.toString() ?? 'Unknown';
                      final dist = (r['distance_km'] as num?);
                      final pace = r['pace_formatted']?.toString();
                      return Container(
                        color: i.isEven
                            ? Colors.white.withValues(alpha:0.01)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '$rank',
                                style: const TextStyle(
                                  color:      _kBlue,
                                  fontSize:   11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      color: _kTextPri, fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                dist != null
                                    ? '${dist.toStringAsFixed(2)} km'
                                    : '—',
                                style: const TextStyle(
                                    color: _kGreen, fontSize: 11),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: Text(
                                pace ?? '—',
                                style: const TextStyle(
                                    color: _kGreen, fontSize: 11),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Right: Live leaderboard ────────────────────────────────────────────────

  Widget _buildLeaderboardPanel() {
    final rows     = _leaderboardRows;
    final isLive   = _finishedRunners.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color:        _kSurface,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    size: 16, color: _kAmber),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isLive ? 'Live Rankings' : 'Leaderboard',
                    style: const TextStyle(
                      color:      _kTextPri,
                      fontSize:   13,
                      fontWeight: FontWeight.w700,
                      overflow:   TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:        _kGreen.withValues(alpha:0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kGreen.withValues(alpha:0.30)),
                  ),
                  child: Text(
                    '${rows.length}',
                    style: const TextStyle(
                      color:      _kGreen,
                      fontSize:   10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        _kGreen.withValues(alpha:0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 5, color: _kGreen),
                      const SizedBox(width: 4),
                      Text(
                        _updatedLabel(),
                        style: const TextStyle(
                          color:      _kGreen,
                          fontSize:   9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: _kBorder, height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _kBorder.withValues(alpha:0.3),
            child: const Row(
              children: [
                SizedBox(width: 44,
                    child: Text('RANK', style: _hdr)),
                Expanded(child: Text('RUNNER', style: _hdr)),
                SizedBox(width: 70,
                    child: Text('DIST', style: _hdr,
                        textAlign: TextAlign.right)),
                SizedBox(width: 72,
                    child: Text('PACE', style: _hdr,
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_empty_rounded,
                            color: _kTextMuted, size: 28),
                        SizedBox(height: 8),
                        Text('No results yet',
                            style: TextStyle(
                                color: _kTextMuted, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final e    = rows[i];
                      final rank = (e['rank'] as int?) ?? (i + 1);
                      final name = e['name']?.toString()
                          ?? e['runner_name']?.toString()
                          ?? 'Unknown';
                      final bib  = e['bib_number']?.toString() ?? '—';
                      final dist = (e['distance_km'] as num?);
                      final pace = e['pace_formatted']?.toString() ?? '—';

                      Color rankColor;
                      switch (rank) {
                        case 1: rankColor = _kGold;   break;
                        case 2: rankColor = _kSilver; break;
                        case 3: rankColor = _kBronze; break;
                        default: rankColor = _kTextMuted;
                      }

                      return Container(
                        color: i.isEven
                            ? Colors.white.withValues(alpha:0.01)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: rank <= 3
                                  ? Container(
                                      width: 24, height: 24,
                                      decoration: BoxDecoration(
                                        color:  rankColor.withValues(alpha:0.15),
                                        shape:  BoxShape.circle,
                                        border: Border.all(
                                            color: rankColor.withValues(alpha:0.5)),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$rank',
                                        style: TextStyle(
                                          color:      rankColor,
                                          fontSize:   10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    )
                                  : Text('$rank',
                                      style: const TextStyle(
                                          color: _kTextMuted, fontSize: 12)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          color: _kTextPri, fontSize: 12),
                                      overflow: TextOverflow.ellipsis),
                                  Text('#$bib',
                                      style: const TextStyle(
                                          color: _kTextMuted, fontSize: 10)),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                dist != null
                                    ? '${dist.toStringAsFixed(2)} km'
                                    : '—',
                                style: const TextStyle(
                                    color: _kGreen, fontSize: 11),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: Text(pace,
                                  style: const TextStyle(
                                      color: _kGreen, fontSize: 11),
                                  textAlign: TextAlign.right),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: _kTextMuted, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loadAll,
            child: const Text('Retry',
                style: TextStyle(color: _kBlue)),
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
  final Color  color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:        color.withValues(alpha:0.06),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: color.withValues(alpha:0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color:         color,
                fontSize:      22,
                fontWeight:    FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color:         _kTextSub,
                fontSize:      10,
                fontWeight:    FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
