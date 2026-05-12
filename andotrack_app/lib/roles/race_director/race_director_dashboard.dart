import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/services/routing_service.dart';
import 'package:andotrack_app/features/checkin/screens/organizer_qr_scanner_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/checkpoint_placement_screen.dart';
import 'package:andotrack_app/features/leaderboard/screens/leaderboard_screen.dart';
import 'package:andotrack_app/features/race/screens/races_screen.dart';
import 'package:andotrack_app/features/runner/screens/settings_screen.dart';
import 'package:andotrack_app/shared/widgets/app_bottom_nav.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _bg          = Color(0xFF080810);
const _surface     = Color(0xFF0E0E1A);
const _surfaceHigh = Color(0xFF161625);
const _border      = Color(0xFF1E1E32);
const _green       = Color(0xFF00FF9C);
const _blue        = Color(0xFF00B4FF);
const _amber       = Color(0xFFFFB800);
const _red         = Color(0xFFFF4D4D);
const _purple      = Color(0xFF8B5CF6);
const _textPri     = Colors.white;
const _textSub     = Color(0xFF8888AA);
const _textMuted   = Color(0xFF3A3A55);

const _runnerColors = [
  _green, _blue, _amber, Color(0xFFFF4D9D),
  Color(0xFFB44DFF), Color(0xFFFF6B35),
  Color(0xFF4DFFEA), _red,
  Color(0xFFFFFF4D), Color(0xFF4DFF4D),
];

Color _runnerColor(String id) =>
    _runnerColors[id.hashCode.abs() % _runnerColors.length];

// ── Main widget ───────────────────────────────────────────────────────────────

class OrganizerDashboard extends StatefulWidget {
  const OrganizerDashboard({super.key});

