// lib/roles/race_director/screens/race_director_stats_screen.dart
//
// WEB-ONLY Per-Race Statistics dashboard for the Race Director.
//
// Level 1: Race Picker  — horizontal scroll of finished race cards
// Level 2: Race Stats   — participation funnel, segment distribution,
//                         avg pace cards, anomaly breakdown
//
// All bar charts are pure Flutter (no chart packages in pubspec.yaml).

import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────

const _kBg        = Color(0xFF0A0A0F);
const _kCard      = Color(0xFF1A1A2E);
const _kChartBg   = Color(0xFF12121E);
const _kBorder    = Color(0xFF1E1E32);
const _kGreen     = Color(0xFF00FF9C);
const _kBlue      = Color(0xFF00B4FF);
const _kTeal      = Color(0xFF00D4AA);
const _kAmber     = Color(0xFFFFB800);
const _kOrange    = Color(0xFFFF7A00);
const _kRed       = Color(0xFFFF4D4D);
const _kGold      = Color(0xFFFFD700);
const _kGrey      = Color(0xFF6B7280);
const _kTextPri   = Colors.white;
const _kTextSub   = Color(0xFF8888AA);
const _kTextMuted = Color(0xFF3A3A55);

// ── Top-level utility ──────────────────────────────────────────────────────────

