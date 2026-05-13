// roles/race_director/screens/checkpoint_placement_screen.dart — AndoTrack
// ═══════════════════════════════════════════════════════════════════════════
// RACE DIRECTOR — WEB ONLY
// Moved from features/checkpoint/screens/ — this screen is Race Director-only
// and belongs inside the race_director role subtree.
//
// Professional desktop route planner
//   Layout:  Fixed left sidebar (280 px) + full-height map area
//   Sidebar: Back/title, location search, checkpoint list, action buttons
//   Map:     Crosshair at Center() of map Stack  →  exact match to camera.center
//   Dialogs: Centered web Dialogs (not mobile bottom sheets)
//   Tiles:   CartoDB Positron (light, clean, consistent with other RD screens)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:andotrack_app/core/services/routing_service.dart';
import 'package:andotrack_app/features/checkpoint/services/checkpoint_service.dart';

// ── Colour palette ─────────────────────────────────────────────────────────
const _kBg      = Color(0xFF080B12);
const _kSurface = Color(0xFF0F1520);
const _kBorder  = Color(0xFF1E2A3A);
const _kGreen   = Color(0xFF00E676);
const _kRed     = Color(0xFFFF5252);
const _kBlue    = Color(0xFF40C4FF);
const _kAmber   = Color(0xFFFFD740);
const _kText    = Color(0xFFCDD8E8);
const _kMuted   = Color(0xFF4A5568);

const double _kSidebarW = 280.0;

// ── Step enum ──────────────────────────────────────────────────────────────
enum _PlacingStep { none, settingStart, addingCheckpoint, settingEnd }

// ══════════════════════════════════════════════════════════════════════════
class CheckpointPlacementScreen extends StatefulWidget {
  final int raceId;
  final double? raceDistanceKm;

  const CheckpointPlacementScreen({
    super.key,
    required this.raceId,
    this.raceDistanceKm,
  });

  @override
  State<CheckpointPlacementScreen> createState() =>
      _CheckpointPlacementScreenState();
}

