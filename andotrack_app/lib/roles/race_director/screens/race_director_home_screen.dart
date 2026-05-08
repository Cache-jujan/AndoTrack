// lib/roles/race_director/screens/race_director_home_screen.dart
//
// WEB-ONLY Races management panel — shown on the "Races" tab of the shell.
// Handles: race listing (grouped by status), create race dialog, tap-to-open.

import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/roles/race_director/screens/race_setup_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/live_race_dashboard_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/post_race_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg         = Color(0xFF080810);
const _kSurface    = Color(0xFF0D0D18);
const _kBorder     = Color(0xFF1E1E32);
const _kGreen      = Color(0xFF00FF9C);
const _kBlue       = Color(0xFF00B4FF);
const _kAmber      = Color(0xFFFFB800);
const _kRed        = Color(0xFFFF4D4D);
const _kPurple     = Color(0xFF8B5CF6);
const _kTextPri    = Colors.white;
const _kTextSub    = Color(0xFF8888AA);
const _kTextMuted  = Color(0xFF3A3A55);

// ─────────────────────────────────────────────────────────────────────────────

class RaceDirectorHomeScreen extends StatefulWidget {
  const RaceDirectorHomeScreen({super.key});

  @override
  State<RaceDirectorHomeScreen> createState() =>
      _RaceDirectorHomeScreenState();
}

class _RaceDirectorHomeScreenState extends State<RaceDirectorHomeScreen> {
  List<Map<String, dynamic>> _races  = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaces();
  }

  Future<void> _loadRaces() async {
    setState(() { _loading = true; _error = null; });
    try {
      final races = await ApiService.getRaces();
      if (mounted) setState(() { _races = races; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

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

  void _openCreateRace() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateRaceDialog(onCreated: () {
        Navigator.pop(context);
        _loadRaces();
      }),
    );
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
    final live     = _races.where((r) => r['status'] == 'active').toList();
    final upcoming = _races.where((r) {
      final s = r['status']?.toString() ?? '';
      return s == 'upcoming' || s == 'registration_open' || s == 'race_day';
    }).toList();
    final finished = _races.where((r) => r['status'] == 'finished').toList();

    return RefreshIndicator(
      color:           _kGreen,
      backgroundColor: _kSurface,
      onRefresh:       _loadRaces,
      child: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Races',
                        style: TextStyle(
                          color:       _kTextPri,
                          fontSize:    24,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _summaryLine(live.length,
                            upcoming.length, finished.length),
                        style: const TextStyle(
                            color: _kTextSub, fontSize: 13),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Create Race — full dialog, not bottom sheet
                  ElevatedButton.icon(
                    onPressed: _openCreateRace,
                    icon:  const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Create New Race'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.black,
                      elevation:       0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_races.isEmpty) ...[
            SliverFillRemaining(child: _buildEmpty()),
          ] else ...[
            if (live.isNotEmpty) ...[
              _sectionHeader('Live Now', live.length),
              _raceGrid(live),
            ],
            if (upcoming.isNotEmpty) ...[
              _sectionHeader('Upcoming', upcoming.length),
              _raceGrid(upcoming),
            ],
            if (finished.isNotEmpty) ...[
              _sectionHeader('Finished', finished.length),
              _raceGrid(finished),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ],
      ),
    );
  }

  String _summaryLine(int live, int upcoming, int finished) {
    final parts = <String>[];
    if (live > 0)     parts.add('$live live');
    if (upcoming > 0) parts.add('$upcoming upcoming');
    if (finished > 0) parts.add('$finished finished');
    return parts.isEmpty ? 'No races yet' : parts.join('  ·  ');
  }

  Widget _sectionHeader(String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                  color:       _kTextPri,
                  fontSize:    13,
                  fontWeight:  FontWeight.w700,
                  letterSpacing: 0.1,
                )),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: _kTextSub, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _raceGrid(List<Map<String, dynamic>> races) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 380,
          mainAxisExtent:     210,
          mainAxisSpacing:    10,
          crossAxisSpacing:   10,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _RaceCard(
            race:  races[i],
            onTap: () => _openRace(races[i]),
          ),
          childCount: races.length,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined,
              size: 56, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 20),
          const Text('No races yet',
              style: TextStyle(
                  color: _kTextSub, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Create your first race to get started.',
              style: TextStyle(color: _kTextMuted, fontSize: 13)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _openCreateRace,
            icon:  const Icon(Icons.add_rounded, size: 17),
            label: const Text('Create New Race'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 13),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
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
            onPressed: _loadRaces,
            child: const Text('Retry',
                style: TextStyle(color: _kBlue)),
          ),
        ],
      ),
    );
  }
}

