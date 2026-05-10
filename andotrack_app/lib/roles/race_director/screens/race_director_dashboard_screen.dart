// lib/roles/race_director/screens/race_director_dashboard_screen.dart
//
// WEB-ONLY Dashboard — the Home tab for the Race Director shell.
// Shows an overview: key stats, live race quick-access, and upcoming races.
// Race creation and full management lives in the Races tab.

import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/utils/date_utils.dart';
import 'package:andotrack_app/roles/race_director/screens/live_race_dashboard_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/race_setup_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/post_race_screen.dart';

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

class RaceDirectorDashboardScreen extends StatefulWidget {
  const RaceDirectorDashboardScreen({super.key});

  @override
  State<RaceDirectorDashboardScreen> createState() =>
      _RaceDirectorDashboardScreenState();
}

class _RaceDirectorDashboardScreenState
    extends State<RaceDirectorDashboardScreen> {
  List<Map<String, dynamic>> _races   = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final races = await ApiService.getRaces();
      if (mounted) setState(() { _races = races; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  // ── Derived stats ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _live     =>
      _races.where((r) => r['status'] == 'active').toList();
  List<Map<String, dynamic>> get _upcoming =>
      _races.where((r) {
        final s = r['status']?.toString() ?? '';
        return s == 'upcoming' || s == 'registration_open' || s == 'race_day';
      }).toList();
  List<Map<String, dynamic>> get _finished =>
      _races.where((r) => r['status'] == 'finished').toList();

  int get _totalRegistered =>
      _races.fold(0, (s, r) => s + ((r['participant_count'] as int?) ?? 0));

  void _openRace(Map<String, dynamic> race) {
    final status = race['status']?.toString() ?? 'upcoming';
    switch (status) {
      case 'active':
        Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => LiveRaceDashboardScreen(race: race)));
        break;
      case 'finished':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => PostRaceScreen(race: race)));
        break;
      default:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => RaceSetupScreen(race: race)));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: _kGreen, strokeWidth: 2))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      color:           _kGreen,
      backgroundColor: _kSurface,
      onRefresh:       _load,
      child: CustomScrollView(
        slivers: [
          // ── Page title ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dashboard',
                        style: TextStyle(
                          color:       _kTextPri,
                          fontSize:    24,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_races.length} race${_races.length == 1 ? '' : 's'} total'
                        '  ·  $_totalRegistered registered',
                        style: const TextStyle(
                            color: _kTextSub, fontSize: 13),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Refresh button
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

          // ── Stats cards ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  _StatCard(
                    label: 'Live Now',
                    value: '${_live.length}',
                    icon:  Icons.radio_button_on_rounded,
                    color: _kGreen,
                    pulsing: _live.isNotEmpty,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Upcoming',
                    value: '${_upcoming.length}',
                    icon:  Icons.calendar_today_outlined,
                    color: _kBlue,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Finished',
                    value: '${_finished.length}',
                    icon:  Icons.flag_outlined,
                    color: _kTextMuted,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Total Runners',
                    value: '$_totalRegistered',
                    icon:  Icons.directions_run_rounded,
                    color: _kPurple,
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),

          // ── Live races (prominent) ────────────────────────────────
          if (_live.isNotEmpty) ...[
            _sectionHeader('Live Now', _kGreen, Icons.radio_button_on_rounded),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _LiveRaceCard(
                    race:  _live[i],
                    onTap: () => _openRace(_live[i]),
                  ),
                  childCount: _live.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],

          // ── Upcoming (needs attention) ────────────────────────────
          if (_upcoming.isNotEmpty) ...[
            _sectionHeader('Upcoming', _kAmber, Icons.flag_circle_outlined),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent:     130,
                  mainAxisSpacing:    10,
                  crossAxisSpacing:   10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _UpcomingCard(
                    race:  _upcoming[i],
                    onTap: () => _openRace(_upcoming[i]),
                  ),
                  childCount: _upcoming.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],

          // ── Recent finished ───────────────────────────────────────
          if (_finished.isNotEmpty) ...[
            _sectionHeader('Recent Finished', _kTextMuted,
                Icons.history_rounded),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent:     110,
                  mainAxisSpacing:    10,
                  crossAxisSpacing:   10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _FinishedCard(
                    race:  _finished[i],
                    onTap: () => _openRace(_finished[i]),
                  ),
                  childCount: _finished.take(6).length,
                ),
              ),
            ),
          ],

          if (_races.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 52,
                        color: Colors.white.withOpacity(0.06)),
                    const SizedBox(height: 16),
                    const Text(
                      'No races yet',
                      style: TextStyle(
                          color: _kTextSub,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Go to the Races tab to create your first race.',
                      style: TextStyle(
                          color: _kTextMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color, IconData icon) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color:       color,
                fontSize:    13,
                fontWeight:  FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            onPressed: _load,
            child: const Text('Retry',
                style: TextStyle(color: _kBlue)),
          ),
        ],
      ),
    );
  }
}