  @override
  State<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends State<OrganizerDashboard>
    with TickerProviderStateMixin {

  // Navigation
  NavTab _tab = NavTab.races; // Always start on races — organizer picks a race first

  // Map
  final MapController _mapController = MapController();

  // Race state
  int?    _raceId;
  String? _raceName;
  String  _raceStatus = 'upcoming';
  double? _raceDistKm;
  bool    _actionLoading = false;

  // Firebase live runners
  final Map<String, _RunnerState> _runners        = {};
  final Map<String, LatLng>       _smoothPositions = {};
  StreamSubscription?             _firebaseSub;
  Timer?                          _smoothTimer;

  // Leaderboard (distance + pace per runner, polled every 5 s)
  List<Map<String, dynamic>> _leaderboard = [];
  Timer?                     _lbTimer;

  // Kit claiming panel
  bool                       _showKitPanel = false;
  List<Map<String, dynamic>> _kitRunners   = [];
  bool                       _kitLoading   = false;

  // Race elapsed timer
  Duration  _elapsed   = Duration.zero;
  DateTime? _raceStart;
  Timer?    _elapsedTimer;

  // Checkpoints + route
  List<Map<String, dynamic>> _checkpoints   = [];
  List<LatLng>               _routePolyline = [];

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _firebaseSub?.cancel();
    _smoothTimer?.cancel();
    _lbTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  // ── Session restore ───────────────────────────────────────

  Future<void> _restoreSession() async {
    final prefs   = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('active_race_id');
    if (savedId == null) { _startSmoothMovement(); return; }

    try {
      final races = await ApiService.getRaces();
      final race  = races
          .cast<Map<String, dynamic>>()
          .where((r) => r['id'] == savedId)
          .firstOrNull;
      if (race != null && mounted) {
        _applyRace(race);
        _afterRaceSelected();
      }
    } catch (_) { _startSmoothMovement(); }
  }

  void _applyRace(Map<String, dynamic> r) => setState(() {
    _raceId     = r['id'] as int;
    _raceName   = r['name']?.toString();
    _raceStatus = r['status']?.toString() ?? 'upcoming';
    _raceDistKm = (r['distance_km'] as num?)?.toDouble();
  });

  // ── Switch race (from Races tab card tap) ─────────────────

  Future<void> _switchRace(int id, String name, String status) async {
    if (id == _raceId) { setState(() => _tab = NavTab.map); return; }

    _firebaseSub?.cancel();
    _lbTimer?.cancel();
    _elapsedTimer?.cancel();

    setState(() {
      _raceId      = id;
      _raceName    = name;
      _raceStatus  = status;
      _raceDistKm  = null;
      _runners.clear();
      _smoothPositions.clear();
      _checkpoints   = [];
      _routePolyline = [];
      _leaderboard   = [];
      _elapsed       = Duration.zero;
      _raceStart     = null;
      _tab           = NavTab.map; // Jump straight to map after picking
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_race_id', id);

    // Fetch full detail for distance_km
    try {
      final detail = await ApiService.getRace(id);
      if (mounted) setState(
          () => _raceDistKm = (detail['distance_km'] as num?)?.toDouble());
    } catch (_) {}

    _afterRaceSelected();
  }

  void _afterRaceSelected() {
    _listenToRunners();
    _startSmoothMovement();
    _loadCheckpoints();
    _startLbPolling();
    if (_raceStatus == 'active') _startElapsedTimer();
  }

  // ── Leaderboard polling ───────────────────────────────────

  void _startLbPolling() {
    _lbTimer?.cancel();
    _fetchLb();
    _lbTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchLb());
  }

  Future<void> _fetchLb() async {
    if (_raceId == null) return;
    try {
      final data = await ApiService.getLeaderboard(_raceId!);
      if (mounted) setState(() => _leaderboard = data);
    } catch (_) {}
  }

  // ── Elapsed timer ─────────────────────────────────────────

  void _startElapsedTimer() {
    _raceStart ??= DateTime.now();
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_raceStart!));
    });
  }

  // ── Checkpoints ───────────────────────────────────────────

  Future<void> _loadCheckpoints() async {
    if (_raceId == null) return;
    try {
      final data   = await ApiService.getCheckpoints(_raceId!);
      if (!mounted) return;
      final sorted = data
        ..sort((a, b) => (a['order_number'] as num)
            .compareTo(b['order_number'] as num));
      setState(() => _checkpoints = sorted);
      _buildRoute();
    } catch (_) {}
  }

  Future<void> _buildRoute() async {
    if (_checkpoints.length < 2) { setState(() => _routePolyline = []); return; }
    final pts = _checkpoints
        .map((cp) => LatLng((cp['lat'] as num).toDouble(),
                            (cp['lng'] as num).toDouble()))
        .toList();
    try {
      final route = await RoutingService.getRoutePolyline(pts);
      if (mounted) setState(() => _routePolyline = route);
    } catch (_) {}
  }

  // ── Firebase ──────────────────────────────────────────────

  void _listenToRunners() {
    if (_raceId == null) return;
    final lid = _raceId!;
    _firebaseSub = FirebaseDatabase.instance
        .ref('races/$lid/runners')
        .onValue
        .listen((ev) {
      if (lid != _raceId || !mounted) return;
      if (ev.snapshot.value == null) { setState(() => _runners.clear()); return; }
      final raw = Map<String, dynamic>.from(ev.snapshot.value as Map);
      setState(() {
        raw.forEach((id, val) {
          final d = Map<String, dynamic>.from(val as Map);
          final prev = _runners[id];
          final pos  = LatLng(
            (d['lat']   as num?)?.toDouble() ?? 0,
            (d['lng']   as num?)?.toDouble() ?? 0,
          );
          _runners[id] = _RunnerState(
            id:           id,
            position:     pos,
            prevPosition: prev?.position,
            speed:        (d['speed'] as num?)?.toDouble() ?? 0,
            lastSeen:     DateTime.now(),
          );
          _smoothPositions[id] ??= pos;
        });
        _runners.removeWhere((id, _) => !raw.containsKey(id));
        _smoothPositions.removeWhere((id, _) => !raw.containsKey(id));
      });
    });
  }

  void _startSmoothMovement() {
    _smoothTimer?.cancel();
    _smoothTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      bool changed = false;
      _runners.forEach((id, r) {
        final cur = _smoothPositions[id];
        if (cur == null) return;
        const t = 0.15;
        final nLat = cur.latitude  + (r.position.latitude  - cur.latitude)  * t;
        final nLng = cur.longitude + (r.position.longitude - cur.longitude) * t;
        if ((nLat - cur.latitude).abs() > 0.000001 ||
            (nLng - cur.longitude).abs() > 0.000001) {
          _smoothPositions[id] = LatLng(nLat, nLng);
          changed = true;
        }
      });
      if (changed && mounted) setState(() {});
    });
  }

  // ── Race lifecycle ────────────────────────────────────────

  Future<void> _handleRaceAction() async {
    if (_raceId == null) return;
    final isActive = _raceStatus == 'active';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(
        title:        isActive ? 'Stop the Race?' : 'Start the Race?',
        body:         isActive
            ? 'This ends the race and freezes the leaderboard. Cannot be undone.'
            : 'All runners will begin GPS tracking. Make sure everyone is ready.',
        confirmLabel: isActive ? 'Stop Race'  : 'Start Race',
        confirmColor: isActive ? _red         : _green,
        icon:         isActive
            ? Icons.stop_circle_outlined
            : Icons.play_circle_outline_rounded,
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      if (isActive) {
        await ApiService.stopRace(_raceId!);
        setState(() => _raceStatus = 'finished');
        _elapsedTimer?.cancel();
      } else {
        await ApiService.startRace(_raceId!);
        setState(() => _raceStatus = 'active');
        _startElapsedTimer();
      }
    } catch (e) {
      if (mounted) _toast('Action failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _recenterMap() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
    } catch (_) {}
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.w700)),
      backgroundColor: error ? _red : _green,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── Status helpers ────────────────────────────────────────

  Color  get _statusColor  => _statusColorFor(_raceStatus);
  String get _statusLabel  => _statusLabelFor(_raceStatus);

  static Color _statusColorFor(String s) {
    switch (s) {
      case 'active':            return _green;
      case 'finished':          return _textSub;
      case 'registration_open': return _blue;
      case 'race_day':          return _amber;
      default:                  return _purple;
    }
  }

  static String _statusLabelFor(String s) {
    switch (s) {
      case 'registration_open': return 'REG OPEN';
      case 'race_day':          return 'RACE DAY';
      default:                  return s.toUpperCase();
    }
  }

  static String _fmtElapsed(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness:     Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body:            _buildBody(),
        bottomNavigationBar: AppBottomNav(
          current: _tab,
          onTap: (t) {
            if ((t == NavTab.map || t == NavTab.leaderboard) &&
                _raceId == null) {
              _toast('Select a race from the Races tab first');
              setState(() => _tab = NavTab.races);
              return;
            }
            setState(() => _tab = t);
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case NavTab.map:
        return _raceId == null ? _noRaceState() : _mapView();
      case NavTab.races:
        return RacesScreen(
            onRaceSelected: (id, name, status) =>
                _switchRace(id, name, status));
      case NavTab.leaderboard:
        return _raceId == null
            ? _noRaceState()
            : LeaderboardScreen(raceId: _raceId!);
      case NavTab.settings:
        return const SettingsScreen();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // NO-RACE STATE
  // ═══════════════════════════════════════════════════════════

  Widget _noRaceState() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width:  96,
              height: 96,
              decoration: BoxDecoration(
                shape:     BoxShape.circle,
                color:     _green.withOpacity(0.07),
                border:    Border.all(
                    color: _green.withOpacity(0.2), width: 1.5),
              ),
              child: const Icon(Icons.flag_rounded,
                  color: _green, size: 40),
            ),
            const SizedBox(height: 28),
            const Text('No Race Selected',
                style: TextStyle(
                    color:      _textPri,
                    fontSize:   22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5)),
            const SizedBox(height: 10),
            const Text(
              'Go to the Races tab, pick a race,\nand it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _textSub, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _tab = NavTab.races),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon:  const Icon(Icons.list_alt_rounded, size: 20),
                label: const Text('Browse Races',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MAP VIEW — Command Center
  // ═══════════════════════════════════════════════════════════

  Widget _mapView() {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(children: [

      // ① Full-screen map
      _buildMap(),

      // ② Top gradient scrim (HUD readability)
      Positioned(
        top: 0, left: 0, right: 0,
        height: topPad + 130,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [_bg.withOpacity(0.88), _bg.withOpacity(0)],
              ),
            ),
          ),
        ),
      ),

      // ③ HUD bar
      Positioned(
        top: topPad + 10, left: 14, right: 14,
        child: _hud(),
      ),

      // ④ Side action rail (right edge)
      Positioned(
        right: 12, bottom: 230,
        child: _sideRail(),
      ),

      // ⑤ Draggable runner panel
      _runnerPanel(),
    ]);
  }

  // ── Map layers ────────────────────────────────────────────

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(10.3157, 123.8854),
        initialZoom:   15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),

        if (_routePolyline.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points:      _routePolyline,
              color:       _blue.withOpacity(0.55),
              strokeWidth: 4.5,
            ),
          ]),

        CircleLayer(
          circles: _checkpoints.map((cp) => CircleMarker(
            point: LatLng(
              (cp['lat'] as num).toDouble(),
              (cp['lng'] as num).toDouble(),
            ),
            radius:            (cp['radius_meters'] as num).toDouble(),
            color:             _blue.withOpacity(0.07),
            borderColor:       _blue.withOpacity(0.35),
            borderStrokeWidth: 1.5,
            useRadiusInMeter:  true,
          )).toList(),
        ),

        MarkerLayer(markers: [
          // Checkpoint pins
          ..._checkpoints.asMap().entries.map((e) => Marker(
            point: LatLng(
              (e.value['lat'] as num).toDouble(),
              (e.value['lng'] as num).toDouble(),
            ),
            width: 56, height: 60,
            child: _CheckpointPin(
                index: e.key + 1,
                name:  e.value['name']?.toString() ?? ''),
          )),

          // Runner dots (smoothed)
          ..._smoothPositions.entries.map((e) {
            final color = _runnerColor(e.key);
            final kmh   = ((_runners[e.key]?.speed ?? 0) * 3.6)
                .toStringAsFixed(1);
            return Marker(
              point: e.value, width: 64, height: 56,
              child: _RunnerPin(color: color, kmh: kmh),
            );
          }),
        ]),
      ],
    );
  }

  // ── HUD ───────────────────────────────────────────────────

  Widget _hud() {
    final isActive = _raceStatus == 'active';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        _surface.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: _border),
        boxShadow:    [
          BoxShadow(
              color:      Colors.black.withOpacity(0.4),
              blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Race name row
          Row(
            children: [
              _PulseDot(color: _statusColor, pulse: isActive),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _raceName ?? '',
                  style: const TextStyle(
                      color: _textPri, fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Elapsed clock when race is active
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        _green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(
                        color: _green.withOpacity(0.25)),
                  ),
                  child: Text(
                    _fmtElapsed(_elapsed),
                    style: const TextStyle(
                      color:      _green,
                      fontSize:   13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Stat row — wrapped in scroll to prevent right overflow
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Status badge
                _Badge(label: _statusLabel, color: _statusColor),
                const SizedBox(width: 8),

                if (_raceDistKm != null) ...[
                  _Badge(
                    label: '${_raceDistKm!.toStringAsFixed(0)} km',
                    color: _textSub,
                    icon:  Icons.straighten_rounded,
                  ),
                  const SizedBox(width: 8),
                ],

                // Live runners
                _Badge(
                  label: '${_runners.length} live',
                  color: _runners.isEmpty ? _textMuted : _green,
                  icon:  Icons.people_alt_rounded,
                ),
                const SizedBox(width: 8),

                // Checkpoints
                _Badge(
                  label: '${_checkpoints.length} checkpoints',
                  color: _checkpoints.isEmpty ? _textMuted : _blue,
                  icon:  Icons.place_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Side rail ─────────────────────────────────────────────

  Widget _sideRail() {
    return Column(
      children: [
        _RailBtn(
          icon:  Icons.qr_code_scanner_rounded,
          color: _green,
          tip:   'Scan QR / Check-in',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrganizerQrScannerScreen(
                  raceId:   _raceId!,
                  raceName: _raceName ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _RailBtn(
          icon:  Icons.add_location_alt_rounded,
          color: _blue,
          tip:   'Manage Checkpoints',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CheckpointPlacementScreen(
                  raceId:         _raceId!,
                  raceDistanceKm: _raceDistKm, // ← passes race km
                ),
              ),
            );
            _loadCheckpoints();
          },
        ),
        const SizedBox(height: 10),
        _RailBtn(
          icon:  Icons.my_location_rounded,
          color: _amber,
          tip:   'Re-center map',
          onTap: _recenterMap,
        ),
      ],
    );
  }

  // ── Kit claiming ──────────────────────────────────────────

  Future<void> _loadKitRunners() async {
    if (_raceId == null) return;
    setState(() => _kitLoading = true);
    try {
      final data = await ApiService.getKitRunners(_raceId!);
      if (mounted) setState(() { _kitRunners = data; _kitLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _kitLoading = false);
    }
  }

  Future<void> _claimKit(int runnerId) async {
    if (_raceId == null) return;
    try {
      await ApiService.claimKit(_raceId!, runnerId);
      setState(() {
        final idx = _kitRunners.indexWhere((r) => r['runner_id'] == runnerId);
        if (idx != -1) _kitRunners[idx] = {..._kitRunners[idx], 'claimed': true};
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: _red),
        );
      }
    }
  }

  // ── Draggable runner panel ────────────────────────────────

  Widget _runnerPanel() {
    final isActive   = _raceStatus == 'active';
    final isFinished = _raceStatus == 'finished';
    final canAct     = !isFinished;

    return DraggableScrollableSheet(
      initialChildSize: 0.24,
      minChildSize:     0.12,
      maxChildSize:     0.62,
      snap:             true,
      snapSizes:        const [0.12, 0.24, 0.62],
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color:        _surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
            border:       const Border(
                top: BorderSide(color: _border, width: 1)),
            boxShadow:    [
              BoxShadow(
                  color:      Colors.black.withOpacity(0.55),
                  blurRadius: 28,
                  offset:     const Offset(0, -8)),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 2),
                width: 36, height: 3,
                decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2)),
              ),

              // Panel header
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Row(
                  children: [
                    // Tab toggle: Runners | Registrations
                    GestureDetector(
                      onTap: () => setState(() { _showKitPanel = false; }),
                      child: Text(
                        'RUNNERS',
                        style: TextStyle(
                            color: _showKitPanel ? _textMuted : _textSub,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        setState(() { _showKitPanel = true; });
                        _loadKitRunners();
                      },
                      child: Text(
                        'REGISTRATIONS',
                        style: TextStyle(
                            color: _showKitPanel ? _amber : _textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2),
                      ),
                    ),
                    const Spacer(),

                    // ── Start / Stop button ──────────────
                    if (canAct)
                      GestureDetector(
                        onTap: _actionLoading
                            ? null
                            : _handleRaceAction,
                        child: AnimatedContainer(
                          duration:
                              const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color:        isActive
                                ? _red.withOpacity(0.12)
                                : _green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border:       Border.all(
                              color: isActive
                                  ? _red.withOpacity(0.35)
                                  : _green.withOpacity(0.35),
                            ),
                          ),
                          child: _actionLoading
                              ? SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isActive ? _red : _green,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      color: isActive ? _red : _green,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isActive ? 'Stop' : 'Start',
                                      style: TextStyle(
                                          color: isActive
                                              ? _red
                                              : _green,
                                          fontSize:   13,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                    if (isFinished)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color:        _textMuted.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag_rounded,
                                color: _textSub, size: 14),
                            SizedBox(width: 5),
                            Text('Finished',
                                style: TextStyle(
                                    color:      _textSub,
                                    fontSize:   12,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Divider
              Container(
                margin: const EdgeInsets.only(top: 10),
                height: 1,
                color:  _border,
              ),

              // Runner list / Kit claiming list
              Expanded(
                child: _showKitPanel
                    ? _kitLoading
                        ? const Center(child: CircularProgressIndicator(
                            color: _amber, strokeWidth: 2))
                        : _kitRunners.isEmpty
                            ? ListView(controller: scrollCtrl, children: const [
                                Padding(
                                  padding: EdgeInsets.all(28),
                                  child: Text('No registrations found.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: _textSub, fontSize: 13)),
                                )
                              ])
                            : ListView.builder(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                                itemCount: _kitRunners.length,
                                itemBuilder: (_, i) {
                                  final r = _kitRunners[i];
                                  final claimed = r['claimed'] == true;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _surfaceHigh,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _border),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36, height: 36,
                                          decoration: BoxDecoration(
                                            color: _green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '#${r['bib_number'] ?? '—'}',
                                              style: const TextStyle(
                                                  color: _green,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(r['name']?.toString() ?? '—',
                                                  style: const TextStyle(
                                                      color: _textPri,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600)),
                                              Text(
                                                'Size ${r['shirt_size'] ?? '—'}',
                                                style: const TextStyle(
                                                    color: _textSub, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        claimed
                                            ? const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.check_circle_rounded,
                                                      color: _green, size: 16),
                                                  SizedBox(width: 4),
                                                  Text('Claimed',
                                                      style: TextStyle(
                                                          color: _green,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600)),
                                                ],
                                              )
                                            : GestureDetector(
                                                onTap: () => _claimKit(
                                                    r['runner_id'] as int),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: _amber.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                        color: _amber.withOpacity(0.4)),
                                                  ),
                                                  child: const Text('Claim',
                                                      style: TextStyle(
                                                          color: _amber,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700)),
                                                ),
                                              ),
                                      ],
                                    ),
                                  );
                                },
                              )
                    : (_leaderboard.isEmpty && _runners.isEmpty)
                        ? _emptyRunners(scrollCtrl)
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding:
                                const EdgeInsets.fromLTRB(14, 8, 14, 32),
                            itemCount: _leaderboard.isNotEmpty
                                ? _leaderboard.length
                                : _runners.length,
                            itemBuilder: (_, i) {
                              if (_leaderboard.isNotEmpty) {
                                final e = _leaderboard[i];
                                final rid = e['runner_id']
                                        ?.toString() ?? '$i';
                                return _RunnerRow(
                                  entry: e,
                                  rank:  i + 1,
                                  color: _runnerColor(rid),
                                );
                              }
                              final r = _runners.values.elementAt(i);
                              return _RunnerRowSimple(
                                  runner: r,
                                  color:  _runnerColor(r.id));
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyRunners(ScrollController scrollCtrl) => ListView(
    controller: scrollCtrl,   // ← must use scrollCtrl so sheet drag works when empty
    shrinkWrap: true,
    children: const [
      Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_run_rounded,
                color: _textMuted, size: 40),
            SizedBox(height: 12),
            Text('No runners online yet',
                style: TextStyle(color: _textSub, fontSize: 13)),
            SizedBox(height: 4),
            Text(
              'Runner positions appear here once\nthey open the app and start GPS.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textMuted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════
// REUSABLE SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════

// ── Pulsing dot ───────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool  pulse;
  const _PulseDot({required this.color, required this.pulse});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot o) {
    super.didUpdateWidget(o);
    if (widget.pulse && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulse &&  _c.isAnimating) _c.stop();
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        shape:     BoxShape.circle,
        color:     Color.lerp(
            widget.color,
            widget.color.withOpacity(0.3),
            _c.value),
        boxShadow: widget.pulse
            ? [BoxShadow(
                color:     widget.color.withOpacity(
                    0.55 * (1 - _c.value)),
                blurRadius: 10)]
            : null,
      ),
    ),
  );
}

// ── Badge chip ────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData? icon;
  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                color:      color,
                fontSize:   10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4)),
      ],
    ),
  );
}