// ── Race card ─────────────────────────────────────────────────────────────────

class _RaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback         onTap;
  const _RaceCard({required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status     = race['status']?.toString() ?? 'upcoming';
    final name       = race['name']?.toString() ?? 'Unnamed Race';
    final distanceKm = race['distance_km'];
    final location   = race['location']?.toString();
    final scheduled  = race['scheduled_start']?.toString();
    final maxP       = race['max_participants'] as int?;
    final count      = race['participant_count'] as int? ?? 0;
    final isActive   = status == 'active';

    final statusColor = _statusColor(status);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? _kGreen.withOpacity(0.35)
                  : _kBorder,
            ),
            boxShadow: isActive
                ? [BoxShadow(
                    color:     _kGreen.withOpacity(0.07),
                    blurRadius: 16)]
                : null,
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(status: status),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16,
                      color: _kTextMuted),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  color:       _kTextPri,
                  fontSize:    15,
                  fontWeight:  FontWeight.w700,
                  letterSpacing: -0.2,
                  height:      1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (distanceKm != null)
                    _MetaChip(
                      icon:  Icons.straighten_rounded,
                      label: '${(distanceKm as num).toStringAsFixed(0)} km',
                    ),
                  if (location != null)
                    _MetaChip(
                      icon:  Icons.place_outlined,
                      label: location,
                      maxWidth: 120,
                    ),
                  if (scheduled != null)
                    _MetaChip(
                      icon:  Icons.calendar_today_outlined,
                      label: _formatDate(scheduled),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 12, color: _kTextMuted),
                  const SizedBox(width: 5),
                  Text(
                    maxP != null
                        ? '$count / $maxP runners'
                        : '$count runners',
                    style: const TextStyle(
                        color: _kTextSub, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'active':            return _kGreen;
      case 'finished':          return _kTextMuted;
      case 'registration_open': return _kBlue;
      case 'race_day':          return _kAmber;
      default:                  return _kPurple;
    }
  }

  static String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = ['','Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month]} · $h:$m';
    } catch (_) { return raw; }
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color  color;
    String label;
    bool   dot = false;
    switch (status) {
      case 'active':
        color = _kGreen;   label = 'LIVE';      dot = true; break;
      case 'registration_open':
        color = _kBlue;    label = 'OPEN';       break;
      case 'race_day':
        color = _kAmber;   label = 'RACE DAY';   break;
      case 'finished':
        color = _kTextMuted; label = 'FINISHED'; break;
      default:
        color = _kPurple;  label = 'UPCOMING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                color:         color,
                fontSize:      10,
                fontWeight:    FontWeight.w800,
                letterSpacing: 0.5,
              )),
        ],
      ),
    );
  }
}

