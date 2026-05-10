import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/checkpoint/services/checkpoint_service.dart';
import 'package:andotrack_app/roles/race_director/screens/checkpoint_placement_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/live_race_dashboard_screen.dart';

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

class RaceSetupScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const RaceSetupScreen({super.key, required this.race});

  @override
  State<RaceSetupScreen> createState() => _RaceSetupScreenState();
}

class _RaceSetupScreenState extends State<RaceSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late Map<String, dynamic> _race;

  // ── Per-tab data ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _runners      = [];
  List<Map<String, dynamic>> _checkpoints  = [];
  List<Map<String, dynamic>> _staff        = [];

  bool    _loadingRunners     = true;
  bool    _loadingCheckpoints = true;
  bool    _loadingStaff       = true;
  String? _runnersError;
  String? _staffError;

  // ── Registrations tab state ────────────────────────────────────────────────
  String _searchQuery = '';

  // ── Settings tab state ────────────────────────────────────────────────────
  double     _gpsAccuracy        = 15.0;
  String     _anomalySensitivity = 'medium';
  TimeOfDay? _checkInOpen;
  TimeOfDay? _checkInClose;
  int        _walkInSlots        = 0;
  late final TextEditingController _walkInCtrl;
  bool       _savingSettings     = false;
  bool       _settingsSaved      = false;

  // ── Race start ────────────────────────────────────────────────────────────
  bool _startingRace   = false;
  bool _markingRaceDay = false;

  // ── Helpers ───────────────────────────────────────────────────────────────
  int    get _raceId     => (_race['id'] as num).toInt();
  String get _raceName   => _race['name']?.toString() ?? 'Race';
  String get _raceStatus => _race['status']?.toString() ?? 'upcoming';
  bool   get _isRaceDay  => _raceStatus == 'race_day';

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _race    = Map<String, dynamic>.from(widget.race);
    _tabCtrl = TabController(length: 4, vsync: this);
    _walkInSlots        = (_race['walk_in_slots'] as num?)?.toInt() ?? 0;
    _walkInCtrl         = TextEditingController(text: '$_walkInSlots');
    _gpsAccuracy        = ((_race['gps_accuracy_threshold'] as num?)?.toDouble() ?? 15.0).clamp(5.0, 50.0);
    _anomalySensitivity = _race['anomaly_sensitivity'] as String? ?? 'medium';
    _loadPreferenceDefaults();
    final openStr  = _race['checkin_open']  as String?;
    final closeStr = _race['checkin_close'] as String?;
    if (openStr != null) {
      final p = openStr.split(':');
      if (p.length >= 2) {
        _checkInOpen = TimeOfDay(
            hour:   int.tryParse(p[0]) ?? 0,
            minute: int.tryParse(p[1]) ?? 0);
      }
    }
    if (closeStr != null) {
      final p = closeStr.split(':');
      if (p.length >= 2) {
        _checkInClose = TimeOfDay(
            hour:   int.tryParse(p[0]) ?? 0,
            minute: int.tryParse(p[1]) ?? 0);
      }
    }
    _refreshRaceStatus();
    _loadRunners();
    _loadCheckpoints();
    _loadStaff();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _walkInCtrl.dispose();
    super.dispose();
  }

  // ── Preference defaults (fills in values not set on the race object) ─────────

  Future<void> _loadPreferenceDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Only override if the race object didn't supply a value (i.e. we still
    // hold the hard-coded fallback of 15.0 / 'medium').
    final hasGps  = (_race['gps_accuracy_threshold'] as num?) != null;
    final hasSens = (_race['anomaly_sensitivity'] as String?) != null;
    if (!hasGps || !hasSens) {
      setState(() {
        if (!hasGps) {
          final saved = prefs.getDouble('default_gps_accuracy');
          if (saved != null) _gpsAccuracy = saved.clamp(5.0, 50.0);
        }
        if (!hasSens) {
          final saved = prefs.getString('default_anomaly_sensitivity');
          if (saved != null) _anomalySensitivity = saved;
        }
      });
    }
  }

  // ── Data loaders ───────────────────────────────────────────────────────────

  Future<void> _refreshRaceStatus() async {
    try {
      final fresh = await ApiService.getRace(_raceId);
      if (!mounted) return;
      // If already active, jump straight to live dashboard
      if (fresh['status'] == 'active') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LiveRaceDashboardScreen(race: fresh),
          ),
        );
        return;
      }
      setState(() {
        _race['status']      = fresh['status'];
        _race['walk_in_slots'] = fresh['walk_in_slots'] ?? _race['walk_in_slots'];
      });
    } catch (_) {
      // Non-critical — keep whatever status was passed at navigation time
    }
  }

  Future<void> _loadRunners() async {
    setState(() { _loadingRunners = true; _runnersError = null; });
    try {
      final runners = await ApiService.getRaceRunners(_raceId);
      if (mounted) setState(() { _runners = runners; _loadingRunners = false; });
    } catch (e) {
      if (mounted) setState(() {
        _runnersError = 'Failed to load registrations.';
        _loadingRunners = false;
      });
    }
  }

  Future<void> _loadCheckpoints() async {
    setState(() => _loadingCheckpoints = true);
    final cps = await CheckpointService.getCheckpoints(_raceId);
    if (mounted) setState(() { _checkpoints = cps; _loadingCheckpoints = false; });
  }

  Future<void> _loadStaff() async {
    setState(() { _loadingStaff = true; _staffError = null; });
    try {
      final staff = await ApiService.getStaffAccounts(_raceId);
      if (mounted) setState(() { _staff = staff; _loadingStaff = false; });
    } catch (e) {
      if (mounted) setState(() {
        _staffError = 'Failed to load staff accounts.';
        _loadingStaff = false;
      });
    }
  }

  // ── Start race ─────────────────────────────────────────────────────────────

  Future<void> _startRace() async {
    final confirmed = await _showStartConfirmation();
    if (confirmed != true || !mounted) return;

    setState(() => _startingRace = true);
    try {
      await ApiService.startRace(_raceId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LiveRaceDashboardScreen(
            race: {..._race, 'status': 'active'},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingRace = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to start race: $e',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.w600)),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  Future<bool?> _showStartConfirmation() => showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kGreen.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: _kGreen, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text('Start Race?',
                      style: TextStyle(
                          color: _kTextPri,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'This will make the race live. All checked-in runners '
                'will begin tracking from this moment.',
                style: TextStyle(color: _kTextSub, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTextSub,
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Start Race',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _markAsRaceDay() async {
  setState(() => _markingRaceDay = true);
  try {
    final fresh = await ApiService.getRace(_raceId); // fetch full object
    fresh['status'] = 'race_day';                    // patch status field
    await ApiService.updateRaceSettings(_raceId, fresh); // PUT full object
    if (!mounted) return;
    await _refreshRaceStatus();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Failed to mark as race day: $e',
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.w600)),
      backgroundColor: _kAmber,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  } finally {
    if (mounted) setState(() => _markingRaceDay = false);
  }
}

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _buildHeader(),
          Container(
            color: _kSurface,
            child: TabBar(
              controller:            _tabCtrl,
              indicatorColor:        _kGreen,
              indicatorWeight:       2,
              labelColor:            _kGreen,
              unselectedLabelColor:  _kTextSub,
              labelStyle:            const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:  const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: 'Registrations'),
                Tab(text: 'Checkpoints'),
                Tab(text: 'Staff Accounts'),
                Tab(text: 'Race Settings'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildRegistrationsTab(),
                _buildCheckpointsTab(),
                _buildStaffTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 20, 14),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _kTextSub),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _raceName,
                  style: const TextStyle(
                    color:       _kTextPri,
                    fontSize:    17,
                    fontWeight:  FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                _StatusBadge(status: _raceStatus),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStartRaceButton(),
        ],
      ),
    );
  }

  Widget _buildStartRaceButton() {
    if (_startingRace) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color:        _kGreen.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: _kGreen.withOpacity(0.3)),
        ),
        child: const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen),
        ),
      );
    }

    if (_isRaceDay) {
      return ElevatedButton.icon(
        onPressed: _startRace,
        icon:  const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Start Race'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kGreen,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    }

    if (_markingRaceDay) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color:        _kAmber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: _kAmber.withOpacity(0.3)),
        ),
        child: const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAmber),
        ),
      );
    }

    if (_raceStatus == 'upcoming') {
      return ElevatedButton.icon(
        onPressed: _markAsRaceDay,
        icon:  const Icon(Icons.flag_rounded, size: 16),
        label: const Text('Mark as Race Day'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAmber,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kTextMuted),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 13, color: _kTextMuted),
          const SizedBox(width: 7),
          const Text('Available on race day',
              style: TextStyle(
                  color: _kTextMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  TAB 1 — REGISTRATIONS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildRegistrationsTab() {
    if (_loadingRunners) {
      return const Center(
          child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2));
    }
    if (_runnersError != null) {
      return _buildErrorState(_runnersError!, _loadRunners);
    }

    final maxP     = (_race['max_participants'] as num?)?.toInt();
    final filtered = _searchQuery.isEmpty
        ? _runners
        : _runners.where((r) {
            final name = (r['name']?.toString() ?? '').toLowerCase();
            final bib  = (r['bib_number']?.toString() ?? '').toLowerCase();
            final q    = _searchQuery.toLowerCase();
            return name.contains(q) || bib.contains(q);
          }).toList();

    return Column(
      children: [
        // Stats + search header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          color: _kSurface,
          child: Column(
            children: [
              Row(
                children: [
                  _StatPill(label: 'Registered', value: '${_runners.length}',
                      color: _kGreen),
                  if (maxP != null) ...[
                    const SizedBox(width: 10),
                    _StatPill(label: 'Capacity', value: '$maxP', color: _kBlue),
                  ],
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _showExportCsvDialog(_runners),
                    icon:  const Icon(Icons.download_outlined, size: 15),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTextSub,
                      side:  const BorderSide(color: _kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),

              if (maxP != null && maxP > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_runners.length / maxP).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: _kBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _runners.length >= maxP ? _kAmber : _kGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_runners.length} registered',
                        style: const TextStyle(color: _kTextSub, fontSize: 11)),
                    Text('$maxP capacity',
                        style: const TextStyle(
                            color: _kTextMuted, fontSize: 11)),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              _buildSearchBar(),
            ],
          ),
        ),
        const Divider(height: 1, color: _kBorder),

        // Runner list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          color: _kTextMuted, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No registrations yet'
                            : 'No results for "$_searchQuery"',
                        style: const TextStyle(
                            color: _kTextSub, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: _kGreen,
                  onRefresh: _loadRunners,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _RunnerRow(runner: filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, color: _kTextMuted, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged:   (q) => setState(() => _searchQuery = q),
              style:       const TextStyle(color: _kTextPri, fontSize: 13),
              decoration:  const InputDecoration(
                hintText:       'Search by name or bib…',
                hintStyle:      TextStyle(color: _kTextMuted, fontSize: 13),
                border:         InputBorder.none,
                isDense:        true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportCsvDialog(List<Map<String, dynamic>> runners) {
    final sb = StringBuffer('Bib,Name,Shirt Size,Status\n');
    for (final r in runners) {
      final bib    = r['bib_number']?.toString() ?? '';
      final name   = (r['name']?.toString() ?? '').replaceAll('"', '""');
      final shirt  = r['shirt_size']?.toString() ?? '';
      final status = _runnerStatus(r);
      sb.writeln('$bib,"$name",$shirt,$status');
    }

    showDialog<void>(
      context: context,
      builder: (_) => _CsvExportDialog(csv: sb.toString(), filename: 'runners'),
    );
  }

  static String _runnerStatus(Map<String, dynamic> r) {
    if (r['is_checked_in'] == true) return 'Checked In';
    final s = r['status']?.toString() ?? '';
    if (s == 'dns') return 'DNS';
    if (s == 'dnf') return 'DNF';
    if (s == 'finished') return 'Finished';
    return 'Registered';
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  TAB 2 — CHECKPOINTS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCheckpointsTab() {
    return Column(
      children: [
        // Compact non-interactive map preview
        if (!_loadingCheckpoints && _checkpoints.isNotEmpty)
          SizedBox(
            height: 200,
            child: IgnorePointer(child: _buildMapPreview()),
          ),

        // Action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: _kSurface,
          child: Row(
            children: [
              Text(
                '${_checkpoints.length} checkpoint${_checkpoints.length == 1 ? '' : 's'}',
                style: const TextStyle(color: _kTextSub, fontSize: 13),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CheckpointPlacementScreen(
                        raceId:        _raceId,
                        raceDistanceKm:
                            (_race['distance_km'] as num?)?.toDouble(),
                      ),
                    ),
                  );
                  _loadCheckpoints();
                },
                icon:  const Icon(Icons.map_rounded, size: 15),
                label: const Text('Manage on Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue.withOpacity(0.12),
                  foregroundColor: _kBlue,
                  elevation: 0,
                  side: const BorderSide(color: _kBlue, width: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _kBorder),

        // Checkpoint list
        Expanded(
          child: _loadingCheckpoints
              ? const Center(
                  child: CircularProgressIndicator(
                      color: _kGreen, strokeWidth: 2))
              : _checkpoints.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_off_rounded,
                              color: _kTextMuted, size: 40),
                          const SizedBox(height: 12),
                          const Text('No checkpoints yet',
                              style: TextStyle(
                                  color: _kTextSub, fontSize: 14)),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap "Manage on Map" to add checkpoints.',
                            style: TextStyle(
                                color: _kTextMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: _checkpoints.length,
                      itemBuilder: (_, i) => _CheckpointRow(
                        checkpoint: _checkpoints[i],
                        index:      i,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildMapPreview() {
    final ordered = _checkpoints.toList()
      ..sort((a, b) => (a['order_number'] as int? ?? 0)
          .compareTo(b['order_number'] as int? ?? 0));

    LatLng center = const LatLng(10.3157, 123.8854);
    if (ordered.isNotEmpty) {
      center = LatLng(
        (ordered.first['lat'] as num).toDouble(),
        (ordered.first['lng'] as num).toDouble(),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom:   13,
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.andotrack.app',
        ),
        CircleLayer(
          circles: ordered.map((cp) => CircleMarker(
            point: LatLng(
                (cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
            radius: (cp['radius_meters'] as num?)?.toDouble() ?? 20.0,
            color:        _kBlue.withOpacity(0.12),
            borderColor:  _kBlue.withOpacity(0.5),
            borderStrokeWidth: 1.5,
            useRadiusInMeter: true,
          )).toList(),
        ),
        MarkerLayer(
          markers: ordered.asMap().entries.map((e) {
            final i     = e.key;
            final cp    = e.value;
            final name  = (cp['name'] as String?)?.toLowerCase() ?? '';
            final isS   = name == 'start';
            final isE   = name == 'finish' || name == 'end';
            final color = isS ? _kGreen : isE ? _kRed : _kBlue;
            final label = isS ? 'S' : isE ? 'E' : '${i}';
            return Marker(
              point: LatLng(
                  (cp['lat'] as num).toDouble(),
                  (cp['lng'] as num).toDouble()),
              width: 28, height: 28,
              child: Container(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)]),
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.black, fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  TAB 3 — STAFF ACCOUNTS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStaffTab() {
    if (_loadingStaff) {
      return const Center(
          child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: _kSurface,
          child: Row(
            children: [
              Text(
                '${_staff.length} account${_staff.length == 1 ? '' : 's'}',
                style: const TextStyle(color: _kTextSub, fontSize: 13),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _openCreateStaffDialog,
                icon:  const Icon(Icons.add_rounded, size: 16),
                label: const Text('Create Staff Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _kBorder),

        Expanded(
          child: _staffError != null
              ? _buildErrorState(_staffError!, _loadStaff)
              : _staff.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.badge_outlined,
                              color: _kTextMuted, size: 40),
                          const SizedBox(height: 12),
                          const Text('No staff accounts yet',
                              style: TextStyle(
                                  color: _kTextSub, fontSize: 14)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: _staff.length,
                      itemBuilder: (_, i) => _SetupStaffRow(
                        account: _staff[i],
                        onTap:   () => _openStaffOptions(_staff[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  void _openCreateStaffDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SetupCreateStaffDialog(
        raceId: _raceId,
        onCreated: (name, tempPw) {
          _loadStaff();
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (_) =>
                _SetupTempPasswordDialog(name: name, tempPassword: tempPw),
          );
        },
      ),
    );
  }

  void _openStaffOptions(Map<String, dynamic> account) {
    final isActive = account['is_active'] as bool? ?? true;
    showDialog<void>(
      context: context,
      builder: (_) => _SetupStaffOptionsDialog(
        account:      account,
        onDeactivate: isActive
            ? () {
                Navigator.pop(context);
                _deactivateStaff(account);
              }
            : null,
      ),
    );
  }

  Future<void> _deactivateStaff(Map<String, dynamic> account) async {
    try {
      final staffId = (account['staff_id'] ?? account['id']) as int;
      await ApiService.deactivateStaffAccount(_raceId, staffId);
      _loadStaff();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to deactivate: $e'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  TAB 4 — RACE SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // GPS accuracy
            _SettingsLabel(
              title: 'GPS Accuracy Threshold',
              subtitle:
                  'Minimum accuracy required to record a runner position.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value:      _gpsAccuracy,
                    min:        5,
                    max:        50,
                    divisions:  9,
                    activeColor:   _kGreen,
                    inactiveColor: _kBorder,
                    onChanged:  (v) => setState(() => _gpsAccuracy = v),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:        _kGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: _kGreen.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_gpsAccuracy.round()} m',
                    style: const TextStyle(
                        color:      _kGreen,
                        fontSize:   13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),
            const Divider(color: _kBorder),
            const SizedBox(height: 28),

            // Anomaly sensitivity
            _SettingsLabel(
              title: 'Anomaly Detection Sensitivity',
              subtitle:
                  'Controls how aggressively suspicious runner movements are flagged.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _SensitivityChip(
                  label:    'Low',
                  selected: _anomalySensitivity == 'low',
                  color:    _kBlue,
                  onTap:    () => setState(() => _anomalySensitivity = 'low'),
                ),
                const SizedBox(width: 8),
                _SensitivityChip(
                  label:    'Medium',
                  selected: _anomalySensitivity == 'medium',
                  color:    _kAmber,
                  onTap:    () => setState(() => _anomalySensitivity = 'medium'),
                ),
                const SizedBox(width: 8),
                _SensitivityChip(
                  label:    'High',
                  selected: _anomalySensitivity == 'high',
                  color:    _kRed,
                  onTap:    () => setState(() => _anomalySensitivity = 'high'),
                ),
              ],
            ),

            const SizedBox(height: 28),
            const Divider(color: _kBorder),
            const SizedBox(height: 28),

            // Check-in window
            _SettingsLabel(
              title: 'Check-in Window',
              subtitle: 'Time range during which runners can check in.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _TimePickerField(
                    label: 'Opens',
                    time:  _checkInOpen,
                    onTap: () async {
                      final t = await _pickTime(
                          _checkInOpen ?? const TimeOfDay(hour: 5, minute: 0));
                      if (t != null) setState(() => _checkInOpen = t);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _TimePickerField(
                    label: 'Closes',
                    time:  _checkInClose,
                    onTap: () async {
                      final t = await _pickTime(
                          _checkInClose ?? const TimeOfDay(hour: 7, minute: 0));
                      if (t != null) setState(() => _checkInClose = t);
                    },
                  ),
                ),
              ],
            ),

            const Divider(color: _kBorder, height: 40),

            const Text('Walk-in Bib Pool',
                style: TextStyle(
                    color: _kTextSub, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _walkInCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: _kTextPri, fontSize: 14),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: const TextStyle(color: _kTextMuted),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kGreen)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) =>
                  _walkInSlots = int.tryParse(v) ?? 0,
            ),

            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _savingSettings ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _settingsSaved
                      ? _kGreen.withOpacity(0.8)
                      : _kGreen,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _savingSettings
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        _settingsSaved ? 'Saved!' : 'Save Settings',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) => showTimePicker(
    context: context,
    initialTime: initial,
    builder: (ctx, child) => Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
            primary: _kGreen, surface: _kSurface),
      ),
      child: child!,
    ),
  );

  Future<void> _saveSettings() async {
    setState(() { _savingSettings = true; _settingsSaved = false; });
    try {
      await ApiService.updateRaceSettings(_raceId, {
        'gps_accuracy_threshold': _gpsAccuracy.round(),
        'anomaly_sensitivity':    _anomalySensitivity,
        'walk_in_slots':          _walkInSlots,
        if (_checkInOpen != null)
          'checkin_open': _fmtTime(_checkInOpen!),
        if (_checkInClose != null)
          'checkin_close': _fmtTime(_checkInClose!),
      });
      if (!mounted) return;
      setState(() { _savingSettings = false; _settingsSaved = true; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _settingsSaved = false);
    } catch (_) {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: _kTextMuted, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: _kBlue)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISPLAY WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color  color;
    String label;
    switch (status) {
      case 'active':            color = _kGreen;  label = 'LIVE';         break;
      case 'registration_open': color = _kBlue;   label = 'OPEN';         break;
      case 'race_day':          color = _kAmber;  label = 'RACE DAY';     break;
      case 'finished':          color = _kTextMuted; label = 'FINISHED';  break;
      default:                  color = _kPurple; label = 'UPCOMING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9,
              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.6), fontSize: 11)),
        ],
      ),
    );
  }
}

class _RunnerRow extends StatelessWidget {
  final Map<String, dynamic> runner;
  const _RunnerRow({required this.runner});

  static String _status(Map<String, dynamic> r) {
    if (r['is_checked_in'] == true) return 'Checked In';
    final s = r['status']?.toString() ?? '';
    if (s == 'dns') return 'DNS';
    if (s == 'dnf') return 'DNF';
    return 'Registered';
  }

  @override
  Widget build(BuildContext context) {
    final bib    = runner['bib_number']?.toString() ?? '—';
    final name   = runner['name']?.toString() ?? 'Unknown';
    final shirt  = runner['shirt_size']?.toString() ?? '—';
    final status = _status(runner);

    Color  statusColor;
    switch (status) {
      case 'Checked In': statusColor = _kGreen;    break;
      case 'DNS':        statusColor = _kTextMuted; break;
      case 'DNF':        statusColor = _kAmber;     break;
      default:           statusColor = _kBlue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        const Color(0xFF0D0D18),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(bib,
                style: const TextStyle(
                    color: _kTextSub, fontSize: 11,
                    fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    color: _kTextPri, fontSize: 13,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          Text(shirt, style: const TextStyle(color: _kTextMuted, fontSize: 12)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border:       Border.all(color: statusColor.withOpacity(0.35)),
            ),
            child: Text(status,
                style: TextStyle(
                    color:      statusColor,
                    fontSize:   10,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  final Map<String, dynamic> checkpoint;
  final int                  index;
  const _CheckpointRow({required this.checkpoint, required this.index});

  static String _type(String name) {
    final lower = name.toLowerCase();
    if (lower == 'start' || lower == 'finish' || lower == 'end') return 'Timing Point';
    if (lower.contains('aid') || lower.startsWith('as')) return 'Aid Station';
    if (lower.startsWith('km') || RegExp(r'^\d').hasMatch(lower)) return 'KM Marker';
    return 'Timing Point';
  }

  @override
  Widget build(BuildContext context) {
    final name   = checkpoint['name']?.toString() ?? 'Checkpoint';
    final radius = checkpoint['radius_meters']?.toString() ?? '—';
    final order  = checkpoint['order_number']?.toString() ?? '${index + 1}';
    final type   = _type(name);
    final isS    = name.toLowerCase() == 'start';
    final isE    = name.toLowerCase() == 'finish' || name.toLowerCase() == 'end';
    final color  = isS ? _kGreen : isE ? _kRed : _kBlue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        const Color(0xFF0D0D18),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Text(
                isS ? 'S' : isE ? 'E' : order,
                style: const TextStyle(
                    color: Colors.black, fontSize: 11,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: _kTextPri, fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(type,
                    style: const TextStyle(
                        color: _kTextMuted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(6),
              border:       Border.all(color: _kBorder),
            ),
            child: Text('$radius m',
                style: const TextStyle(
                    color: _kTextSub, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// Minimal staff row for use inside this screen
class _SetupStaffRow extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback          onTap;
  const _SetupStaffRow({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name     = account['name']?.toString() ?? 'Unknown';
    final role     = account['role']?.toString() ?? '';
    final isActive = account['is_active'] as bool? ?? true;
    final initials = name.trim().split(' ') is List
        ? () {
            final parts = name.trim().split(' ');
            return parts.length >= 2
                ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                : name.isNotEmpty
                    ? name[0].toUpperCase()
                    : '?';
          }()
        : '?';
    final roleLabel = role == 'kit_staff' ? 'Kit Staff' : role == 'checkin_staff' ? 'Check-in' : 'Staff';
    final roleColor = role == 'kit_staff' ? _kBlue : role == 'checkin_staff' ? _kAmber : _kTextSub;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:        const Color(0xFF0D0D18),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: _kGreen.withOpacity(0.2))),
                child: Center(
                  child: Text(initials,
                      style: const TextStyle(
                          color: _kGreen, fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        color:      isActive ? _kTextPri : _kTextMuted,
                        fontSize:   13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color:        roleColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                  border:       Border.all(color: roleColor.withOpacity(0.35)),
                ),
                child: Text(roleLabel,
                    style: TextStyle(
                        color:      roleColor,
                        fontSize:   10,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                    color:  isActive ? _kGreen : _kTextMuted,
                    shape:  BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SettingsLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: _kTextPri, fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(color: _kTextSub, fontSize: 12)),
      ],
    );
  }
}

class _SensitivityChip extends StatelessWidget {
  final String   label;
  final bool     selected;
  final Color    color;
  final VoidCallback onTap;
  const _SensitivityChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color:        selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
              color: selected ? color : _kBorder, width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      selected ? color : _kTextSub,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize:   13,
          ),
        ),
      ),
    );
  }
}

class _TimePickerField extends StatelessWidget {
  final String   label;
  final TimeOfDay? time;
  final VoidCallback onTap;
  const _TimePickerField({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = time != null
        ? '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'
        : 'Not set';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time_rounded,
                color: _kTextMuted, size: 16),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: _kTextMuted, fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                Text(display,
                    style: TextStyle(
                        color:      time != null ? _kTextPri : _kTextMuted,
                        fontSize:   13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── CSV export dialog (reused in this screen + post_race_screen) ───────────────

class _CsvExportDialog extends StatelessWidget {
  final String csv;
  final String filename;
  const _CsvExportDialog({required this.csv, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D0D18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF1E1E32)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Export CSV',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF8888AA)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: const Color(0xFF1E1E32)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      csv,
                      style: const TextStyle(
                          color:    Color(0xFF00FF9C),
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: csv));
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('CSV copied to clipboard'),
                    backgroundColor: Color(0xFF00FF9C),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                icon:  const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy to Clipboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF9C),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Staff dialogs (inline versions for this screen) ────────────────────────────

class _SetupCreateStaffDialog extends StatefulWidget {
  final int raceId;
  final void Function(String name, String tempPassword) onCreated;
  const _SetupCreateStaffDialog({required this.raceId, required this.onCreated});

  @override
  State<_SetupCreateStaffDialog> createState() =>
      _SetupCreateStaffDialogState();
}

class _SetupCreateStaffDialogState extends State<_SetupCreateStaffDialog> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  String  _role   = 'checkin_staff';
  bool    _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _genPw() {
    const c = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#';
    final r = Random.secure();
    return List.generate(12, (_) => c[r.nextInt(c.length)]).join();
  }

  Future<void> _save() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Full name is required.'); return; }
    if (!email.contains('@')) { setState(() => _error = 'Valid email required.'); return; }

    setState(() { _saving = true; _error = null; });
    try {
      final result = await ApiService.createStaffAccount(
        widget.raceId,
        name:  name,
        email: email,
        role:  _role,
      );
      final pw = result['temp_password']?.toString() ?? '';
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated(name, pw);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create Staff Account',
                  style: TextStyle(
                      color: _kTextPri, fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _field(_nameCtrl, 'Full name', Icons.person_outline_rounded,
                  TextInputType.text),
              const SizedBox(height: 12),
              _field(_emailCtrl, 'Email address', Icons.email_outlined,
                  TextInputType.emailAddress),
              const SizedBox(height: 12),
              // Role selector
              ...['checkin_staff', 'kit_staff'].map((r) => RadioListTile<String>(
                value:    r,
                groupValue: _role,
                onChanged: (v) => setState(() => _role = v!),
                title: Text(
                  r == 'checkin_staff' ? 'Check-in Staff' : 'Kit Distribution Staff',
                  style: const TextStyle(color: _kTextPri, fontSize: 13),
                ),
                activeColor: _kGreen,
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: _kRed, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTextSub,
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Text('Create Account',
                              style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      TextInputType type) {
    return TextField(
      controller:   ctrl,
      keyboardType: type,
      style:        const TextStyle(color: _kTextPri, fontSize: 13),
      decoration:   InputDecoration(
        hintText:   hint,
        hintStyle:  const TextStyle(color: _kTextMuted),
        prefixIcon: Icon(icon, color: _kTextSub, size: 16),
        filled:     true,
        fillColor:  Colors.white.withOpacity(0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:   BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:   BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide:   BorderSide(color: _kGreen, width: 1.5),
        ),
      ),
    );
  }
}

class _SetupTempPasswordDialog extends StatefulWidget {
  final String name;
  final String tempPassword;
  const _SetupTempPasswordDialog(
      {required this.name, required this.tempPassword});

  @override
  State<_SetupTempPasswordDialog> createState() =>
      _SetupTempPasswordDialogState();
}

class _SetupTempPasswordDialogState extends State<_SetupTempPasswordDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: _kGreen.withOpacity(0.3))),
                child: const Icon(Icons.check_rounded,
                    color: _kGreen, size: 22),
              ),
              const SizedBox(height: 14),
              Text('${widget.name} created',
                  style: const TextStyle(
                      color: _kTextPri, fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Share this password securely.\nIt will not be shown again.',
                style: TextStyle(color: _kTextSub, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: _kGreen.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        widget.tempPassword,
                        style: const TextStyle(
                            color:    _kGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(
                            ClipboardData(text: widget.tempPassword));
                        if (!mounted) return;
                        setState(() => _copied = true);
                        await Future.delayed(const Duration(seconds: 2));
                        if (mounted) setState(() => _copied = false);
                      },
                      child: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        color: _copied ? _kGreen : _kTextSub,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupStaffOptionsDialog extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback?        onDeactivate;
  const _SetupStaffOptionsDialog(
      {required this.account, this.onDeactivate});

  @override
  Widget build(BuildContext context) {
    final name     = account['name']?.toString() ?? 'Unknown';
    final isActive = account['is_active'] as bool? ?? true;

    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: _kTextPri, fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(isActive ? 'Active' : 'Deactivated',
                  style: TextStyle(
                      color: isActive ? _kGreen : _kTextMuted,
                      fontSize: 12)),
              const SizedBox(height: 18),
              if (onDeactivate != null) ...[
                GestureDetector(
                  onTap: onDeactivate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:        _kRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(color: _kRed.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.block_rounded, color: _kRed, size: 15),
                        SizedBox(width: 8),
                        Text('Deactivate Account',
                            style: TextStyle(
                                color:      _kRed,
                                fontSize:   13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTextSub,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