// ── Side rail button ──────────────────────────────────────────────────

class _RailBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       tip;
  final VoidCallback onTap;
  const _RailBtn({
    required this.icon,
    required this.color,
    required this.tip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message:    tip,
    preferBelow: false,
    textStyle:   const TextStyle(color: _textPri, fontSize: 12),
    decoration:  BoxDecoration(
        color: _surfaceHigh,
        borderRadius: BorderRadius.circular(8)),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color:        _surface.withOpacity(0.96),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(
              color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color:     Colors.black.withOpacity(0.45),
                blurRadius: 12),
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    ),
  );
}

// ── Checkpoint pin ────────────────────────────────────────────────────

class _CheckpointPin extends StatelessWidget {
  final int    index;
  final String name;
  const _CheckpointPin({required this.index, required this.name});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 26, height: 26,
        decoration: const BoxDecoration(
            color: _blue, shape: BoxShape.circle),
        child: Center(
          child: Text('$index',
              style: const TextStyle(
                  color:      Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize:   11)),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color:        _surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
          border:       Border.all(color: _blue.withOpacity(0.3)),
        ),
        child: Text(name,
            style: const TextStyle(color: Colors.white70, fontSize: 8),
            overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

// ── Runner pin ────────────────────────────────────────────────────────

class _RunnerPin extends StatelessWidget {
  final Color  color;
  final String kmh;
  const _RunnerPin({required this.color, required this.kmh});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 13, height: 13,
        decoration: BoxDecoration(
          shape:     BoxShape.circle,
          color:     color,
          boxShadow: [BoxShadow(color: color.withOpacity(0.7), blurRadius: 8)],
        ),
      ),
      const SizedBox(height: 2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color:        _surface.withOpacity(0.88),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('$kmh km/h',
            style: TextStyle(color: color, fontSize: 8)),
      ),
    ],
  );
}