// ── Meta chip ─────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final double?  maxWidth;
  const _MetaChip({required this.icon, required this.label, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(
            color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: _kTextMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: const TextStyle(
                    color: _kTextSub, fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ── Create Race Dialog ────────────────────────────────────────────────────────
// Full-screen centered Dialog — much more web-appropriate than a bottom sheet.
// Two-column layout: left = race basics, right = date/location/settings.

class _CreateRaceDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateRaceDialog({required this.onCreated});

  @override
  State<_CreateRaceDialog> createState() => _CreateRaceDialogState();
}

class _CreateRaceDialogState extends State<_CreateRaceDialog> {
  final _nameCtrl     = TextEditingController();
  final _distCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _maxPCtrl     = TextEditingController();

  DateTime? _scheduledStart;
  bool      _isSaving      = false;
  String?   _validationErr;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _distCtrl.dispose();
    _locationCtrl.dispose();
    _maxPCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context:     context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate:   now,
      lastDate:    now.add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
              primary: _kGreen, surface: _kSurface),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context:     context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
              primary: _kGreen, surface: _kSurface),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _scheduledStart = DateTime(
          picked.year, picked.month, picked.day,
          time.hour, time.minute);
    });
  }

  String _fmtDate(DateTime dt) {
    const months = ['','Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year}  ·  $h:$m';
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final dist = double.tryParse(_distCtrl.text.trim());
    final maxP = int.tryParse(_maxPCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _validationErr = 'Race name is required.');
      return;
    }
    if (dist == null || dist <= 0) {
      setState(
          () => _validationErr = 'Enter a valid distance (km).');
      return;
    }
    setState(() { _isSaving = true; _validationErr = null; });
    try {
      await ApiService.createRace({
        'name':           name,
        'distance_km':    dist,
        'location':       _locationCtrl.text.trim().isEmpty
            ? null : _locationCtrl.text.trim(),
        'scheduled_start': _scheduledStart?.toIso8601String(),
        'status':          'upcoming',
        'registration_fee': 0.0,
        if (maxP != null && maxP > 0) 'max_participants': maxP,
      });
      widget.onCreated();
    } catch (e) {
      setState(() {
        _isSaving      = false;
        _validationErr = 'Failed to create race: $e';
      });
    }
  }

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
    hintText:   hint,
    hintStyle:  TextStyle(
        color: Colors.white.withOpacity(0.2), fontSize: 13),
    prefixIcon: Icon(icon, color: _kTextSub, size: 16),
    filled:     true,
    fillColor:  Colors.white.withOpacity(0.03),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide:   BorderSide(color: _kGreen, width: 1.5),
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(
            maxWidth: 680, maxHeight: 560),
        decoration: BoxDecoration(
          color:        _kSurface,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color:     Colors.black.withOpacity(0.5),
              blurRadius: 40,
              offset:    const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Dialog header ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color:        _kGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.flag_rounded,
                        color: _kGreen, size: 18),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Create New Race',
                    style: TextStyle(
                      color:      _kTextPri,
                      fontSize:   17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _kTextSub, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Form body — two columns ───────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              _label('Race Name *'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameCtrl,
                                style: const TextStyle(
                                    color: _kTextPri, fontSize: 13),
                                decoration: _deco(
                                    'e.g. Cebu City Marathon 2026',
                                    Icons.flag_rounded),
                              ),
                              const SizedBox(height: 18),
                              _label('Distance (km) *'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _distCtrl,
                                keyboardType:
                                    const TextInputType
                                        .numberWithOptions(decimal: true),
                                style: const TextStyle(
                                    color: _kTextPri, fontSize: 13),
                                decoration: _deco(
                                    'e.g. 42.195',
                                    Icons.straighten_rounded),
                              ),
                              const SizedBox(height: 18),
                              _label('Max Participants'),
                              const SizedBox(height: 8),
                              TextField(
                                controller:   _maxPCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                    color: _kTextPri, fontSize: 13),
                                decoration: _deco(
                                    'Leave blank for unlimited',
                                    Icons.people_outline_rounded),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 24),

                        // Right column
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              _label('Location'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _locationCtrl,
                                style: const TextStyle(
                                    color: _kTextPri, fontSize: 13),
                                decoration: _deco(
                                    'e.g. Cebu City',
                                    Icons.place_outlined),
                              ),
                              const SizedBox(height: 18),
                              _label('Race Date & Time'),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _pickDate,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 13),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withOpacity(0.03),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.white
                                            .withOpacity(0.1)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons
                                              .calendar_today_outlined,
                                          color: _kTextSub,
                                          size: 16),
                                      const SizedBox(width: 10),
                                      Text(
                                        _scheduledStart == null
                                            ? 'Select date and time'
                                            : _fmtDate(
                                                _scheduledStart!),
                                        style: TextStyle(
                                          color: _scheduledStart ==
                                                  null
                                              ? Colors.white
                                                  .withOpacity(0.2)
                                              : _kTextPri,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Validation error
                    if (_validationErr != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width:   double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:        _kRed.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _kRed.withOpacity(0.3)),
                        ),
                        child: Text(_validationErr!,
                            style: const TextStyle(
                                color: _kRed, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Footer actions ────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: _kBorder)),
              ),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTextSub,
                      side: const BorderSide(color: _kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 13),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 13),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth:  2,
                                color:        Colors.black))
                        : const Text('Create Race'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color:      _kTextSub,
      fontSize:   12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
  );
}
