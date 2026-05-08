// lib/roles/race_director/screens/post_race_screen.dart
//
// WEB-ONLY post-race summary for Race Director.
// Shown when a race status == 'finished'.
//
// Header:  4 stat cards — Registered / Checked In / Finishers / DNF+DNS
// 3 tabs:  Results | Analytics | Anomaly Report
// Export:  CSV via Clipboard (works on all platforms, no dart:html)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:andotrack_app/core/services/api_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF080810);
const _kSurface   = Color(0xFF0D0D18);
const _kBorder    = Color(0xFF1E1E32);
const _kGreen     = Color(0xFF00FF9C);
const _kBlue      = Color(0xFF00B4FF);
const _kAmber     = Color(0xFFFFB800);
const _kRed       = Color(0xFFFF4D4D);
const _kPurple    = Color(0xFF8B5CF6);
const _kTextPri   = Colors.white;
const _kTextSub   = Color(0xFF8888AA);
const _kTextMuted = Color(0xFF3A3A55);

// ─────────────────────────────────────────────────────────────────────────────

class PostRaceScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const PostRaceScreen({super.key, required this.race});

  @override
  State<PostRaceScreen> createState() => _PostRaceScreenState();
}

class _PostRaceScreenState extends State<PostRaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ── Data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _leaderboard = [];
  List<Map<String, dynamic>> _runners     = [];
  Map<String, dynamic>       _anomalyRpt  = {};
  bool    _loading = true;
  String? _error;

  int get _raceId => widget.race['id'] as int;
  double get _distKm => (widget.race['distance_km'] as num?)?.toDouble() ?? 0;

  // ── Computed stats ────────────────────────────────────────────────────────
  int get _registered  => _runners.length;
  int get _checkedIn   =>
      _runners.where((r) =>
          r['checked_in'] == true || r['is_checked_in'] == true).length;
  int get _finishers   =>
      _runners.where((r) => r['status']?.toString() == 'finished').length;
  int get _dnfDns      => _runners
      .where((r) {
        final s = r['status']?.toString() ?? '';
        return s == 'dnf' || s == 'dns';
      }).length;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Fetch runners first — required for header stats
      final runners = await ApiService.getRaceRunners(_raceId);
      // These can fail gracefully — leaderboard may be empty for finished races
      final leaderboard  = await ApiService.getLeaderboard(_raceId)
          .catchError((_) => <Map<String, dynamic>>[]);
      final anomalyRpt   = await ApiService.getAnomalyReport(_raceId)
          .catchError((_) => <String, dynamic>{
            'total': 0, 'vehicle_speed': 0, 'gps_jump': 0,
            'off_route': 0, 'erratic': 0,
            'resolved': 0, 'unresolved': 0,
            'flagged_runners': <dynamic>[],
          });
      if (!mounted) return;
      setState(() {
        _runners     = runners;
        _leaderboard = leaderboard;
        _anomalyRpt  = anomalyRpt;
        _loading     = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── CSV export ────────────────────────────────────────────────────────────

  void _exportResults() {
    final buf = StringBuffer();
    buf.writeln('Rank,Bib,Name,Finish Time,Pace (min/km)');
    for (var i = 0; i < _leaderboard.length; i++) {
      final row  = _leaderboard[i];
      final rank = i + 1;
      final bib  = row['bib_number']?.toString() ?? '';
      final name = (row['name']?.toString() ?? '').replaceAll(',', ' ');
      final secs = (row['finish_time_seconds'] as num?)?.toInt();
      final timeStr = secs != null ? _fmtSecs(secs) : '';
      final pace    = (secs != null && _distKm > 0)
          ? _fmtPace(secs / _distKm)
          : '';
      buf.writeln('$rank,$bib,$name,$timeStr,$pace');
    }
    _showCsvDialog('Results', buf.toString());
  }

  void _showCsvDialog(String title, String csv) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kBorder)),
        title: Text('Export: $title',
            style: const TextStyle(
                color: _kTextPri, fontWeight: FontWeight.bold, fontSize: 15)),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy the CSV below and paste into a spreadsheet:',
                style: TextStyle(color: _kTextSub, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                height:      220,
                padding:     const EdgeInsets.all(12),
                decoration:  BoxDecoration(
                  color:        _kBg,
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(color: _kBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csv,
                    style: const TextStyle(
                      color:      _kTextSub,
                      fontSize:   11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _kTextSub)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('CSV copied to clipboard'),
                backgroundColor: _kGreen,
                behavior: SnackBarBehavior.floating,
              ));
            },
            icon:  const Icon(Icons.copy_rounded, size: 14),
            label: const Text('Copy CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: _kGreen, strokeWidth: 2))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildTopBar(),
        _buildStatHeader(),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _ResultsTab(
                leaderboard:  _leaderboard,
                runners:      _runners,
                distKm:       _distKm,
                onExport:     _exportResults,
              ),
              _AnalyticsTab(
                runners:     _runners,
                leaderboard: _leaderboard,
                distKm:      _distKm,
              ),
              _AnomalyReportTab(report: _anomalyRpt),
            ],
          ),
        ),
      ],
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final name     = widget.race['name']?.toString() ?? 'Race';
    final location = widget.race['location']?.toString();
    final distKm   = widget.race['distance_km'];

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: _kTextSub, size: 20),
            onPressed: () => Navigator.pop(context),
            padding:     const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:        _kTextMuted.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _kTextMuted.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'FINISHED',
                        style: TextStyle(
                          color:         _kTextMuted,
                          fontSize:      9,
                          fontWeight:    FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (distKm != null)
                      Text(
                        '${(distKm as num).toStringAsFixed(0)} km',
                        style: const TextStyle(
                            color: _kTextSub, fontSize: 12),
                      ),
                    if (location != null) ...[
                      const SizedBox(width: 8),
                      const Text('·',
                          style: TextStyle(color: _kTextMuted)),
                      const SizedBox(width: 8),
                      Text(location,
                          style: const TextStyle(
                              color: _kTextSub, fontSize: 12)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: const TextStyle(
                    color:       _kTextPri,
                    fontSize:    20,
                    fontWeight:  FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: _kTextSub, size: 18),
            onPressed: _loadAll,
            tooltip:   'Refresh',
          ),
        ],
      ),
    );
  }

  // ── Stat header ───────────────────────────────────────────────────────────

  Widget _buildStatHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          _StatCard(
            label: 'Registered',
            value: '$_registered',
            icon:  Icons.how_to_reg_outlined,
            color: _kBlue,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Checked In',
            value: '$_checkedIn',
            icon:  Icons.qr_code_scanner_rounded,
            color: _kPurple,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Finishers',
            value: '$_finishers',
            icon:  Icons.flag_rounded,
            color: _kGreen,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'DNF / DNS',
            value: '$_dnfDns',
            icon:  Icons.cancel_outlined,
            color: _kRed,
          ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: TabBar(
        controller:       _tabCtrl,
        labelColor:       _kGreen,
        unselectedLabelColor: _kTextSub,
        labelStyle:       const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        indicatorColor:   _kGreen,
        indicatorWeight:  2,
        indicatorSize:    TabBarIndicatorSize.label,
        padding:          const EdgeInsets.symmetric(horizontal: 20),
        tabs: const [
          Tab(text: 'Results'),
          Tab(text: 'Analytics'),
          Tab(text: 'Anomaly Report'),
        ],
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: _kTextMuted, size: 48),
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
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color:      color,
                    fontSize:   22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                      color: _kTextSub, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Results tab ───────────────────────────────────────────────────────────────

class _ResultsTab extends StatelessWidget {
  final List<Map<String, dynamic>> leaderboard;
  final List<Map<String, dynamic>> runners;
  final double    distKm;
  final VoidCallback onExport;

  const _ResultsTab({
    required this.leaderboard,
    required this.runners,
    required this.distKm,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
          child: Row(
            children: [
              Text(
                '${leaderboard.length} finishers',
                style: const TextStyle(color: _kTextSub, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: leaderboard.isEmpty ? null : onExport,
                icon:  const Icon(Icons.download_rounded, size: 14),
                label: const Text('Export CSV'),
                style: TextButton.styleFrom(
                  foregroundColor: _kBlue,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // Column headers
        _tableHeader(),

        // Rows — Finishers → DNF → DNS
        Expanded(child: _buildAllResults()),
      ],
    );
  }

  Widget _buildAllResults() {
    final dnf = runners.where((r) {
      final s = r['race_status']?.toString()
             ?? r['status']?.toString() ?? '';
      return s == 'dnf';
    }).toList();
    final dns = runners.where((r) {
      final s = r['race_status']?.toString()
             ?? r['status']?.toString() ?? '';
      return s == 'dns';
    }).toList();

    if (leaderboard.isEmpty && dnf.isEmpty && dns.isEmpty) {
      return const Center(
        child: Text('No results recorded',
            style: TextStyle(color: _kTextMuted, fontSize: 13)));
    }

    final items = <Widget>[];

    // Finishers
    if (leaderboard.isEmpty) {
      items.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('No finishers recorded',
              style: TextStyle(color: _kTextMuted, fontSize: 13)),
        ),
      ));
    } else {
      for (var i = 0; i < leaderboard.length; i++) {
        items.add(_LeaderboardRow(
          rank:   i + 1,
          entry:  leaderboard[i],
          distKm: distKm,
          isEven: i.isEven,
        ));
      }
    }

    // DNF section
    if (dnf.isNotEmpty) {
      items.add(_SectionDivider(
          label: 'DID NOT FINISH', count: dnf.length, color: _kAmber));
      for (final r in dnf) {
        items.add(_DnfRow(runner: r));
      }
    }

    // DNS section
    if (dns.isNotEmpty) {
      items.add(_SectionDivider(
          label: 'DID NOT START', count: dns.length, color: _kTextMuted));
      for (final r in dns) {
        items.add(_DnsRow(runner: r));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: items,
    );
  }

  Widget _tableHeader() {
    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color:        _kBorder.withOpacity(0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 40,
              child: Text('Rank', style: _hdr)),
          SizedBox(width: 60,
              child: Text('Bib', style: _hdr)),
          Expanded(child: Text('Name', style: _hdr)),
          SizedBox(width: 100,
              child: Text('Time', style: _hdr, textAlign: TextAlign.right)),
          SizedBox(width: 100,
              child: Text('Pace', style: _hdr, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  static const _hdr = TextStyle(
    color: _kTextMuted, fontSize: 10, fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );
}

// ── Leaderboard row ───────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  final int                  rank;
  final Map<String, dynamic> entry;
  final double               distKm;
  final bool                 isEven;

  const _LeaderboardRow({
    required this.rank,
    required this.entry,
    required this.distKm,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context) {
    final bib    = entry['bib_number']?.toString() ?? '—';
    final name   = entry['name']?.toString()
        ?? entry['runner_name']?.toString() ?? 'Unknown';
    // Backend may return finish_time_seconds, finish_time, or elapsed_seconds
    final secRaw = entry['finish_time_seconds']
        ?? entry['finish_time']
        ?? entry['elapsed_seconds'];
    final secs = (secRaw as num?)?.toInt();
    final time = secs != null ? _fmtSecs(secs) : '—';
    final pace = (secs != null && distKm > 0)
        ? _fmtPace(secs / distKm)
        : '—';

    // Medal colors for top 3
    Color nameColor = _kTextPri;
    if (rank == 1) nameColor = _kAmber;
    else if (rank == 2) nameColor = const Color(0xFFC0C0C0);
    else if (rank == 3) nameColor = const Color(0xFFCD7F32);

    return Container(
      margin:  const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.white.withOpacity(0.02)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$rank',
              style: TextStyle(
                color:      rank <= 3 ? nameColor : _kTextMuted,
                fontSize:   12,
                fontWeight: rank <= 3 ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '#$bib',
              style: const TextStyle(color: _kTextSub, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color:      nameColor,
                fontSize:   13,
                fontWeight: rank <= 3 ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              time,
              style: const TextStyle(
                color:      _kTextPri,
                fontSize:   12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              pace,
              style: const TextStyle(color: _kTextSub, fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Analytics tab ─────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatelessWidget {
  final List<Map<String, dynamic>> runners;
  final List<Map<String, dynamic>> leaderboard;
  final double distKm;

  const _AnalyticsTab({
    required this.runners,
    required this.leaderboard,
    required this.distKm,
  });

  @override
  Widget build(BuildContext context) {
    final registered = runners.length;
    final finishers  = runners
        .where((r) => r['status']?.toString() == 'finished').length;
    final completionPct =
        registered > 0 ? (finishers / registered * 100).toStringAsFixed(1) : '0';

    // Average finish time
    final finishTimes = leaderboard
        .map((e) => (e['finish_time_seconds'] as num?)?.toInt())
        .where((s) => s != null)
        .cast<int>()
        .toList();
    final avgSecs = finishTimes.isEmpty
        ? null
        : finishTimes.reduce((a, b) => a + b) ~/ finishTimes.length;
    final fastestSecs = finishTimes.isEmpty ? null : finishTimes.first;
    final slowestSecs =
        finishTimes.isEmpty ? null : finishTimes.last;

    // Pace buckets (performance segments)
    final buckets = _buildBuckets(finishTimes, distKm);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row
          Row(
            children: [
              _AnalyticCard(
                label: 'Completion Rate',
                value: '$completionPct%',
                color: _kGreen,
              ),
              const SizedBox(width: 12),
              _AnalyticCard(
                label: 'Average Time',
                value: avgSecs != null ? _fmtSecs(avgSecs) : '—',
                color: _kBlue,
              ),
              const SizedBox(width: 12),
              _AnalyticCard(
                label: 'Fastest',
                value: fastestSecs != null ? _fmtSecs(fastestSecs) : '—',
                color: _kAmber,
              ),
              const SizedBox(width: 12),
              _AnalyticCard(
                label: 'Slowest',
                value: slowestSecs != null ? _fmtSecs(slowestSecs) : '—',
                color: _kTextSub,
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Pace distribution
          if (buckets.isNotEmpty) ...[
            const Text(
              'Finish Time Distribution',
              style: TextStyle(
                color:      _kTextPri,
                fontSize:   14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ...buckets.map((b) => _PaceBar(
                  label:   b.label,
                  count:   b.count,
                  total:   finishers,
                  color:   b.color,
                )),
          ],

          const SizedBox(height: 28),

          // Status breakdown
          const Text(
            'Runner Status Breakdown',
            style: TextStyle(
              color:      _kTextPri,
              fontSize:   14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _buildStatusBreakdown(),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown() {
    final groups = <String, int>{};
    for (final r in runners) {
      final s = r['status']?.toString() ?? 'unknown';
      groups[s] = (groups[s] ?? 0) + 1;
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: groups.entries.map((e) {
        Color color;
        switch (e.key) {
          case 'finished': color = _kGreen;      break;
          case 'racing':   color = _kAmber;      break;
          case 'dns':      color = _kTextMuted;  break;
          case 'dnf':      color = _kRed;        break;
          default:         color = _kTextSub;
        }
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                e.key.toUpperCase(),
                style: TextStyle(
                  color:         color,
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${e.value}',
                style: const TextStyle(
                  color:      _kTextPri,
                  fontSize:   14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static List<_Bucket> _buildBuckets(List<int> times, double distKm) {
    if (times.isEmpty || distKm <= 0) return [];
    // Build 4–6 roughly equal time buckets based on data spread
    final min = times.first;
    final max = times.last;
    if (min == max) {
      return [_Bucket('${_fmtSecs(min)}', times.length, _kGreen)];
    }
    final span    = max - min;
    final step    = (span / 5).ceil();
    final buckets = <_Bucket>[];
    final colors  = [_kGreen, _kBlue, _kAmber, _kPurple, _kRed];
    for (var i = 0; i < 5; i++) {
      final lo = min + step * i;
      final hi = lo + step;
      final count =
          times.where((t) => t >= lo && (i == 4 ? t <= hi : t < hi)).length;
      if (count == 0) continue;
      final label =
          '${_fmtSecs(lo)} – ${_fmtSecs(hi > max ? max : hi)}';
      buckets.add(_Bucket(label, count, colors[i % colors.length]));
    }
    return buckets;
  }
}

class _Bucket {
  final String label;
  final int    count;
  final Color  color;
  const _Bucket(this.label, this.count, this.color);
}

class _AnalyticCard extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _AnalyticCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: _kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color:      color,
                fontSize:   20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(color: _kTextSub, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _PaceBar extends StatelessWidget {
  final String label;
  final int    count;
  final int    total;
  final Color  color;

  const _PaceBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final frac = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: _kTextSub, fontSize: 11)),
              ),
              Text(
                '$count runner${count == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: _kTextMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:            frac.toDouble(),
              backgroundColor:  _kBorder,
              valueColor:       AlwaysStoppedAnimation<Color>(color),
              minHeight:        8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Anomaly Report tab ────────────────────────────────────────────────────────

class _AnomalyReportTab extends StatelessWidget {
  final Map<String, dynamic> report;
  const _AnomalyReportTab({required this.report});

  @override
  Widget build(BuildContext context) {
    final total      = report['total'] as int? ?? 0;
    final resolved   = report['resolved'] as int? ?? 0;
    final unresolved = report['unresolved'] as int? ?? 0;
    final vSpeed     = report['vehicle_speed'] as int? ?? 0;
    final gpsJump    = report['gps_jump'] as int? ?? 0;
    final offRoute   = report['off_route'] as int? ?? 0;
    final erratic    = report['erratic'] as int? ?? 0;
    final flagged    = (report['flagged_runners'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              _AnomalyStatCard(
                  label: 'Total Anomalies', value: '$total',
                  color: _kAmber),
              const SizedBox(width: 10),
              _AnomalyStatCard(
                  label: 'Resolved', value: '$resolved',
                  color: _kGreen),
              const SizedBox(width: 10),
              _AnomalyStatCard(
                  label: 'Unresolved', value: '$unresolved',
                  color: unresolved > 0 ? _kRed : _kTextMuted),
            ],
          ),

          const SizedBox(height: 28),

          // By type
          const Text(
            'By Type',
            style: TextStyle(
              color: _kTextPri, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _AnomalyTypeRow(
              label: 'Vehicle Speed', count: vSpeed, color: _kRed),
          _AnomalyTypeRow(
              label: 'GPS Jump', count: gpsJump, color: _kAmber),
          _AnomalyTypeRow(
              label: 'Off Route', count: offRoute, color: _kAmber),
          _AnomalyTypeRow(
              label: 'Erratic Movement', count: erratic, color: _kRed),

          if (flagged.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text(
              'Flagged Runners',
              style: TextStyle(
                color:      _kTextPri,
                fontSize:   14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...flagged.map((r) {
              final m    = r as Map<String, dynamic>;
              final bib  = m['bib_number']?.toString() ?? '—';
              final name = m['name']?.toString() ?? 'Unknown';
              final cnt  = m['anomaly_count'] as int? ?? 0;
              return Container(
                margin:  const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color:        _kRed.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kRed.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:        _kBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('#$bib',
                          style: const TextStyle(
                            color:      _kBlue,
                            fontSize:   11,
                            fontWeight: FontWeight.w800,
                          )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                            color:      _kTextPri,
                            fontSize:   13,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:        _kRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$cnt anomal${cnt == 1 ? 'y' : 'ies'}',
                        style: const TextStyle(
                          color:      _kRed,
                          fontSize:   10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          if (total == 0) ...[
            const SizedBox(height: 32),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.shield_outlined, color: _kGreen, size: 36),
                  SizedBox(height: 10),
                  Text(
                    'No anomalies detected during this race.',
                    style: TextStyle(color: _kTextSub, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnomalyStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;

  const _AnomalyStatCard({
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
          color:        color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                  color:      color,
                  fontSize:   22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: _kTextSub, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _AnomalyTypeRow extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;

  const _AnomalyTypeRow({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: _kTextSub, fontSize: 13)),
          ),
          Text(
            '$count',
            style: TextStyle(
              color:      count > 0 ? color : _kTextMuted,
              fontSize:   13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section divider ───────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;

  const _SectionDivider({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: _kBorder)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color:         color,
                    fontSize:      10,
                    fontWeight:    FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color:        color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color:      color,
                      fontSize:   10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: _kBorder)),
        ],
      ),
    );
  }
}

// ── DNF row ───────────────────────────────────────────────────────────────────

class _DnfRow extends StatelessWidget {
  final Map<String, dynamic> runner;
  const _DnfRow({required this.runner});

  @override
  Widget build(BuildContext context) {
    final bib  = runner['bib_number']?.toString() ?? '—';
    final name = runner['name']?.toString() ?? 'Unknown';
    final dist = runner['distance_covered_km']
              ?? runner['distance_covered']
              ?? runner['km_covered'];

    return Container(
      margin:  const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.01),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color:        _kAmber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border:       Border.all(color: _kAmber.withOpacity(0.2)),
              ),
              child: const Text(
                'DNF',
                style: TextStyle(
                  color:         _kAmber,
                  fontSize:      9,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: Text(
              '#$bib',
              style: const TextStyle(color: _kTextSub, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color:      _kTextPri,
                fontSize:   13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (dist != null)
            Text(
              '${(dist as num).toStringAsFixed(1)} km reached',
              style: const TextStyle(color: _kTextSub, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ── DNS row ───────────────────────────────────────────────────────────────────

class _DnsRow extends StatelessWidget {
  final Map<String, dynamic> runner;
  const _DnsRow({required this.runner});

  @override
  Widget build(BuildContext context) {
    final bib  = runner['bib_number']?.toString() ?? '—';
    final name = runner['name']?.toString() ?? 'Unknown';

    return Container(
      margin:  const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color:        _kTextMuted.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border:       Border.all(color: _kTextMuted.withOpacity(0.25)),
              ),
              child: const Text(
                'DNS',
                style: TextStyle(
                  color:         _kTextMuted,
                  fontSize:      9,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: Text(
              '#$bib',
              style: const TextStyle(color: _kTextMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: _kTextSub, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared format utilities ───────────────────────────────────────────────────

String _fmtSecs(int totalSecs) {
  final h = totalSecs ~/ 3600;
  final m = (totalSecs % 3600) ~/ 60;
  final s = totalSecs % 60;
  if (h > 0) {
    return '${h}h ${m.toString().padLeft(2, '0')}m '
        '${s.toString().padLeft(2, '0')}s';
  }
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

String _fmtPace(double secsPerKm) {
  final mins = secsPerKm ~/ 60;
  final secs = (secsPerKm % 60).toInt();
  return '$mins:${secs.toString().padLeft(2, '0')} /km';
}