// ── Runner row — full leaderboard data ───────────────────────────────

class _RunnerRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int   rank;
  final Color color;
  const _RunnerRow({
      required this.entry, required this.rank, required this.color});

  @override
  Widget build(BuildContext context) {
    final name    = entry['name']?.toString() ?? 'Runner';
    final distFmt = entry['distance_formatted']?.toString() ?? '0 m';
    final pace    = entry['pace_formatted']?.toString() ?? '—';
    final eta     = entry['eta']?.toString() ?? '—';
    final isTop3  = rank <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        isTop3
            ? color.withOpacity(0.05)
            : _surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
            color: isTop3
                ? color.withOpacity(0.2)
                : _border),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '#$rank',
              style: TextStyle(
                  color:     isTop3 ? _amber : _textMuted,
                  fontSize:  isTop3 ? 18 : 12,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),

          // Color dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape:     BoxShape.circle,
              color:     color,
              boxShadow: [BoxShadow(
                  color: color.withOpacity(0.6), blurRadius: 5)],
            ),
          ),
          const SizedBox(width: 10),

          // Name
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    color: _textPri, fontSize: 13,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ),

          // Distance + pace + eta
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distFmt,
                  style: TextStyle(
                      color: color, fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '$pace  ·  ETA $eta',
                style: const TextStyle(
                    color: _textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Runner row — Firebase only (no leaderboard yet) ───────────────────

class _RunnerRowSimple extends StatelessWidget {
  final _RunnerState runner;
  final Color        color;
  const _RunnerRowSimple(
      {required this.runner, required this.color});

  @override
  Widget build(BuildContext context) {
    final kmh = (runner.speed * 3.6).toStringAsFixed(1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        _surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape:     BoxShape.circle,
              color:     color,
              boxShadow: [BoxShadow(
                  color: color.withOpacity(0.6), blurRadius: 5)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Runner #${runner.id}',
                style: const TextStyle(
                    color: _textPri, fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          Text('$kmh km/h',
              style: TextStyle(
                  color: color, fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Confirm bottom sheet ──────────────────────────────────────────────

class _ConfirmSheet extends StatelessWidget {
  final String   title;
  final String   body;
  final String   confirmLabel;
  final Color    confirmColor;
  final IconData icon;
  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
      decoration: const BoxDecoration(
        color:        _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border:       Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 3,
              decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 22),

          // Icon
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color:        confirmColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(
                  color: confirmColor.withOpacity(0.3)),
            ),
            child: Icon(icon, color: confirmColor, size: 26),
          ),
          const SizedBox(height: 16),

          Text(title,
              style: const TextStyle(
                  color: _textPri, fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body,
              style: const TextStyle(
                  color: _textSub, fontSize: 13, height: 1.55)),
          const SizedBox(height: 28),

          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textSub,
                  side:  const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon:  Icon(icon, size: 18),
                label: Text(confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Runner state data ─────────────────────────────────────────────────

class _RunnerState {
  final String   id;
  final LatLng   position;
  final LatLng?  prevPosition;
  final double   speed;
  final DateTime lastSeen;

  const _RunnerState({
    required this.id,
    required this.position,
    this.prevPosition,
    required this.speed,
    required this.lastSeen,
  });
}