class _CheckpointPlacementScreenState extends State<CheckpointPlacementScreen>
    with TickerProviderStateMixin {

  // ── Controllers ──────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  final _nameCtrl  = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  // ── Animation ────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // ── State ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _checkpoints = [];
  bool _isLoading   = true;
  bool _isSaving    = false;
  int  _deletingId  = -1;
  int  _radiusMeters = 20;

  LatLng? _myPos;
  LatLng  _crosshair = const LatLng(10.3157, 123.8854);

  _PlacingStep _step = _PlacingStep.none;
  Map<String, dynamic>? _editingCp;

  List<_GeoResult> _searchResults = [];
  bool _isSearching  = false;
  bool _searchFailed = false;
  Timer? _searchDebounce;

  final Map<String, List<LatLng>> _segments = {};
  bool _isRouting = false;

  // ── Constants ─────────────────────────────────────────────────────────────
  static const _defaultCenter = LatLng(10.3157, 123.8854);
  // CartoDB Positron — clean light tiles, same as all other RD screens
  static const _tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _photon    = 'https://photon.komoot.io/api';
  static const _nominatim = 'https://nominatim.openstreetmap.org';

  // ── Checkpoint helpers ────────────────────────────────────────────────────
  bool _isStartCp(Map<String, dynamic> cp) =>
      (cp['name'] as String?)?.toLowerCase() == 'start';
  bool _isEndCp(Map<String, dynamic> cp) =>
      (cp['name'] as String?)?.toLowerCase() == 'finish' ||
      (cp['name'] as String?)?.toLowerCase() == 'end';

  bool get _hasStart => _checkpoints.any(_isStartCp);
  bool get _hasEnd   => _checkpoints.any(_isEndCp);

  List<Map<String, dynamic>> get _orderedCheckpoints {
    final starts = _checkpoints.where(_isStartCp).toList();
    final ends   = _checkpoints.where(_isEndCp).toList();
    final mids   = _checkpoints
        .where((c) => !_isStartCp(c) && !_isEndCp(c))
        .toList()
      ..sort((a, b) =>
          (a['order_number'] as int).compareTo(b['order_number'] as int));
    return [...starts, ...mids, ...ends];
  }

  List<LatLng> get _fullPolyline {
    final ordered = _orderedCheckpoints;
    if (ordered.length < 2) return [];
    final pts = <LatLng>[];
    for (int i = 0; i < ordered.length - 1; i++) {
      final seg = _segments['$i-${i + 1}'];
      if (seg != null && seg.isNotEmpty) {
        pts.isEmpty ? pts.addAll(seg) : pts.addAll(seg.skip(1));
      }
    }
    return pts;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _loadCheckpoints();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLocate());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── GPS ───────────────────────────────────────────────────────────────────
  Future<void> _autoLocate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      _mapController.move(ll, 17);
      setState(() { _crosshair = ll; _myPos = ll; });
    } catch (_) {}
  }

  Future<void> _locateMe() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _showSnack('Location permission denied.', error: true);
        await Geolocator.openAppSettings();
        return;
      }
      if (perm == LocationPermission.denied) {
        _showSnack('Location permission denied.', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final ll = LatLng(pos.latitude, pos.longitude);
      _mapController.move(ll, 17);
      if (mounted) setState(() { _crosshair = ll; _myPos = ll; });
    } catch (_) {
      _showSnack('Could not get location.', error: true);
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Future<void> _loadCheckpoints() async {
    setState(() => _isLoading = true);
    final data = await CheckpointService.getCheckpoints(widget.raceId);
    if (!mounted) return;
    setState(() {
      _checkpoints = data.cast<Map<String, dynamic>>();
      _isLoading = false;
    });
    _rebuildAllSegments();
  }

  // ── Routing ───────────────────────────────────────────────────────────────
  Future<void> _rebuildAllSegments() async {
    final ordered = _orderedCheckpoints;
    if (ordered.length < 2) {
      if (mounted) setState(() => _segments.clear());
      return;
    }
    setState(() => _isRouting = true);
    _segments.clear();
    for (int i = 0; i < ordered.length - 1; i++) {
      await _fetchSegment(i, i + 1, ordered);
    }
    if (mounted) setState(() => _isRouting = false);
  }

  Future<void> _fetchSegment(
      int fromIdx, int toIdx, List<Map<String, dynamic>> ordered) async {
    final a = ordered[fromIdx];
    final b = ordered[toIdx];
    final from = LatLng((a['lat'] as num).toDouble(), (a['lng'] as num).toDouble());
    final to   = LatLng((b['lat'] as num).toDouble(), (b['lng'] as num).toDouble());
    try {
      final pts = await RoutingService.getRoutePolyline([from, to]);
      if (mounted) setState(() => _segments['$fromIdx-$toIdx'] = pts);
    } catch (_) {
      if (mounted) setState(() => _segments['$fromIdx-$toIdx'] = [from, to]);
    }
  }

  // ── Placing flow ──────────────────────────────────────────────────────────
  void _startPlacing(_PlacingStep step) {
    if (step == _PlacingStep.addingCheckpoint && !_hasStart) {
      _showSnack('Set the Start point first.', error: true);
      return;
    }
    if (step == _PlacingStep.settingEnd && !_hasStart) {
      _showSnack('Set the Start point first.', error: true);
      return;
    }
    _searchFocus.unfocus();
    setState(() {
      _step          = step;
      _crosshair     = _mapController.camera.center;
      _searchResults = [];
      _searchFailed  = false;
    });
  }

  void _cancelPlacing() => setState(() => _step = _PlacingStep.none);

  void _confirmPlacement() {
    final point = _mapController.camera.center;
    setState(() => _crosshair = point);

    switch (_step) {
      case _PlacingStep.settingStart:     _nameCtrl.text = 'Start'; break;
      case _PlacingStep.settingEnd:       _nameCtrl.text = 'Finish'; break;
      case _PlacingStep.addingCheckpoint: _nameCtrl.clear(); break;
      case _PlacingStep.none:             return;
    }
    _radiusMeters = 20;
    _showSaveDialog(point);
  }

  void _showSaveDialog(LatLng point) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveDialog(
        point: point,
        nameCtrl: _nameCtrl,
        initialRadius: _radiusMeters,
        isSaving: _isSaving,
        step: _step,
        onRadiusChanged: (v) => setState(() => _radiusMeters = v),
        onCancel: () => Navigator.pop(context),
        onSave: () => _saveCheckpoint(point),
      ),
    ).whenComplete(() {
      if (mounted && !_isSaving) setState(() => _step = _PlacingStep.none);
    });
  }

  Future<void> _saveCheckpoint(LatLng point) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    if (_step == _PlacingStep.settingStart && _hasStart) {
      _showSnack('Start already placed.', error: true);
      Navigator.pop(context);
      setState(() { _isSaving = false; _step = _PlacingStep.none; });
      return;
    }
    if (_step == _PlacingStep.settingEnd && _hasEnd) {
      _showSnack('End already placed.', error: true);
      Navigator.pop(context);
      setState(() { _isSaving = false; _step = _PlacingStep.none; });
      return;
    }

    final int orderNumber;
    if (_step == _PlacingStep.settingStart) {
      orderNumber = 1;
    } else if (_step == _PlacingStep.settingEnd) {
      final maxOrder = _checkpoints.isEmpty
          ? 1
          : _checkpoints.map((c) => c['order_number'] as int).reduce(math.max);
      orderNumber = maxOrder + 1;
    } else {
      if (_hasEnd) {
        orderNumber = _checkpoints.firstWhere(_isEndCp)['order_number'] as int;
      } else {
        final maxOrder = _checkpoints.isEmpty
            ? 1
            : _checkpoints.map((c) => c['order_number'] as int).reduce(math.max);
        orderNumber = maxOrder + 1;
      }
    }

    setState(() => _isSaving = true);

    if (_step == _PlacingStep.addingCheckpoint && _hasEnd) {
      final endCp = _checkpoints.firstWhere(_isEndCp);
      await CheckpointService.updateCheckpoint(
        id: endCp['id'] as int,
        raceId: widget.raceId,
        orderNumber: (endCp['order_number'] as int) + 1,
      );
    }

    final result = await CheckpointService.createCheckpoint(
      raceId: widget.raceId,
      name: name,
      lat: point.latitude,
      lng: point.longitude,
      radiusMeters: _radiusMeters,
      orderNumber: orderNumber,
    );

    setState(() { _isSaving = false; _step = _PlacingStep.none; });
    if (!mounted) return;
    Navigator.pop(context);

    if (result['success'] == true) {
      await _loadCheckpoints();
      _showSnack('Checkpoint saved!', error: false);
    } else {
      _showSnack(result['message'] ?? 'Failed to save.', error: true);
    }
  }

  // ── Edit / Delete ─────────────────────────────────────────────────────────
  void _editCp(Map<String, dynamic> cp) {
    setState(() => _editingCp = cp);
    _nameCtrl.text = cp['name'] ?? '';
    _radiusMeters = (cp['radius_meters'] as num?)?.toInt() ?? 20;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditDialog(
        cp: cp,
        nameCtrl: _nameCtrl,
        initialRadius: _radiusMeters,
        isSaving: _isSaving,
        onRadiusChanged: (v) {
          setState(() {
            _radiusMeters = v;
            final idx = _checkpoints.indexWhere((c) => c['id'] == cp['id']);
            if (idx != -1) {
              _checkpoints[idx] = {..._checkpoints[idx], 'radius_meters': v};
            }
          });
        },
        onCancel: () { Navigator.pop(context); _loadCheckpoints(); },
        onSave: () => _updateCp(cp['id'] as int),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _editingCp = null);
    });
  }

  Future<void> _updateCp(int id) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { _showSnack('Name cannot be empty.', error: true); return; }
    setState(() => _isSaving = true);
    final result = await CheckpointService.updateCheckpoint(
      id: id,
      raceId: widget.raceId,
      name: name,
      radiusMeters: _radiusMeters,
    );
    setState(() { _isSaving = false; _editingCp = null; });
    if (!mounted) return;
    Navigator.pop(context);
    if (result['success'] == true) {
      await _loadCheckpoints();
      _showSnack('Checkpoint updated!', error: false);
    } else {
      _showSnack(result['message'] ?? 'Failed to update.', error: true);
      _loadCheckpoints();
    }
  }

  Future<void> _deleteCp(Map<String, dynamic> cp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _kBorder),
        ),
        title: const Text('Delete Checkpoint',
            style: TextStyle(color: _kText, fontWeight: FontWeight.bold, fontSize: 15)),
        content: Text('Delete "${cp['name']}"? This cannot be undone.',
            style: TextStyle(color: _kText.withOpacity(0.5), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingId = cp['id'] as int);
    final result = await CheckpointService.deleteCheckpoint(cp['id'] as int);
    if (!mounted) return;
    setState(() => _deletingId = -1);

    if (result['success'] == true) {
      setState(() => _checkpoints.removeWhere((c) => c['id'] == cp['id']));
      _rebuildAllSegments();
      _showSnack('Checkpoint deleted.', error: false);
    } else {
      _showSnack(result['message'] ?? 'Failed to delete.', error: true);
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      if (mounted) setState(() { _searchResults = []; _searchFailed = false; });
      return;
    }
    _searchDebounce = Timer(
        const Duration(milliseconds: 400), () => _doSearch(q.trim()));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;
    setState(() { _isSearching = true; _searchFailed = false; _searchResults = []; });
    final center = _mapController.camera.center;
    var results = await _runBothGeocoders(q, center);
    if (results.isEmpty) {
      final s = _simplifyQuery(q);
      if (s != q) results = await _runBothGeocoders(s, center);
    }
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
      _searchFailed  = results.isEmpty;
    });
  }

  Future<List<_GeoResult>> _runBothGeocoders(String q, LatLng center) async {
    final results = await Future.wait([_fetchPhoton(q, center), _fetchNominatim(q, center)]);
    return _mergeResults(results[0], results[1]);
  }

  Future<List<_GeoResult>> _fetchPhoton(String q, LatLng c) async {
    try {
      final uri = Uri.parse(
          '$_photon/?q=${Uri.encodeComponent(q)}&limit=5&lang=en'
          '&lat=${c.latitude}&lon=${c.longitude}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['features'] as List? ?? [])
          .map((f) => _parsePhoton(f as Map<String, dynamic>))
          .whereType<_GeoResult>()
          .toList();
    } catch (_) { return []; }
  }

  Future<List<_GeoResult>> _fetchNominatim(String q, LatLng c) async {
    try {
      final uri = Uri.parse(
          '$_nominatim/search?q=${Uri.encodeComponent(q)}'
          '&format=json&limit=5&addressdetails=1');
      final res = await http.get(uri, headers: {
        'User-Agent': 'AndoTrack/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      return (jsonDecode(res.body) as List)
          .map((i) => _parseNominatim(i as Map<String, dynamic>))
          .toList();
    } catch (_) { return []; }
  }

  List<_GeoResult> _mergeResults(List<_GeoResult> a, List<_GeoResult> b) {
    final merged = [...a];
    for (final r in b) {
      if (!merged.any((e) =>
          (e.lat - r.lat).abs() < 0.0007 && (e.lng - r.lng).abs() < 0.0007)) {
        merged.add(r);
      }
    }
    return merged.take(7).toList();
  }

  _GeoResult? _parsePhoton(Map<String, dynamic> f) {
    try {
      final geo = f['geometry'] as Map<String, dynamic>;
      final c = geo['coordinates'] as List;
      final lng = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      final p = f['properties'] as Map<String, dynamic>? ?? {};
      final name = p['name'] as String? ?? '';
      final city = p['city'] as String? ?? p['town'] as String? ?? '';
      return _GeoResult(
        displayName: [name, city].where((s) => s.isNotEmpty).join(', '),
        shortName: name.isNotEmpty ? name : '$lat, $lng',
        lat: lat, lng: lng,
      );
    } catch (_) { return null; }
  }

  _GeoResult _parseNominatim(Map<String, dynamic> i) {
    final addr = i['address'] as Map<String, dynamic>?;
    String short = i['display_name'] as String? ?? '';
    if (addr != null) {
      for (final k in ['road', 'suburb', 'city', 'town', 'village']) {
        final v = addr[k] as String?;
        if (v != null && v.isNotEmpty) { short = v; break; }
      }
    }
    return _GeoResult(
      displayName: i['display_name'] as String? ?? short,
      shortName: short,
      lat: double.parse(i['lat'] as String),
      lng: double.parse(i['lon'] as String),
    );
  }

  String _simplifyQuery(String q) {
    const drops = {'main', 'campus', 'branch', 'center', 'building', 'complex'};
    final words = q.trim().split(RegExp(r'\s+'));
    final kept = <String>[];
    bool dropping = true;
    for (final w in words.reversed) {
      if (dropping && drops.contains(w.toLowerCase())) continue;
      dropping = false;
      kept.insert(0, w);
    }
    final s = kept.join(' ').trim();
    return (s.length < q.length && s.split(' ').length >= 2) ? s : q;
  }

  void _selectResult(_GeoResult r) {
    _mapController.move(LatLng(r.lat, r.lng), 17);
    setState(() {
      _crosshair = LatLng(r.lat, r.lng);
      _searchResults = [];
      _searchFailed  = false;
      _searchCtrl.clear();
    });
    _searchFocus.unfocus();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() { _searchResults = []; _searchFailed = false; });
    _searchFocus.unfocus();
  }

  // ── Map events ────────────────────────────────────────────────────────────
  void _onMapEvent(MapEvent event) {
    if (mounted) setState(() => _crosshair = _mapController.camera.center);
  }

  // ── Snack ─────────────────────────────────────────────────────────────────
  void _showSnack(String msg, {required bool error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: TextStyle(
              color: error ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600)),
      backgroundColor: error ? _kRed : _kGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Route distance ────────────────────────────────────────────────────────
  double get _routeKm {
    final pts = _fullPolyline;
    if (pts.length < 2) return 0;
    double total = 0;
    const r = 6371.0;
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i]; final b = pts[i + 1];
      final dLat = (b.latitude  - a.latitude)  * math.pi / 180;
      final dLng = (b.longitude - a.longitude) * math.pi / 180;
      final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(a.latitude  * math.pi / 180) *
          math.cos(b.latitude  * math.pi / 180) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
      total += 2 * r * math.asin(math.sqrt(h));
    }
    return total;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD — Desktop layout: sidebar + map area
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final inPlacing = _step != _PlacingStep.none;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Row(
          children: [
            // ── LEFT SIDEBAR ─────────────────────────────────────
            _buildSidebar(inPlacing),

            // ── MAP AREA (full remaining width) ──────────────────
            // Crosshair uses Center() inside this Stack — it perfectly
            // matches camera.center since both reference the same widget bounds.
            Expanded(
              child: Stack(
                children: [
                  _buildMap(),
                  if (inPlacing) ...[
                    _buildCrosshair(),
                    _buildCoordBadge(),
                    _buildPlacingControls(),
                  ],
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(
                          color: _kGreen, strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SIDEBAR
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSidebar(bool inPlacing) {
    return Container(
      width: _kSidebarW,
      decoration: BoxDecoration(
        color: _kBg,
        border: Border(right: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ──────────────────────────────────────────────
          _buildSidebarHeader(inPlacing),

          // ── Search (hidden while placing) ────────────────────────
          if (!inPlacing) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _buildSearchBar(),
            ),
            if (_searchResults.isNotEmpty ||
                (_searchFailed && _searchCtrl.text.trim().length >= 2))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _buildSearchDropdown(),
              ),
          ],

          // ── Step guide ──────────────────────────────────────────
          if (!inPlacing && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _buildStepBanner(),
            ),

          // ── Action buttons ──────────────────────────────────────
          if (!inPlacing && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: _buildActionBar(),
            ),

          // ── Route header ────────────────────────────────────────
          if (_checkpoints.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                Text('ROUTE',
                    style: TextStyle(
                        color: _kMuted, fontSize: 10,
                        letterSpacing: 1.6, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                _pill('${_checkpoints.length}', _kBlue),
                const Spacer(),
                if (_routeKm > 0) ...[
                  _pill('~${_routeKm.toStringAsFixed(2)} km', _kGreen),
                  const SizedBox(width: 6),
                ],
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _isRouting ? null : _rebuildAllSegments,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _kGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kGreen.withOpacity(0.3)),
                      ),
                      child: _isRouting
                          ? const SizedBox(
                              width: 11, height: 11,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: _kGreen))
                          : const Icon(Icons.alt_route_rounded,
                              color: _kGreen, size: 13),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1, color: _kBorder),
            ),
            const SizedBox(height: 8),
          ],

          // ── Checkpoint list ─────────────────────────────────────
          Expanded(
            child: _checkpoints.isEmpty && !_isLoading
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _orderedCheckpoints.length,
                    itemBuilder: (_, i) => _checkpointRow(_orderedCheckpoints[i]),
                  ),
          ),

          // ── My Location ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _locateMe,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Icon(Icons.my_location_rounded, color: _kBlue, size: 15),
                    SizedBox(width: 6),
                    Text('My Location',
                        style: TextStyle(color: _kBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(bool inPlacing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: inPlacing ? _cancelPlacing : () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Icon(
                    inPlacing ? Icons.close_rounded : Icons.arrow_back_rounded,
                    color: _kText, size: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Route Planner',
                      style: TextStyle(
                          color: _kText, fontWeight: FontWeight.w700,
                          fontSize: 15, letterSpacing: 0.1)),
                  Text(
                    inPlacing ? _stepLabel() : 'Race ${widget.raceId}',
                    style: TextStyle(
                        color: inPlacing ? _kAmber : _kMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!inPlacing) _buildRouteChip(),
          ]),

          // Instruction banner (while placing)
          if (inPlacing) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _kAmber.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kAmber.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.open_with_rounded, color: _kAmber, size: 13),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pan the map to position the crosshair, then press Confirm.',
                    style: TextStyle(color: _kAmber.withOpacity(0.9), fontSize: 11),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_rounded, color: _kMuted.withOpacity(0.3), size: 36),
          const SizedBox(height: 12),
          const Text('No checkpoints yet',
              style: TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('Start by setting the Start point.',
              style: TextStyle(color: _kMuted.withOpacity(0.7), fontSize: 11),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  // ── Route distance chip ───────────────────────────────────────────────────
  Widget _buildRouteChip() {
    if (_isRouting) {
      return _pill('…', _kGreen);
    }
    final km = _routeKm;
    if (km > 0) {
      return _pill('${km.toStringAsFixed(1)} km', _kGreen);
    }
    return const SizedBox.shrink();
  }

  // ── Search ────────────────────────────────────────────────────────────────
  Widget _buildSearchBar() => Container(
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _kBorder),
    ),
    child: Row(children: [
      const SizedBox(width: 10),
      const Icon(Icons.search_rounded, color: _kMuted, size: 16),
      const SizedBox(width: 6),
      Expanded(
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          style: const TextStyle(color: _kText, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search location…',
            hintStyle: TextStyle(color: _kMuted.withOpacity(0.5), fontSize: 13),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      if (_isSearching)
        const Padding(
          padding: EdgeInsets.only(right: 10),
          child: SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen)),
        )
      else if (_searchCtrl.text.isNotEmpty)
        GestureDetector(
          onTap: _clearSearch,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(Icons.close_rounded,
                color: _kMuted.withOpacity(0.5), size: 16),
          ),
        )
      else
        const SizedBox(width: 10),
    ]),
  );

  Widget _buildSearchDropdown() => Container(
    constraints: const BoxConstraints(maxHeight: 220),
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _kBorder),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
    ),
    child: _searchFailed && _searchResults.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.search_off_rounded, color: _kMuted.withOpacity(0.4), size: 13),
              const SizedBox(width: 8),
              Text('No results found.',
                  style: TextStyle(color: _kMuted.withOpacity(0.6), fontSize: 11)),
            ]),
          )
        : ListView(
            shrinkWrap: true,
            children: _searchResults.asMap().entries.map((e) {
              final i = e.key; final r = e.value;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _selectResult(r),
                  child: Container(
                    decoration: BoxDecoration(
                      border: i < _searchResults.length - 1
                          ? Border(bottom: BorderSide(color: _kBorder.withOpacity(0.5)))
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(children: [
                      const Icon(Icons.place_outlined, color: _kMuted, size: 12),
                      const SizedBox(width: 8),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.shortName,
                              style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Text(r.displayName,
                              style: const TextStyle(color: _kMuted, fontSize: 9),
                              overflow: TextOverflow.ellipsis, maxLines: 1),
                        ],
                      )),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
  );

  // ── Step banner ───────────────────────────────────────────────────────────
  Widget _buildStepBanner() {
    final isSetStart = !_hasStart;
    final isAddCp    = _hasStart && !_hasEnd;
    final Color  c = isSetStart ? _kGreen : isAddCp ? _kBlue : _kAmber;
    final IconData ic = isSetStart
        ? Icons.flag_rounded
        : isAddCp ? Icons.add_location_alt_rounded : Icons.check_circle_rounded;
    final String msg = isSetStart
        ? 'Set the Start point'
        : isAddCp
            ? 'Add checkpoints, then Set End'
            : '${_checkpoints.length} checkpoints · Route built';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(ic, color: c, size: 13),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: TextStyle(color: _kText.withOpacity(0.8), fontSize: 11))),
      ]),
    );
  }

  // ── Action bar ────────────────────────────────────────────────────────────
  Widget _buildActionBar() {
    if (!_hasStart) {
      return _actionBtn('Set Start', Icons.flag_rounded, _kGreen,
          () => _startPlacing(_PlacingStep.settingStart));
    }
    return Column(children: [
      _actionBtn('Add Checkpoint', Icons.add_location_alt_rounded, _kBlue,
          () => _startPlacing(_PlacingStep.addingCheckpoint)),
      if (!_hasEnd) ...[
        const SizedBox(height: 8),
        _actionBtn('Set End', Icons.sports_score_rounded, _kRed,
            () => _startPlacing(_PlacingStep.settingEnd)),
      ],
    ]);
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  //  MAP
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMap() {
    final ordered = _orderedCheckpoints;
    final polyline = _fullPolyline;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapEvent: _onMapEvent,
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
        ),

        if (polyline.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: polyline,
              color: const Color(0xFF007A40).withOpacity(0.85),
              strokeWidth: 4.0,
            ),
          ]),

        if (_step != _PlacingStep.none && ordered.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points: [
                LatLng((ordered.last['lat'] as num).toDouble(),
                    (ordered.last['lng'] as num).toDouble()),
                _crosshair,
              ],
              color: _kAmber.withOpacity(0.5),
              strokeWidth: 2,
              isDotted: true,
            ),
          ]),

        CircleLayer(
          circles: _checkpoints.map((cp) {
            final isEdit = _editingCp?['id'] == cp['id'];
            final color  = _isStartCp(cp) ? _kGreen : _isEndCp(cp) ? _kRed : _kBlue;
            return CircleMarker(
              point: LatLng(
                  (cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
              radius: (cp['radius_meters'] as num).toDouble(),
              color: color.withOpacity(isEdit ? 0.22 : 0.10),
              borderColor: color.withOpacity(isEdit ? 0.8 : 0.45),
              borderStrokeWidth: isEdit ? 2.0 : 1.5,
              useRadiusInMeter: true,
            );
          }).toList(),
        ),

        if (_step != _PlacingStep.none)
          CircleLayer(circles: [
            CircleMarker(
              point: _crosshair,
              radius: _radiusMeters.toDouble(),
              color: _kAmber.withOpacity(0.12),
              borderColor: _kAmber.withOpacity(0.5),
              borderStrokeWidth: 1.5,
              useRadiusInMeter: true,
            ),
          ]),

        MarkerLayer(markers: [
          if (_myPos != null)
            Marker(
              point: _myPos!,
              width: 56, height: 56,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 52 * _pulseAnim.value,
                    height: 52 * _pulseAnim.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kBlue.withOpacity(0.12 * _pulseAnim.value),
                      border: Border.all(
                          color: _kBlue.withOpacity(0.3 * _pulseAnim.value),
                          width: 1.5),
                    ),
                  ),
                  Container(
                    width: 12, height: 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: _kBlue,
                      boxShadow: [BoxShadow(color: _kBlue, blurRadius: 6, spreadRadius: 1)],
                    ),
                  ),
                ]),
              ),
            ),

          ..._orderedCheckpoints.asMap().entries.map((e) {
            final cp = e.value;
            final isStart = _isStartCp(cp);
            final isEnd   = _isEndCp(cp);
            final isEdit  = _editingCp?['id'] == cp['id'];
            final color   = isEdit ? _kAmber : isStart ? _kGreen : isEnd ? _kRed : _kBlue;
            final mids    = _orderedCheckpoints
                .where((c) => !_isStartCp(c) && !_isEndCp(c)).toList();
            final midIdx  = mids.indexWhere((c) => c['id'] == cp['id']);
            final label   = isStart ? 'S' : isEnd ? 'E' : '${midIdx + 1}';

            return Marker(
              point: LatLng(
                  (cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
              width: 68, height: 56,
              alignment: const Alignment(0.0, -0.464), 
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _editCp(cp),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: color.withOpacity(0.55),
                            blurRadius: isEdit ? 14 : 8,
                            spreadRadius: isEdit ? 2 : 1)],
                      ),
                      child: Center(child: Text(label,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900, fontSize: 12))),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 68),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withOpacity(0.5)),
                      ),
                      child: Text(cp['name'] ?? '',
                          style: TextStyle(
                              color: color, fontSize: 8.5, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ]),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CROSSHAIR — Center() here = center of the map Stack = camera.center ✓
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCrosshair() {
    final color = _step == _PlacingStep.settingStart ? _kGreen
        : _step == _PlacingStep.settingEnd ? _kRed : _kAmber;
    return Center(
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          ),
        ),
        Container(width: 40, height: 1.5, color: color.withOpacity(0.8)),
        Container(width: 1.5, height: 40, color: color.withOpacity(0.8)),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: color,
            boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 8)],
          ),
        ),
      ]),
    );
  }

  Widget _buildCoordBadge() => Positioned(
    top: 16, left: 0, right: 0,
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _kSurface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.my_location_rounded, color: _kAmber, size: 12),
          const SizedBox(width: 6),
          Text(
            '${_crosshair.latitude.toStringAsFixed(6)}, '
            '${_crosshair.longitude.toStringAsFixed(6)}',
            style: const TextStyle(
              color: _kText, fontSize: 11, fontFamily: 'monospace',
              fontWeight: FontWeight.w600, letterSpacing: 0.2,
            ),
          ),
        ]),
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  //  PLACING CONTROLS  (Confirm button on map)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPlacingControls() {
    final Color color = _step == _PlacingStep.settingStart ? _kGreen
        : _step == _PlacingStep.settingEnd ? _kRed : _kAmber;
    final String label = _step == _PlacingStep.settingStart
        ? 'Confirm Start'
        : _step == _PlacingStep.settingEnd ? 'Confirm End' : 'Confirm Checkpoint';
    final IconData icon = _step == _PlacingStep.settingStart
        ? Icons.flag_rounded
        : _step == _PlacingStep.settingEnd
            ? Icons.sports_score_rounded
            : Icons.location_on_rounded;

    return Positioned(
      bottom: 32, left: 24, right: 24,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _confirmPlacement,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: color.withOpacity(0.5), blurRadius: 20, spreadRadius: 2)],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.black, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Step label ────────────────────────────────────────────────────────────
  String _stepLabel() {
    switch (_step) {
      case _PlacingStep.settingStart:     return 'Setting Start';
      case _PlacingStep.addingCheckpoint: return 'Adding Checkpoint';
      case _PlacingStep.settingEnd:       return 'Setting Finish';
      case _PlacingStep.none:             return '';
    }
  }

  // ── Checkpoint row (sidebar) ──────────────────────────────────────────────
  Widget _checkpointRow(Map<String, dynamic> cp) {
    final id         = cp['id'] as int;
    final isStart    = _isStartCp(cp);
    final isEnd      = _isEndCp(cp);
    final isDeleting = _deletingId == id;
    final color      = isStart ? _kGreen : isEnd ? _kRed : _kBlue;
    final mids       = _orderedCheckpoints
        .where((c) => !_isStartCp(c) && !_isEndCp(c)).toList();
    final midIdx = mids.indexWhere((c) => c['id'] == id);
    final label  = isStart ? 'S' : isEnd ? 'E' : '${midIdx + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: Text(label,
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cp['name'] ?? '',
                style: const TextStyle(
                    color: _kText, fontWeight: FontWeight.w600, fontSize: 12),
                overflow: TextOverflow.ellipsis),
            Text(
              '${(cp['lat'] as num).toDouble().toStringAsFixed(4)}, '
              '${(cp['lng'] as num).toDouble().toStringAsFixed(4)}',
              style: const TextStyle(color: _kMuted, fontSize: 9),
            ),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: _kBorder.withOpacity(0.5),
            borderRadius: BorderRadius.circular(5)),
          child: Text('${cp['radius_meters']}m',
              style: const TextStyle(color: _kMuted, fontSize: 9)),
        ),
        const SizedBox(width: 4),
        _iconBtn(Icons.edit_outlined, _kAmber, () => _editCp(cp)),
        const SizedBox(width: 3),
        isDeleting
            ? const SizedBox(width: 24, height: 24,
                child: Center(child: SizedBox(width: 13, height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))))
            : _iconBtn(Icons.delete_outline_rounded, _kRed, () => _deleteCp(cp)),
      ]),
    );
  }

  // ── Shared small widgets ──────────────────────────────────────────────────
  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 13),
          ),
        ),
      );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SAVE DIALOG  — centered web dialog, replaces mobile bottom sheet
