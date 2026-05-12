import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/utils/date_utils.dart';
import 'package:andotrack_app/roles/race_director/screens/post_race_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF080810);
const _kSurface   = Color(0xFF0D0D18);
const _kBorder    = Color(0xFF1E1E32);
const _kGreen     = Color(0xFF00FF9C);
const _kBlue      = Color(0xFF00B4FF);
const _kAmber     = Color(0xFFFFB800);
const _kRed       = Color(0xFFFF4D4D);
const _kTextPri   = Colors.white;
const _kTextSub   = Color(0xFF8888AA);
const _kTextMuted = Color(0xFF3A3A55);

const _kTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

// ── Philippine time helper ────────────────────────────────────────────────────
// Available for any future clock-time display added to this screen.
// Do NOT apply to _raceStartedAt: that value feeds a Duration calculation, not
// a displayed timestamp, so PHT conversion belongs at the display layer only.
DateTime _toPhilippineTime(DateTime utc) =>
    utc.add(const Duration(hours: 8));

// ─────────────────────────────────────────────────────────────────────────────

class LiveRaceDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const LiveRaceDashboardScreen({super.key, required this.race});

  @override
  State<LiveRaceDashboardScreen> createState() =>
      _LiveRaceDashboardScreenState();
}

class _LiveRaceDashboardScreenState extends State<LiveRaceDashboardScreen> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _runners     = [];
  List<Map<String, dynamic>> _checkpoints = [];
  List<Map<String, dynamic>> _anomalies   = [];

  // ── UI state ──────────────────────────────────────────────────────────────
  bool    _bottomExpanded = true;
  bool    _stoppingRace   = false;
  bool    _mapCentered    = false;
  String? _pollError;

  // ── Map ───────────────────────────────────────────────────────────────────
  final _mapCtrl = MapController();

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer?   _clockTimer;
  Timer?   _pollTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _raceStartedAt;  // ← Store parsed start time to preserve across screen re-entries

  int get _raceId => (widget.race['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _initElapsed();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) { if (mounted) setState(() => _elapsed += const Duration(seconds: 1)); },
    );
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollAll(),
    );
    _pollAll();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _initElapsed() {
    // If we already have a stored start time from a previous init, use it
    if (_raceStartedAt != null) {
      final d = DateTime.now().difference(_raceStartedAt!);
      _elapsed = d.isNegative ? Duration.zero : d;
      return;
    }

    // Try to get started_at from widget.race first
    final raw = widget.race['started_at']?.toString();
    if (raw != null) {
      try {
        _raceStartedAt = parsePht(raw);
        final d = DateTime.now().difference(_raceStartedAt!);
        _elapsed = d.isNegative ? Duration.zero : d;
        return;
      } catch (_) {}
    }

    // If started_at is missing or parse failed, fetch fresh race data from backend
    _fetchRaceStartTime();
  }

  Future<void> _fetchRaceStartTime() async {
    try {
      final race = await ApiService.getRace(_raceId);
      final raw = race['started_at']?.toString();
      if (raw != null) {
        _raceStartedAt = parsePht(raw);
        final d = DateTime.now().difference(_raceStartedAt!);
        if (mounted) {
          setState(() => _elapsed = d.isNegative ? Duration.zero : d);
        }
      }
    } catch (e) {
      debugPrint('[LiveRace] Failed to fetch race start time: $e');
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  Future<void> _pollAll() async {
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        ApiService.getRaceRunners(_raceId),
        ApiService.getCheckpoints(_raceId),
        ApiService.getAnomalies(_raceId),
      ]);
      if (!mounted) return;
      setState(() {
        _runners     = results[0];
        _checkpoints = results[1];
        // Filter unresolved client-side; backend may not filter
        _anomalies   = results[2]
            .where((a) => a['resolved'] != true)
            .toList();
        _pollError = null;
      });
      // Move map to course centroid on first successful checkpoint load.
      // Guard with _mapCentered so subsequent polls don't fight user panning.
      if (!_mapCentered && _checkpoints.isNotEmpty) {
        _mapCentered = true;
        _mapCtrl.move(_mapCenter, 13);
      }
    } catch (e) {
      if (mounted) setState(() => _pollError = e.toString());
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _elapsedStr {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  int get _racingCount =>
      _runners.where((r) => r['is_present'] == true).length;
  int get _dnsCount    =>
      _runners.where((r) => r['race_status']?.toString() == 'dns').length;

  // Only checked-in runners (is_present == true) are shown in the bottom panel.
  List<Map<String, dynamic>> get _checkedInRunners =>
      _runners.where((r) => r['is_present'] == true).toList();

  // Compute map center from checkpoint coordinates (field: lat, lng)
  LatLng get _mapCenter {
    final pts = _checkpoints
        .where((c) => c['lat'] != null && c['lng'] != null)
        .map((c) => LatLng(
              (c['lat'] as num).toDouble(),
              (c['lng'] as num).toDouble(),
            ))
        .toList();
    if (pts.isEmpty) return const LatLng(14.5995, 120.9842); // PH default
    return LatLng(
      pts.fold(0.0, (s, p) => s + p.latitude)  / pts.length,
      pts.fold(0.0, (s, p) => s + p.longitude) / pts.length,
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _confirmStopRace() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _kRed.withOpacity(0.3)),
        ),
        title: const Text(
          'Stop Race?',
          style: TextStyle(color: _kTextPri, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will end the race and lock results.',
              style: TextStyle(color: _kTextSub, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(color: _kRed.withOpacity(0.85), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _kTextSub)),
          ),
          ElevatedButton(
            onPressed: _doStopRace,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Stop Race',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _doStopRace() async {
    Navigator.pop(context);
    setState(() => _stoppingRace = true);
    try {
      await ApiService.stopRace(_raceId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => PostRaceScreen(race: widget.race)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _stoppingRace = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to stop race: $e'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _resolveAnomaly(int anomalyId) async {
    try { await ApiService.resolveAnomaly(_raceId, anomalyId); } catch (_) {}
    _pollAll();
  }

  void _showRunnerDetail(Map<String, dynamic> runner) {
    showDialog(
      context: context,
      builder: (_) => _RunnerDetailDialog(runner: runner),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AnomalySidebar(
                  anomalies: _anomalies,
                  onResolve: _resolveAnomaly,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildMap()),
                      Positioned(
                        left: 0, right: 0, bottom: 0,
                        child: _buildRunnerPanel(),
                      ),
                      if (_pollError != null)
                        Positioned(
                          top: 12, right: 12,
                          child: _PollErrorChip(message: _pollError!),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color:  _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Back to shell
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: _kTextSub, size: 18),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          // Live dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color:  _kGreen,
              shape:  BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _kGreen.withOpacity(0.6), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.race['name']?.toString() ?? 'Live Race',
              style: const TextStyle(
                color:      _kTextPri,
                fontSize:   15,
                fontWeight: FontWeight.w700,
                overflow:   TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Elapsed timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color:        _kGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: _kGreen.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 13, color: _kGreen),
                const SizedBox(width: 6),
                Text(
                  _elapsedStr,
                  style: const TextStyle(
                    color:       _kGreen,
                    fontSize:    13,
                    fontWeight:  FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Runner count badge
          if (_runners.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: _kBorder),
              ),
              child: Text(
                '$_racingCount racing  ·  $_dnsCount DNS',
                style: const TextStyle(color: _kTextSub, fontSize: 12),
              ),
            ),
          // Stop Race button
          _stoppingRace
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kRed))
              : ElevatedButton.icon(
                  onPressed:  _confirmStopRace,
                  icon:  const Icon(Icons.stop_rounded, size: 15),
                  label: const Text('Stop Race'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed.withOpacity(0.12),
                    foregroundColor: _kRed,
                    elevation:       0,
                    side:  BorderSide(color: _kRed.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
        ],
      ),
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────
  // Field names: checkpoints use lat/lng/order_number (confirmed from CheckpointService)

  Widget _buildMap() {
    final cpWithCoords = _checkpoints
        .where((c) => c['lat'] != null && c['lng'] != null)
        .toList()
      ..sort((a, b) =>
          (a['order_number'] as int? ?? 0)
              .compareTo(b['order_number'] as int? ?? 0));

    final cpCircles = cpWithCoords.map((c) => CircleMarker(
          point: LatLng(
            (c['lat'] as num).toDouble(),
            (c['lng'] as num).toDouble(),
          ),
          radius:            (c['radius_meters'] as num?)?.toDouble() ?? 20.0,
          color:             _kBlue.withOpacity(0.1),
          borderColor:       _kBlue.withOpacity(0.7),
          borderStrokeWidth: 2,
          useRadiusInMeter:  true,
        )).toList();

    // Runner GPS dots — location fields not yet included in GET /races/{race_id}/runners
    // This will populate once backend updates runner response to include last_lat/last_lng
    final runnerCircles = _runners
        .where((r) => (r['last_lat'] ?? r['latitude']) != null && (r['last_lng'] ?? r['longitude']) != null)
        .map((r) {
      final lat = (r['last_lat'] ?? r['latitude']) as num?;
      final lng = (r['last_lng'] ?? r['longitude']) as num?;
      if (lat == null || lng == null) return null;
      
      final status = r['race_status']?.toString() ?? r['status']?.toString() ?? 'racing';
      Color color;
      switch (status) {
        case 'finished': color = _kGreen; break;
        case 'dns':      color = _kTextMuted; break;
        default:         color = _kAmber;
      }
      return CircleMarker(
        point: LatLng(
          lat.toDouble(),
          lng.toDouble(),
        ),
        radius:            5,
        color:             color.withOpacity(0.9),
        borderColor:       Colors.white.withOpacity(0.5),
        borderStrokeWidth: 1,
      );
    }).whereType<CircleMarker>().toList();

    // Checkpoint number markers
    final cpMarkers = List.generate(cpWithCoords.length, (i) {
      final c     = cpWithCoords[i];
      final name  = (c['name'] as String?)?.toLowerCase() ?? '';
      final isS   = name == 'start';
      final isE   = name == 'finish' || name == 'end';
      final color = isS ? _kGreen : isE ? _kRed : _kBlue;
      final order = c['order_number'] as int? ?? (i + 1);
      final label = isS ? 'S' : isE ? 'E' : '$order';
      return Marker(
        point:  LatLng(
          (c['lat'] as num).toDouble(),
          (c['lng'] as num).toDouble(),
        ),
        width:  26, height: 26,
        child:  Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:  color,
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 6),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color:      Colors.black,
              fontSize:   9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    });

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom:   13,
      ),
      children: [
        TileLayer(
          urlTemplate: _kTileUrl,
        ),
        if (cpCircles.isNotEmpty)
          CircleLayer(circles: cpCircles),
        if (runnerCircles.isNotEmpty)
          CircleLayer(circles: runnerCircles),
        if (cpMarkers.isNotEmpty)
          MarkerLayer(markers: cpMarkers),
      ],
    );
  }

  // ── Runner bottom panel ────────────────────────────────────────────────────

  Widget _buildRunnerPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve:    Curves.easeInOut,
      height:   _bottomExpanded ? 210 : 40,
      decoration: BoxDecoration(
        color:        _kSurface.withOpacity(0.95),
        border: const Border(top: BorderSide(color: _kBorder)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          // Toggle handle
          GestureDetector(
            onTap:    () => setState(() => _bottomExpanded = !_bottomExpanded),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height:  40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 14, color: _kTextSub),
                  const SizedBox(width: 8),
                  Text(
                    'Checked In  (${_checkedInRunners.length})',
                    style: const TextStyle(
                      color:      _kTextSub,
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _bottomExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size:  18, color: _kTextMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_bottomExpanded)
            Expanded(
              child: _runners.isEmpty
                  ? const Center(
                      child: Text('No runner data yet',
                          style: TextStyle(
                              color: _kTextMuted, fontSize: 12)))
                  : _checkedInRunners.isEmpty
                      ? const Center(
                          child: Text('No checked-in runners yet',
                              style: TextStyle(
                                  color: _kTextMuted, fontSize: 12)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          scrollDirection: Axis.horizontal,
                          itemCount:       _checkedInRunners.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => _RunnerCard(
                            runner: _checkedInRunners[i],
                            onTap:  () => _showRunnerDetail(_checkedInRunners[i]),
                          ),
                        ),
            ),
        ],
      ),
    );
  }
}

// ── Anomaly sidebar ───────────────────────────────────────────────────────────

class _AnomalySidebar extends StatelessWidget {
  final List<Map<String, dynamic>>   anomalies;
  final void Function(int anomalyId) onResolve;

  const _AnomalySidebar({required this.anomalies, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color:  _kSurface,
        border: Border(right: BorderSide(color: _kBorder)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: _kAmber),
                const SizedBox(width: 8),
                const Text(
                  'Anomaly Feed',
                  style: TextStyle(
                    color:      _kTextPri,
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (anomalies.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:        _kRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kRed.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${anomalies.length}',
                      style: const TextStyle(
                        color:      _kRed,
                        fontSize:   10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: _kBorder, height: 1),
          Expanded(
            child: anomalies.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: _kGreen, size: 28),
                        SizedBox(height: 10),
                        Text('No active anomalies',
                            style: TextStyle(
                                color: _kTextSub, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: anomalies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AnomalyCard(
                      anomaly:   anomalies[i],
                      onResolve: () =>
                          onResolve(anomalies[i]['id'] as int),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Anomaly card ──────────────────────────────────────────────────────────────
// Anomaly model fields: reason (not description), detected_at, runner_id

class _AnomalyCard extends StatelessWidget {
  final Map<String, dynamic> anomaly;
  final VoidCallback          onResolve;

  const _AnomalyCard({required this.anomaly, required this.onResolve});

  static String _typeLabel(String type) {
    switch (type) {
      case 'vehicle_speed': return 'VEHICLE SPEED';
      case 'gps_jump':      return 'GPS JUMP';
      case 'off_route':     return 'OFF ROUTE';
      case 'erratic':       return 'ERRATIC MOVEMENT';
      default:              return type.toUpperCase().replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 'reason' is the backend field (not 'description')
    final type   = anomaly['reason']?.toString() ?? anomaly['type']?.toString() ?? 'anomaly';
    final detail = anomaly['detail']?.toString()
        ?? anomaly['description']?.toString()
        ?? 'Anomaly detected';

    Color    color;
    IconData icon;
    switch (type) {
      case 'vehicle_speed':
        color = _kRed;   icon = Icons.speed_rounded;         break;
      case 'gps_jump':
        color = _kAmber; icon = Icons.gps_off_rounded;        break;
      case 'off_route':
        color = _kAmber; icon = Icons.route_rounded;          break;
      case 'erratic':
        color = _kRed;   icon = Icons.warning_rounded;        break;
      default:
        color = _kAmber; icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _typeLabel(type),
                  style: TextStyle(
                    color:         color,
                    fontSize:      10,
                    fontWeight:    FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(color: _kTextSub, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width:  double.infinity,
            height: 28,
            child: TextButton(
              onPressed: onResolve,
              style: TextButton.styleFrom(
                foregroundColor: _kGreen,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: _kGreen.withOpacity(0.2)),
                ),
              ),
              child: const Text('Resolve',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Runner card ───────────────────────────────────────────────────────────────

class _RunnerCard extends StatelessWidget {
  final Map<String, dynamic> runner;
  final VoidCallback          onTap;

  const _RunnerCard({required this.runner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bib         = runner['bib_number']?.toString() ?? '—';
    final name        = runner['name']?.toString() ?? 'Unknown';
    final status      = runner['race_status']?.toString()
        ?? runner['status']?.toString()
        ?? 'registered';
    final speed       = runner['current_speed_kmh'];
    final distCovered = runner['distance_covered_km'];

    Color statusColor;
    switch (status) {
      case 'finished':   statusColor = _kGreen;     break;
      case 'dns':        statusColor = _kTextMuted;  break;
      case 'dnf':        statusColor = _kRed;        break;
      case 'active':
      case 'racing':     statusColor = _kAmber;      break;
      default:           statusColor = _kBlue;       // registered
    }

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width:   155,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        _kBg,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color:        _kBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('#$bib',
                        style: const TextStyle(
                          color:      _kBlue,
                          fontSize:   10,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                  const Spacer(),
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: const TextStyle(
                  color:      _kTextPri,
                  fontSize:   11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              if (distCovered != null)
                Text(
                  '${(distCovered as num).toStringAsFixed(1)} km',
                  style: const TextStyle(color: _kTextSub, fontSize: 10),
                ),
              if (speed != null)
                Text(
                  '${(speed as num).toStringAsFixed(1)} km/h',
                  style: const TextStyle(color: _kTextMuted, fontSize: 10),
                ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:        statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: statusColor.withOpacity(0.25)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color:         statusColor,
                    fontSize:      9,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Runner detail dialog ──────────────────────────────────────────────────────

class _RunnerDetailDialog extends StatelessWidget {
  final Map<String, dynamic> runner;
  const _RunnerDetailDialog({required this.runner});

  @override
  Widget build(BuildContext context) {
    final bib         = runner['bib_number']?.toString() ?? '—';
    final name        = runner['name']?.toString() ?? 'Unknown';
    final status      = runner['race_status']?.toString()
        ?? runner['status']?.toString()
        ?? 'registered';
    final speed       = runner['current_speed_kmh'];
    final distCovered = runner['distance_covered_km'];
    final cpPassed    = runner['checkpoints_passed'] as int?;
    final city        = runner['city']?.toString();
    final contact     = runner['contact_number']?.toString();
    final emergency   = runner['emergency_contact']?.toString();
    final shirtSize   = runner['shirt_size']?.toString();

    return AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      contentPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        _kBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('#$bib',
                      style: const TextStyle(
                        color:      _kBlue,
                        fontSize:   13,
                        fontWeight: FontWeight.w800,
                      )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color:      _kTextPri,
                      fontSize:   15,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: _kTextSub),
                  onPressed: () => Navigator.pop(context),
                  padding:     EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _row('Status',      status.toUpperCase()),
            if (distCovered != null)
              _row('Distance',
                  '${(distCovered as num).toStringAsFixed(2)} km'),
            if (speed != null)
              _row('Speed',
                  '${(speed as num).toStringAsFixed(1)} km/h'),
            if (cpPassed != null)
              _row('Checkpoints', '$cpPassed passed'),
            if (shirtSize != null)  _row('Shirt',     shirtSize),
            if (city != null)       _row('City',      city),
            if (contact != null)    _row('Contact',   contact),
            if (emergency != null)  _row('Emergency', emergency),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(color: _kTextSub, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                color:      _kTextPri,
                fontSize:   12,
                fontWeight: FontWeight.w600,
              )),
        ),
      ],
    ),
  );
}

// ── Poll error chip ───────────────────────────────────────────────────────────

class _PollErrorChip extends StatelessWidget {
  final String message;
  const _PollErrorChip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        _kRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: _kRed.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 12, color: _kRed),
          SizedBox(width: 6),
          Text('Poll failed — retrying',
              style: TextStyle(color: _kRed, fontSize: 11)),
        ],
      ),
    );
  }
}