String _fmtDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final dt = DateTime.parse(raw).toLocal();
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  } catch (_) {
    return raw;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class RaceDirectorStatsScreen extends StatefulWidget {
  const RaceDirectorStatsScreen({super.key});

  @override
  State<RaceDirectorStatsScreen> createState() =>
      _RaceDirectorStatsScreenState();
}

class _RaceDirectorStatsScreenState extends State<RaceDirectorStatsScreen> {
  // finished races only
  List<Map<String, dynamic>>     _races     = [];
  // raceId → analytics payload (empty map = fetch failed)
  Map<int, Map<String, dynamic>> _analytics = {};
  bool    _loading = true;
  String? _error;
  int?    _selectedRaceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final allRaces = await ApiService.getRaces();
      final finished = allRaces
          .where((r) => r['status'] == 'finished')
          .toList();

      // Parallel analytics fetch — graceful per-race failure
      final entries = await Future.wait(
        finished.map((r) async {
          final id = r['id'] as int;
          try {
            final data = await ApiService.getAnalytics(id);
            return MapEntry(id, data);
          } catch (_) {
            return MapEntry(id, <String, dynamic>{});
          }
        }),
      );

      if (!mounted) return;
      setState(() {
        _races          = finished;
        _analytics      = Map.fromEntries(entries);
        _selectedRaceId = finished.isNotEmpty
            ? (finished.first['id'] as int)
            : null;
        _loading        = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(
          child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: _kTextMuted, size: 44),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: _kTextSub, fontSize: 13)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _load,
                child: const Text('Retry',
                    style: TextStyle(color: _kBlue)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        color:           _kGreen,
        backgroundColor: _kCard,
        onRefresh:       _load,
        child: CustomScrollView(
          slivers: [
            // ── Page header ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Statistics',
                          style: TextStyle(
                            color:         _kTextPri,
                            fontSize:      24,
                            fontWeight:    FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_races.length} finished race${_races.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: _kTextSub, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: _kTextSub, size: 18),
                      onPressed: _load,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
            ),

            // ── Level 1: Race Picker ─────────────────────────────────────
            SliverToBoxAdapter(
              child: _races.isEmpty
                  ? const _EmptyRaces()
                  : _RacePicker(
                      races:      _races,
                      analytics:  _analytics,
                      selectedId: _selectedRaceId,
                      onSelect:   (id) =>
                          setState(() => _selectedRaceId = id),
                    ),
            ),

            // ── Level 2: Selected Race Stats ─────────────────────────────
            if (_selectedRaceId != null && _races.isNotEmpty)
              SliverToBoxAdapter(
                child: _RaceStats(
                  race: _races.firstWhere(
                      (r) => r['id'] == _selectedRaceId),
                  analytics:
                      _analytics[_selectedRaceId] ?? {},
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 56)),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyRaces extends StatelessWidget {
  const _EmptyRaces();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color:        _kCard,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: _kBorder),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 40, color: _kTextMuted),
            SizedBox(height: 14),
            Text(
              'No finished races yet',
              style: TextStyle(
                color:      _kTextSub,
                fontSize:   15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Stats are available after a race ends.',
              style: TextStyle(color: _kTextMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Race Picker (Level 1) ─────────────────────────────────────────────────────

class _RacePicker extends StatelessWidget {
  final List<Map<String, dynamic>>     races;
  final Map<int, Map<String, dynamic>> analytics;
  final int?                           selectedId;
  final ValueChanged<int>              onSelect;

  const _RacePicker({
    required this.races,
    required this.analytics,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize:        MainAxisSize.min,
      crossAxisAlignment:  CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 0, 0, 10),
          child: Text(
            'SELECT A RACE',
            style: TextStyle(
              color:         _kTextMuted,
              fontSize:      10,
              fontWeight:    FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding:         const EdgeInsets.fromLTRB(28, 0, 28, 0),
            itemCount:       races.length,
            itemBuilder:     (_, i) {
              final race       = races[i];
              final id         = race['id'] as int;
              final isSelected = id == selectedId;
              final name       = race['name']?.toString() ?? 'Race';
              final date       = _fmtDate(
                  race['scheduled_start']?.toString());
              final distKm     = race['distance_km'];
              final dist       = distKm != null
                  ? '${(distKm as num).toStringAsFixed(0)} km'
                  : '';
              final data       = analytics[id] ?? {};
              final funnel     = data['participation_funnel']
                  as Map<String, dynamic>? ?? {};
              final finishers  = (funnel['finishers'] as int?) ?? 0;

              return GestureDetector(
                onTap: () => onSelect(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin:   const EdgeInsets.only(right: 12),
                  width:    186,
                  padding:  const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _kGreen.withOpacity(0.08)
                        : _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? _kGreen.withOpacity(0.5)
                          : _kBorder,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color:      isSelected ? _kGreen : _kTextPri,
                          fontSize:   12,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      if (date.isNotEmpty || dist.isNotEmpty)
                        Text(
                          [date, dist]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(
                              color: _kTextMuted, fontSize: 9.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width:  5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: data.isEmpty
                                  ? _kTextMuted
                                  : _kGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            data.isEmpty
                                ? 'No data'
                                : '$finishers finisher${finishers == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: data.isEmpty
                                  ? _kTextMuted
                                  : _kGreen,
                              fontSize:   10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

// ── Selected Race Stats (Level 2) ─────────────────────────────────────────────

class _RaceStats extends StatelessWidget {
  final Map<String, dynamic> race;
  final Map<String, dynamic> analytics;

  const _RaceStats({required this.race, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final name = race['name']?.toString() ?? 'Race';

    // No analytics recorded for this race
    if (analytics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color:        _kCard,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: _kAmber.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: _kAmber, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No results recorded for this race.',
                      style: TextStyle(
                        color:      _kAmber,
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Run POST /finish to generate stats for "$name".',
                      style: const TextStyle(
                          color: _kTextSub, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Unpack analytics ──────────────────────────────────────────────────
    final funnel   = analytics['participation_funnel']
        as Map<String, dynamic>? ?? {};
    final segments = analytics['segments']
        as Map<String, dynamic>? ?? {};
    final anomaly  = analytics['anomaly_summary']
        as Map<String, dynamic>? ?? {};

    final registered = (funnel['registered']  as int?) ?? 0;
    final checkedIn  = (funnel['checked_in']  as int?) ?? 0;
    final finishers  = (funnel['finishers']   as int?) ?? 0;
    final dnf        = (funnel['dnf']         as int?) ?? 0;
    final dns        = (funnel['dns']         as int?) ?? 0;

    final compSeg   = segments['competitive']  as Map<String, dynamic>? ?? {};
    final recSeg    = segments['recreational'] as Map<String, dynamic>? ?? {};
    final casSeg    = segments['casual']       as Map<String, dynamic>? ?? {};
    final compCount = (compSeg['count'] as int?) ?? 0;
    final recCount  = (recSeg['count']  as int?) ?? 0;
    final casCount  = (casSeg['count']  as int?) ?? 0;
    final segTotal  = compCount + recCount + casCount;

    final anomTotal = (anomaly['total_detected'] as int?) ?? 0;
    final byType    = anomaly['by_type'] as Map<String, dynamic>? ?? {};

    // ── Computed rates ────────────────────────────────────────────────────
    final started = (registered - dns).clamp(0, registered);
    final completionRate = registered > 0
        ? '${(finishers / registered * 100).toStringAsFixed(1)}%' : '—';
    final noShowRate = registered > 0
        ? '${(dns / registered * 100).toStringAsFixed(1)}%' : '—';
    final dnfRate = started > 0
        ? '${(dnf / started * 100).toStringAsFixed(1)}%' : '—';

    return Column(
      mainAxisSize:       MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),

        // ── Race title bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
          child: Row(
            children: [
              Container(
                width: 3, height: 20,
                decoration: BoxDecoration(
                  color:        _kGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color:      _kTextPri,
                    fontSize:   16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // ── Summary stat chips ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
          child: Row(
            children: [
              _StatChip(
                  label: 'Completion',
                  value: completionRate,
                  color: _kGreen),
              const SizedBox(width: 10),
              _StatChip(
                  label: 'No-Show',
                  value: noShowRate,
                  color: _kRed),
              const SizedBox(width: 10),
              _StatChip(
                  label: 'DNF Rate',
                  value: dnfRate,
                  color: _kOrange),
              const SizedBox(width: 10),
              _StatChip(
                  label: 'Anomalies',
                  value: '$anomTotal',
                  color: anomTotal > 0 ? _kAmber : _kTextMuted),
            ],
          ),
        ),

        // ── Chart 1: Participation Funnel ────────────────────────────────
        _ChartSection(
          title: 'Participation Funnel',
          icon:  Icons.bar_chart_rounded,
          child: _VerticalBarChart(
            maxBarHeight: 140,
            bars: [
              _BarData(label: 'Registered', count: registered, color: _kBlue),
              _BarData(label: 'Checked In', count: checkedIn,  color: _kTeal),
              _BarData(label: 'Finishers',  count: finishers,  color: _kGreen),
              _BarData(label: 'DNF',        count: dnf,        color: _kOrange),
              _BarData(label: 'DNS',        count: dns,        color: _kRed),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Chart 2: Segment Distribution ───────────────────────────────
        _ChartSection(
          title: 'Runner Segments',
          icon:  Icons.people_alt_outlined,
          child: _HorizontalBarChart(
            total: segTotal,
            bars: [
              _BarData(label: 'Competitive',  count: compCount, color: _kGold),
              _BarData(label: 'Recreational', count: recCount,  color: _kTeal),
              _BarData(label: 'Casual',       count: casCount,  color: _kGrey),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Chart 3: Avg Pace ────────────────────────────────────────────
        _ChartSection(
          title: 'Average Pace by Segment',
          icon:  Icons.speed_rounded,
          child: _PaceCards(
            compPace: compSeg['avg_pace_formatted']?.toString(),
            recPace:  recSeg['avg_pace_formatted']?.toString(),
            casPace:  casSeg['avg_pace_formatted']?.toString(),
          ),
        ),

        const SizedBox(height: 14),

        // ── Chart 4: Anomaly Breakdown ───────────────────────────────────
        _ChartSection(
          title: 'Anomaly Breakdown',
          icon:  Icons.warning_amber_rounded,
          child: anomTotal == 0
              ? const _NoAnomalies()
              : _AnomalyBars(byType: byType),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color:         color,
                fontSize:      18,
                fontWeight:    FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: _kTextMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ── Chart section wrapper ─────────────────────────────────────────────────────

class _ChartSection extends StatelessWidget {
  final String   title;
  final IconData icon;
  final Widget   child;

  const _ChartSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        _kChartBg,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section title with green accent left border
            Row(
              children: [
                Container(
                  width:  3,
                  height: 14,
                  decoration: BoxDecoration(
                    color:        _kGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 13, color: _kTextSub),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color:      _kTextPri,
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

// ── Bar data model ────────────────────────────────────────────────────────────

class _BarData {
  final String label;
  final int    count;
  final Color  color;

  const _BarData({
    required this.label,
    required this.count,
    required this.color,
  });
}

// ── Vertical bar chart — Participation Funnel ─────────────────────────────────
//
// Each bar: count label (top) → colored bar → x-axis label (bottom).
// maxBarHeight is the pixel height of the tallest bar (the one with max count).

class _VerticalBarChart extends StatelessWidget {
  final List<_BarData> bars;
  final double         maxBarHeight;

  const _VerticalBarChart({
    required this.bars,
    required this.maxBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    // fold seeds at 1 so division is never by zero
    final maxCount = bars.fold<int>(
        1, (m, b) => b.count > m ? b.count : m);

    return SizedBox(
      height: maxBarHeight + 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((b) {
          final fraction = b.count / maxCount;
          final barH =
              (maxBarHeight * fraction).clamp(2.0, maxBarHeight);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Count label above bar
                  Text(
                    '${b.count}',
                    style: TextStyle(
                      color:      b.color,
                      fontSize:   11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Bar body
                  Container(
                    height: barH,
                    decoration: BoxDecoration(
                      color: b.color.withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // X-axis label
                  Text(
                    b.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _kTextSub, fontSize: 9.5),
                    maxLines:  2,
                    overflow:  TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Horizontal bar chart — Segments / Anomalies ───────────────────────────────
//
// Each row: label (fixed 110px) | track+fill bar | count(pct%) label.
// total > 0 → appends percentage of total to the label.

class _HorizontalBarChart extends StatelessWidget {
  final List<_BarData> bars;
  final int            total;

  const _HorizontalBarChart({
    required this.bars,
    this.total = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return const Text('No data.',
          style: TextStyle(color: _kTextMuted, fontSize: 12));
    }

    final maxCount = bars.fold<int>(
        1, (m, b) => b.count > m ? b.count : m);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: bars.map((bar) {
        final fraction   = (bar.count / maxCount).clamp(0.0, 1.0);
        final pctStr     = total > 0
            ? ' (${(bar.count / total * 100).toStringAsFixed(1)}%)'
            : '';
        final countLabel = '${bar.count}$pctStr';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              // Label column — fixed width so bars align
              SizedBox(
                width: 110,
                child: Text(
                  bar.label,
                  style:    const TextStyle(
                      color: _kTextSub, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Bar track + fill
              Expanded(
                child: Stack(
                  children: [
                    // Track
                    Container(
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        height: 26,
                        decoration: BoxDecoration(
                          color: bar.color.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    // Count + pct label (right-aligned inside track)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            countLabel,
                            style: const TextStyle(
                              color:      Colors.white,
                              fontSize:   10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Avg Pace cards ────────────────────────────────────────────────────────────

class _PaceCards extends StatelessWidget {
  final String? compPace;
  final String? recPace;
  final String? casPace;

  const _PaceCards({
    required this.compPace,
    required this.recPace,
    required this.casPace,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PaceCard(label: 'Competitive',  pace: compPace, color: _kGold),
        const SizedBox(width: 10),
        _PaceCard(label: 'Recreational', pace: recPace,  color: _kTeal),
        const SizedBox(width: 10),
        _PaceCard(label: 'Casual',       pace: casPace,  color: _kGrey),
      ],
    );
  }
}

class _PaceCard extends StatelessWidget {
  final String  label;
  final String? pace;
  final Color   color;

  const _PaceCard({
    required this.label,
    required this.pace,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final noData  = pace == null || pace!.isEmpty || pace == '—';
    final display = noData ? 'No data' : pace!;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width:  6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color:         color,
                      fontSize:      9,
                      fontWeight:    FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              display,
              style: TextStyle(
                color:      noData ? _kTextMuted : _kTextPri,
                fontSize:   noData ? 12 : 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!noData)
              const Text(
                'avg pace',
                style: TextStyle(color: _kTextMuted, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}

// ── No anomalies indicator ────────────────────────────────────────────────────

class _NoAnomalies extends StatelessWidget {
  const _NoAnomalies();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shield_outlined, color: _kGreen, size: 18),
        SizedBox(width: 10),
        Text(
          'No anomalies detected ✓',
          style: TextStyle(
            color:      _kGreen,
            fontSize:   13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Anomaly bars (by type) ────────────────────────────────────────────────────

class _AnomalyBars extends StatelessWidget {
  final Map<String, dynamic> byType;

  const _AnomalyBars({required this.byType});

  static String _fmtType(String raw) {
    return raw.split('_').map((w) {
      if (w.toLowerCase() == 'gps') return 'GPS';
      return w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (byType.isEmpty) {
      return const Text(
        'No type breakdown available.',
        style: TextStyle(color: _kTextMuted, fontSize: 12),
      );
    }

    final bars = byType.entries
        .map((e) => _BarData(
              label: _fmtType(e.key),
              count: (e.value as num?)?.toInt() ?? 0,
              color: _kAmber,
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return _HorizontalBarChart(bars: bars);
  }
}