// ══════════════════════════════════════════════════════════════════════════════
class _SaveDialog extends StatefulWidget {
  final LatLng point;
  final TextEditingController nameCtrl;
  final int initialRadius;
  final bool isSaving;
  final _PlacingStep step;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _SaveDialog({
    required this.point, required this.nameCtrl,
    required this.initialRadius, required this.isSaving,
    required this.step, required this.onRadiusChanged,
    required this.onCancel, required this.onSave,
  });

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late int _radius;

  @override
  void initState() { super.initState(); _radius = widget.initialRadius; }

  @override
  Widget build(BuildContext context) {
    final color = widget.step == _PlacingStep.settingStart ? _kGreen
        : widget.step == _PlacingStep.settingEnd ? _kRed : _kAmber;
    final title = widget.step == _PlacingStep.settingStart ? 'Set Start'
        : widget.step == _PlacingStep.settingEnd ? 'Set End' : 'Add Checkpoint';
    final icon  = widget.step == _PlacingStep.settingStart ? Icons.flag_rounded
        : widget.step == _PlacingStep.settingEnd
            ? Icons.sports_score_rounded
            : Icons.add_location_alt_rounded;

    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
      ),
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: const TextStyle(
                            color: _kText, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '${widget.point.latitude.toStringAsFixed(6)}, '
                      '${widget.point.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                          color: _kMuted, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),

              Text('NAME', style: TextStyle(
                  color: _kMuted, fontSize: 10, letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: widget.nameCtrl,
                autofocus: true,
                style: const TextStyle(color: _kText),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Start Line, KM 5, Finish',
                  hintStyle: const TextStyle(color: _kMuted),
                  filled: true, fillColor: _kBg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color)),
                ),
              ),
              const SizedBox(height: 18),

              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('DETECTION RADIUS', style: TextStyle(
                    color: _kMuted, fontSize: 10, letterSpacing: 1.4,
                    fontWeight: FontWeight.w700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('$_radius m',
                      style: TextStyle(color: color, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              Slider(
                value: _radius.toDouble(), min: 10, max: 100, divisions: 18,
                activeColor: color, inactiveColor: _kBorder,
                onChanged: (v) {
                  setState(() => _radius = v.round());
                  widget.onRadiusChanged(v.round());
                },
              ),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kMuted,
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
                  child: ElevatedButton(
                    onPressed: widget.isSaving ? null : widget.onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: widget.isSaving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Text('Save $title',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  EDIT DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _EditDialog extends StatefulWidget {
  final Map<String, dynamic> cp;
  final TextEditingController nameCtrl;
  final int initialRadius;
  final bool isSaving;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _EditDialog({
    required this.cp, required this.nameCtrl,
    required this.initialRadius, required this.isSaving,
    required this.onRadiusChanged, required this.onCancel, required this.onSave,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late int _radius;

  @override
  void initState() { super.initState(); _radius = widget.initialRadius; }

  @override
  Widget build(BuildContext context) {
    final lat = (widget.cp['lat'] as num).toDouble();
    final lng = (widget.cp['lng'] as num).toDouble();

    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kAmber, width: 1.5),
      ),
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _kAmber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kAmber.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.edit_rounded, color: _kAmber, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Edit Checkpoint',
                        style: TextStyle(
                            color: _kText, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                        style: const TextStyle(
                            color: _kMuted, fontSize: 11, fontFamily: 'monospace')),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),

              Text('NAME', style: TextStyle(
                  color: _kMuted, fontSize: 10, letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: widget.nameCtrl,
                autofocus: true,
                style: const TextStyle(color: _kText),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  filled: true, fillColor: _kBg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder)),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: _kAmber)),
                ),
              ),
              const SizedBox(height: 18),

              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('DETECTION RADIUS', style: TextStyle(
                    color: _kMuted, fontSize: 10, letterSpacing: 1.4,
                    fontWeight: FontWeight.w700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kAmber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('$_radius m',
                      style: const TextStyle(color: _kAmber, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              Slider(
                value: _radius.toDouble(), min: 10, max: 500, divisions: 49,
                activeColor: _kAmber, inactiveColor: _kBorder,
                onChanged: (v) {
                  setState(() => _radius = v.round());
                  widget.onRadiusChanged(v.round());
                },
              ),
              Text('Radius updates live on the map.',
                  style: TextStyle(color: _kMuted.withOpacity(0.5), fontSize: 11)),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kMuted,
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
                  child: ElevatedButton(
                    onPressed: widget.isSaving ? null : widget.onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAmber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: widget.isSaving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Text('Save Changes',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  GEO RESULT
// ══════════════════════════════════════════════════════════════════════════════
class _GeoResult {
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;
  const _GeoResult({
    required this.displayName, required this.shortName,
    required this.lat, required this.lng,
  });
}