// ── Live race card ────────────────────────────────────────────────────────────

class _LiveRaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback         onTap;
  const _LiveRaceCard({required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name    = race['name']?.toString() ?? 'Unnamed Race';
    final distKm  = race['distance_km'];
    final count   = race['participant_count'] as int? ?? 0;
    final location = race['location']?.toString();

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _kGreen.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                  color: _kGreen.withOpacity(0.06),
                  blurRadius: 16),
            ],
          ),
          child: Row(
            children: [
              // Status indicator
              Column(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color:  _kGreen,
                      shape:  BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color:     _kGreen.withOpacity(0.6),
                            blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color:       _kTextPri,
                        fontSize:    16,
                        fontWeight:  FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (distKm != null)
                          Text(
                            '${(distKm as num).toStringAsFixed(0)} km',
                            style: const TextStyle(
                                color: _kTextSub, fontSize: 12),
                          ),
                        if (location != null)
                          Text(location,
                              style: const TextStyle(
                                  color: _kTextSub, fontSize: 12)),
                        Text(
                          '$count runners',
                          style: const TextStyle(
                              color: _kTextMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // CTA
              ElevatedButton.icon(
                onPressed: onTap,
                icon:  const Icon(Icons.open_in_new_rounded, size: 14),
                label: const Text('View Live'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upcoming race card ────────────────────────────────────────────────────────

class _UpcomingCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback         onTap;
  const _UpcomingCard({required this.race, required this.onTap});

  static String _fmtDate(String raw) {
    try {
      final dt = parsePht(raw);
      const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${m[dt.month]}  ·  $h:$min';
    } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final name       = race['name']?.toString() ?? 'Unnamed';
    final status     = race['status']?.toString() ?? 'upcoming';
    final scheduled  = race['scheduled_start']?.toString();
    final count      = race['participant_count'] as int? ?? 0;
    final distKm     = race['distance_km'];

    Color  badgeColor;
    String badgeLabel;
    switch (status) {
      case 'registration_open': badgeColor = _kBlue;   badgeLabel = 'OPEN'; break;
      case 'race_day':          badgeColor = _kAmber;  badgeLabel = 'RACE DAY'; break;
      default:                  badgeColor = _kPurple; badgeLabel = 'UPCOMING';
    }

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color:        badgeColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: badgeColor.withOpacity(0.35)),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        color:         badgeColor,
                        fontSize:      9,
                        fontWeight:    FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (distKm != null)
                    Text(
                      '${(distKm as num).toStringAsFixed(0)} km',
                      style: const TextStyle(
                          color: _kTextMuted, fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: const TextStyle(
                  color:       _kTextPri,
                  fontSize:    13,
                  fontWeight:  FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 11, color: _kTextMuted),
                  const SizedBox(width: 4),
                  Text('$count',
                      style: const TextStyle(
                          color: _kTextSub, fontSize: 11)),
                  const Spacer(),
                  if (scheduled != null)
                    Text(
                      _fmtDate(scheduled),
                      style: const TextStyle(
                          color: _kTextMuted, fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Finished race card ────────────────────────────────────────────────────────

class _FinishedCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback         onTap;
  const _FinishedCard({required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name  = race['name']?.toString() ?? 'Unnamed';
    final count = race['participant_count'] as int? ?? 0;
    final distKm = race['distance_km'];

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(
                color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_rounded,
                      size: 13, color: _kTextMuted),
                  const SizedBox(width: 6),
                  const Text('FINISHED',
                      style: TextStyle(
                        color:         _kTextMuted,
                        fontSize:      9,
                        fontWeight:    FontWeight.w800,
                        letterSpacing: 0.4,
                      )),
                  const Spacer(),
                  if (distKm != null)
                    Text(
                      '${(distKm as num).toStringAsFixed(0)} km',
                      style: const TextStyle(
                          color: _kTextMuted, fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: const TextStyle(
                  color:       _kTextSub,
                  fontSize:    13,
                  fontWeight:  FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 11, color: _kTextMuted),
                  const SizedBox(width: 4),
                  Text('$count runners',
                      style: const TextStyle(
                          color: _kTextMuted, fontSize: 11)),
                  const Spacer(),
                  Text(
                    'View results →',
                    style: TextStyle(
                      color:      _kBlue.withOpacity(0.7),
                      fontSize:   10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
  final bool     pulsing;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(
            color: pulsing
                ? color.withOpacity(0.3)
                : _kBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:        color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                if (pulsing) ...[
                  const Spacer(),
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color:  color,
                      shape:  BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:     color.withOpacity(0.7),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                color:       color,
                fontSize:    28,
                fontWeight:  FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  color: _kTextSub, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
