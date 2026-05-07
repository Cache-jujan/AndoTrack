// checkpoint_placement_screen.dart — AndoTrack
// ═══════════════════════════════════════════════════════════════════════════
// REDESIGNED: Progressive checkpoint-driven routing
//   Flow:  Set Start  →  Add Checkpoints (n)  →  Set End
//   Route: built segment-by-segment: Start→CP1, CP1→CP2, …, CPn→End
//   Fixes: gesture conflicts, bottom-sheet drag, button logic, UI clutter
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
const _kBg       = Color(0xFF080B12);
const _kSurface  = Color(0xFF0F1520);
const _kBorder   = Color(0xFF1E2A3A);
const _kGreen    = Color(0xFF00E676);   // Start
const _kRed      = Color(0xFFFF5252);   // End
const _kBlue     = Color(0xFF40C4FF);   // Checkpoint
const _kAmber    = Color(0xFFFFD740);   // Edit / active
const _kText     = Color(0xFFCDD8E8);
const _kMuted    = Color(0xFF4A5568);

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
  final MapController   _mapController   = MapController();
  final _nameCtrl       = TextEditingController();
  final _searchCtrl     = TextEditingController();
  final _searchFocus    = FocusNode();

  // ── Animation ────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;
  late final AnimationController _panelCtrl;
  late final Animation<double>   _panelAnim;

  // ── State ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _checkpoints = [];
  bool   _isLoading    = true;
  bool   _isSaving     = false;
  int    _deletingId   = -1;
  int    _radiusMeters = 20;

  // GPS
  LatLng? _myPos;
  LatLng  _crosshair = const LatLng(10.3157, 123.8854);

  // Placing
  _PlacingStep _step = _PlacingStep.none;

  // Edit
  Map<String, dynamic>? _editingCp;

  // Search
  List<_GeoResult> _searchResults = [];
  bool   _isSearching  = false;
  bool   _searchFailed = false;
  Timer? _searchDebounce;

  // Route — keyed segments for progressive drawing
  // Key: "startIdx-endIdx", Value: List<LatLng>
  final Map<String, List<LatLng>> _segments = {};
  bool _isRouting = false;

  // Bottom sheet
  static const double _kSheetPeek = 100.0;
  static const double _kSheetMid  = 300.0;
  static const double _kSheetFull = 540.0;
  double _sheetH = _kSheetPeek;
  double _sheetDragStart = 0;

  // ── Helpers ───────────────────────────────────────────────────────────────
  static const _defaultCenter = LatLng(10.3157, 123.8854);
  static const _tileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const _photon    = 'https://photon.komoot.io/api';
  static const _nominatim = 'https://nominatim.openstreetmap.org';

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
      final key = '$i-${i + 1}';
      final seg = _segments[key];
      if (seg != null && seg.isNotEmpty) {
        if (pts.isEmpty) {
          pts.addAll(seg);
        } else {
          pts.addAll(seg.skip(1));
        }
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

    _panelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _panelAnim = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutCubic);

    _loadCheckpoints();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLocate());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _panelCtrl.dispose();
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
        _showSnack('Location permission denied. Enable in Settings.', error: true);
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
      _showSnack('Could not get location. Ensure GPS is on.', error: true);
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

  // ── Progressive segment routing ───────────────────────────────────────────
  // Core redesign: route EACH consecutive pair as its own segment.
  // This ensures the route always follows the intended approved path.

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

  Future<void> _fetchLastSegment() async {
    final ordered = _orderedCheckpoints;
    if (ordered.length < 2) return;
    final i = ordered.length - 2;
    setState(() => _isRouting = true);
    await _fetchSegment(i, i + 1, ordered);
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
      if (mounted) {
        setState(() => _segments['$fromIdx-$toIdx'] = pts);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _segments['$fromIdx-$toIdx'] = [from, to]);
      }
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
      _step        = step;
      _crosshair   = _mapController.camera.center;
      _sheetH      = _kSheetPeek;
      _searchResults = [];
      _searchFailed  = false;
    });
  }

  void _cancelPlacing() => setState(() => _step = _PlacingStep.none);

  void _confirmPlacement() {
    final point = _mapController.camera.center;
    setState(() => _crosshair = point);

    switch (_step) {
      case _PlacingStep.settingStart:
        _nameCtrl.text = 'Start';
        break;
      case _PlacingStep.settingEnd:
        _nameCtrl.text = 'Finish';
        break;
      case _PlacingStep.addingCheckpoint:
        _nameCtrl.clear();
        break;
      case _PlacingStep.none:
        return;
    }
    _radiusMeters = 20;
    _showSaveSheet(point);
  }

  void _showSaveSheet(LatLng point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SaveSheet(
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

    // Guard duplicates
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

    // Determine order_number
    final int orderNumber;
    if (_step == _PlacingStep.settingStart) {
      orderNumber = 1;
    } else if (_step == _PlacingStep.settingEnd) {
      // End is always highest order
      final maxOrder = _checkpoints.isEmpty
          ? 1
          : _checkpoints
              .map((c) => c['order_number'] as int)
              .reduce(math.max);
      orderNumber = maxOrder + 1;
    } else {
      // Intermediate checkpoint — insert before End if it exists
      if (_hasEnd) {
        final endOrder = (_checkpoints.firstWhere(_isEndCp)['order_number'] as int);
        orderNumber = endOrder; // We'll shift end up below
      } else {
        final maxOrder = _checkpoints.isEmpty
            ? 1
            : _checkpoints
                .map((c) => c['order_number'] as int)
                .reduce(math.max);
        orderNumber = maxOrder + 1;
      }
    }

    setState(() => _isSaving = true);

    // If inserting before End, bump End's order
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditSheet(
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
    radiusMeters: _radiusMeters);
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
    final confirmed = await _showDeleteDialog(cp['name'] ?? 'Checkpoint');
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

  Future<bool?> _showDeleteDialog(String name) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      title: const Text('Delete Checkpoint',
          style: TextStyle(color: _kText, fontWeight: FontWeight.bold, fontSize: 15)),
      content: Text('Delete "$name"? This cannot be undone.',
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

  // ── Search ────────────────────────────────────────────────────────────────
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      if (mounted) setState(() { _searchResults = []; _searchFailed = false; });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _doSearch(q.trim()));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;
    setState(() { _isSearching = true; _searchFailed = false; _searchResults = []; });
    final center = _mapController.camera.center;
    var results = await _runBothGeocoders(q, center);
    if (results.isEmpty) {
      final simplified = _simplifyQuery(q);
      if (simplified != q) results = await _runBothGeocoders(simplified, center);
    }
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
      _searchFailed = results.isEmpty;
    });
  }

  Future<List<_GeoResult>> _runBothGeocoders(String q, LatLng center) async {
    final results = await Future.wait([
      _fetchPhoton(q, center),
      _fetchNominatim(q, center),
    ]);
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
    if (event is MapEventMove || event is MapEventMoveEnd ||
        event is MapEventScrollWheelZoom || event is MapEventDoubleTapZoom) {
      if (mounted) setState(() => _crosshair = _mapController.camera.center);
    }
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

  // ── Route distance estimate ───────────────────────────────────────────────
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
          math.cos(a.latitude * math.pi / 180) * math.cos(b.latitude * math.pi / 180) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
      total += 2 * r * math.asin(math.sqrt(h));
    }
    return total;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final inPlacing = _step != _PlacingStep.none;
    final showSearch = _searchResults.isNotEmpty ||
        (_searchFailed && _searchCtrl.text.trim().length >= 2);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // ── 1. MAP (always behind everything) ────────────────────────
            _buildMap(),

            // ── 2. CROSSHAIR (only while placing) ────────────────────────
            if (inPlacing) ...[
              _buildCrosshair(),
              _buildCoordBadge(),
            ],

            // ── 3. APP BAR area ──────────────────────────────────────────
            _buildAppBar(inPlacing),

            // ── 4. SEARCH bar + dropdown (hidden while placing) ───────────
            if (!inPlacing) ...[
              Positioned(
                top: 100, left: 12, right: 12,
                child: Column(children: [
                  _buildSearchBar(),
                  if (showSearch) _buildSearchDropdown(),
                ]),
              ),
            ],

            // ── 5. STEP GUIDE banner (not placing, not loading) ───────────
            if (!inPlacing && !_isLoading)
              Positioned(
                top: 158, left: 12, right: 68,
                child: _buildStepBanner(),
              ),

            // ── 6. MY LOCATION button ─────────────────────────────────────
            if (!inPlacing)
              Positioned(
                top: 158, right: 12,
                child: _buildFab(
                  icon: Icons.my_location_rounded,
                  color: _kBlue,
                  onTap: _locateMe,
                ),
              ),

            // ── 7. ACTION BUTTONS (bottom-left, not placing) ──────────────
            if (!inPlacing && !_isLoading)
              Positioned(
                bottom: _sheetH + 12,
                left: 16, right: 16,
                child: _buildActionBar(),
              ),

            // ── 8. PLACING CONTROLS ───────────────────────────────────────
            if (inPlacing) _buildPlacingControls(),

            // ── 9. BOTTOM CHECKPOINT PANEL ────────────────────────────────
            if (_checkpoints.isNotEmpty && !inPlacing)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _buildBottomPanel(),
              ),

            // ── 10. LOADING ───────────────────────────────────────────────
            if (_isLoading)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(
                    color: _kGreen, strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
        // GESTURE FIX: map handles only its own pan/zoom; no bleed-through.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapEvent: _onMapEvent,
      ),
      children: [
        // Tiles
        TileLayer(
          urlTemplate: _tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.andotrack_app',
        ),

        // Full route polyline
        if (polyline.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: polyline,
              color: _kGreen.withOpacity(0.7),
              strokeWidth: 3.5,
            ),
          ]),

        // Pending dashed line from last cp to crosshair (placing new cp)
        if (_step != _PlacingStep.none && ordered.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points: [
                LatLng(
                  (ordered.last['lat'] as num).toDouble(),
                  (ordered.last['lng'] as num).toDouble(),
                ),
                _crosshair,
              ],
              color: _kAmber.withOpacity(0.45),
              strokeWidth: 2,
              isDotted: true,
            ),
          ]),

        // Detection radius circles
        CircleLayer(
          circles: _checkpoints.map((cp) {
            final isEdit = _editingCp?['id'] == cp['id'];
            final color  = _isStartCp(cp) ? _kGreen
                : _isEndCp(cp) ? _kRed : _kBlue;
            return CircleMarker(
              point: LatLng((cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
              radius: (cp['radius_meters'] as num).toDouble(),
              color: color.withOpacity(isEdit ? 0.22 : 0.10),
              borderColor: color.withOpacity(isEdit ? 0.8 : 0.4),
              borderStrokeWidth: isEdit ? 2.0 : 1.5,
              useRadiusInMeter: true,
            );
          }).toList(),
        ),

        // Live placing circle preview
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

        // Checkpoint markers
        MarkerLayer(markers: [
          // GPS dot
          if (_myPos != null)
            Marker(
              point: _myPos!,
              width: 56, height: 56,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
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
                        shape: BoxShape.circle,
                        color: _kBlue,
                        boxShadow: [BoxShadow(color: _kBlue, blurRadius: 6, spreadRadius: 1)],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Checkpoint markers
          ..._orderedCheckpoints.asMap().entries.map((e) {
            final cp = e.value;
            final isStart  = _isStartCp(cp);
            final isEnd    = _isEndCp(cp);
            final isEdit   = _editingCp?['id'] == cp['id'];
            final color    = isEdit ? _kAmber
                : isStart ? _kGreen : isEnd ? _kRed : _kBlue;

            // Label: S, E, or sequential number
            final mids = _orderedCheckpoints.where((c) => !_isStartCp(c) && !_isEndCp(c)).toList();
            final midIdx = mids.indexWhere((c) => c['id'] == cp['id']);
            final label  = isStart ? 'S' : isEnd ? 'E' : '${midIdx + 1}';

            return Marker(
              point: LatLng((cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
              width: 68, height: 56,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () => _editCp(cp),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: color.withOpacity(0.55),
                            blurRadius: isEdit ? 14 : 8,
                            spreadRadius: isEdit ? 2 : 1)],
                      ),
                      child: Center(child: Text(label,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 12))),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 68),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xCC080B12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Text(cp['name'] ?? '',
                          style: const TextStyle(
                              color: _kText, fontSize: 8.5, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            );
          }),
        ]),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CROSSHAIR + COORD BADGE
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
        Container(
          width: 40, height: 1.5,
          color: color.withOpacity(0.8),
        ),
        Container(
          width: 1.5, height: 40,
          color: color.withOpacity(0.8),
        ),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 8)],
          ),
        ),
      ]),
    );
  }

  Widget _buildCoordBadge() {
    return Positioned(
      top: 56, left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _kSurface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: const Border.fromBorderSide(BorderSide(color: _kBorder)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.my_location_rounded, color: _kAmber, size: 12),
            const SizedBox(width: 6),
            Text(
              '${_crosshair.latitude.toStringAsFixed(6)}, '
              '${_crosshair.longitude.toStringAsFixed(6)}',
              style: const TextStyle(
                color: _kText, fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  APP BAR
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAppBar(bool inPlacing) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kBg, _kBg.withOpacity(0.0)],
            stops: const [0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: _kText),
                onPressed: inPlacing ? _cancelPlacing : () => Navigator.pop(context),
              ),

              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Place Checkpoints',
                        style: TextStyle(
                            color: _kText,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.2)),
                    Text(
                      inPlacing
                          ? _stepLabel()
                          : 'Race ${widget.raceId}  ·  ${_checkpoints.length} checkpoints',
                      style: TextStyle(
                          color: inPlacing ? _kAmber : _kMuted,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),

              // Route chip
              if (!inPlacing) _buildRouteChip(),
            ]),
          ),
        ),
      ),
    );
  }

  String _stepLabel() {
    switch (_step) {
      case _PlacingStep.settingStart:      return 'Pan to start line · tap Confirm';
      case _PlacingStep.addingCheckpoint:  return 'Pan to checkpoint · tap Confirm';
      case _PlacingStep.settingEnd:        return 'Pan to finish line · tap Confirm';
      case _PlacingStep.none:              return '';
    }
  }

  Widget _buildRouteChip() {
    if (_isRouting) {
      return _chip(
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          SizedBox(width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGreen)),
          SizedBox(width: 6),
          Text('Routing…', style: TextStyle(color: _kGreen, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        color: _kGreen,
      );
    }
    final km = _routeKm;
    if (km > 0) {
      return _chip(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.route_rounded, color: _kGreen, size: 13),
          const SizedBox(width: 5),
          Text('${km.toStringAsFixed(2)} km',
              style: const TextStyle(color: _kGreen, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        color: _kGreen,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _chip({required Widget child, required Color color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: child,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  //  SEARCH
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSearchBar() => Container(
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(12),
      border: const Border.fromBorderSide(BorderSide(color: _kBorder)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
    ),
    child: Row(children: [
      const SizedBox(width: 12),
      const Icon(Icons.search_rounded, color: _kMuted, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          style: const TextStyle(color: _kText, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search city, street, landmark…',
            hintStyle: TextStyle(color: _kMuted.withOpacity(0.5), fontSize: 14),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      if (_isSearching)
        const Padding(padding: EdgeInsets.only(right: 12),
            child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen)))
      else if (_searchCtrl.text.isNotEmpty)
        GestureDetector(
          onTap: _clearSearch,
          child: Padding(padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.close_rounded, color: _kMuted.withOpacity(0.5), size: 18)),
        )
      else
        const SizedBox(width: 12),
    ]),
  );

  Widget _buildSearchDropdown() => Container(
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(12),
      border: const Border.fromBorderSide(BorderSide(color: _kBorder)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
    ),
    child: _searchFailed && _searchResults.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.search_off_rounded, color: _kMuted.withOpacity(0.4), size: 16),
              const SizedBox(width: 10),
              Text('No results. Try a broader term.',
                  style: TextStyle(color: _kMuted.withOpacity(0.6), fontSize: 12)),
            ]),
          )
        : Column(
            children: _searchResults.asMap().entries.map((e) {
              final i = e.key; final r = e.value;
              return GestureDetector(
                onTap: () => _selectResult(r),
                child: Container(
                  decoration: BoxDecoration(
                    border: i < _searchResults.length - 1
                        ? Border(bottom: BorderSide(color: _kBorder.withOpacity(0.5)))
                        : null,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(children: [
                    const Icon(Icons.place_outlined, color: _kMuted, size: 15),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.shortName,
                            style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(r.displayName,
                            style: const TextStyle(color: _kMuted, fontSize: 10),
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ],
                    )),
                    const Icon(Icons.chevron_right_rounded, color: _kMuted, size: 16),
                  ]),
                ),
              );
            }).toList(),
          ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  //  STEP BANNER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStepBanner() {
    final isSetStart  = !_hasStart;
    final isAddCp     = _hasStart && !_hasEnd;
    final isDone      = _hasStart && _hasEnd;

    final Color bColor = isSetStart ? _kGreen : isAddCp ? _kBlue : _kAmber;
    final IconData bIcon = isSetStart
        ? Icons.flag_rounded
        : isAddCp
            ? Icons.add_location_alt_rounded
            : Icons.check_circle_rounded;
    final String bText = isSetStart
        ? 'Step 1: Set the Start point'
        : isAddCp
            ? 'Add checkpoints, then Set the End point'
            : '${_checkpoints.length} checkpoints saved · Route built';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bColor.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
      ),
      child: Row(children: [
        Icon(bIcon, color: bColor, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(bText,
            style: TextStyle(color: _kText.withOpacity(0.75), fontSize: 12))),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ACTION BAR  (Set Start / Add Checkpoint / Set End)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildActionBar() {
    // Three distinct states, minimal buttons
    if (!_hasStart) {
      return _actionButton(
        label: 'Set Start',
        icon: Icons.flag_rounded,
        color: _kGreen,
        onTap: () => _startPlacing(_PlacingStep.settingStart),
      );
    }

    return Row(children: [
      // Add Checkpoint (always available once start is set)
      Expanded(
        child: _actionButton(
          label: 'Add Checkpoint',
          icon: Icons.add_location_alt_rounded,
          color: _kBlue,
          onTap: () => _startPlacing(_PlacingStep.addingCheckpoint),
        ),
      ),
      if (!_hasEnd) ...[
        const SizedBox(width: 10),
        // Set End
        Expanded(
          child: _actionButton(
            label: 'Set End',
            icon: Icons.sports_score_rounded,
            color: _kRed,
            onTap: () => _startPlacing(_PlacingStep.settingEnd),
          ),
        ),
      ],
    ]);
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.5)),
            boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 12)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  //  PLACING CONTROLS  (Cancel + Confirm)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPlacingControls() {
    final Color btnColor = _step == _PlacingStep.settingStart ? _kGreen
        : _step == _PlacingStep.settingEnd ? _kRed : _kAmber;
    final String btnLabel = _step == _PlacingStep.settingStart
        ? 'Confirm Start'
        : _step == _PlacingStep.settingEnd
            ? 'Confirm End'
            : 'Confirm Checkpoint';
    final IconData btnIcon = _step == _PlacingStep.settingStart
        ? Icons.flag_rounded
        : _step == _PlacingStep.settingEnd
            ? Icons.sports_score_rounded
            : Icons.location_on_rounded;

    return Stack(children: [
      // Cancel pill — top-left
      Positioned(
        top: 56, left: 16,
        child: GestureDetector(
          onTap: _cancelPlacing,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(24),
              border: const Border.fromBorderSide(BorderSide(color: _kBorder)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.close_rounded, color: _kMuted, size: 15),
              SizedBox(width: 6),
              Text('Cancel', style: TextStyle(color: _kMuted, fontSize: 13)),
            ]),
          ),
        ),
      ),

      // Confirm button — bottom
      Positioned(
        bottom: 36, left: 24, right: 24,
        child: GestureDetector(
          onTap: _confirmPlacement,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: btnColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                  color: btnColor.withOpacity(0.45),
                  blurRadius: 18, spreadRadius: 2)],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(btnIcon, color: Colors.black, size: 20),
              const SizedBox(width: 8),
              Text(btnLabel,
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BOTTOM PANEL
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildBottomPanel() {
    return GestureDetector(
      // GESTURE FIX: absorb vertical drags for the sheet — does NOT bleed to map.
      onVerticalDragStart: (d) => _sheetDragStart = d.globalPosition.dy,
      onVerticalDragUpdate: (d) {
        final dy = d.globalPosition.dy - _sheetDragStart;
        _sheetDragStart = d.globalPosition.dy;
        setState(() {
          _sheetH = (_sheetH - dy).clamp(_kSheetPeek, _kSheetFull);
        });
      },
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        final double target;
        if (v < -500)       { target = _sheetH > (_kSheetPeek + _kSheetMid) / 2 ? _kSheetFull : _kSheetMid; }
        else if (v > 500)   { target = _sheetH < (_kSheetMid  + _kSheetFull) / 2 ? _kSheetPeek : _kSheetMid; }
        else {
          final m1 = (_kSheetPeek + _kSheetMid) / 2;
          final m2 = (_kSheetMid  + _kSheetFull) / 2;
          target = _sheetH < m1 ? _kSheetPeek : _sheetH < m2 ? _kSheetMid : _kSheetFull;
        }
        setState(() => _sheetH = target);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: _sheetH,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: _kBorder)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24, offset: const Offset(0, -4))],
        ),
        child: Column(children: [
          // Handle + header row
          Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
              width: 36, height: 3,
              decoration: BoxDecoration(
                color: _kBorder,
                borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                Text('ROUTE',
                    style: TextStyle(
                        color: _kMuted, fontSize: 10,
                        letterSpacing: 1.6, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _pill('${_checkpoints.length}', _kBlue),
                const Spacer(),
                // Estimated km
                if (_routeKm > 0)
                  _pill('~${_routeKm.toStringAsFixed(2)} km', _kGreen),
                const SizedBox(width: 8),
                // Re-route button
                GestureDetector(
                  onTap: _isRouting ? null : _rebuildAllSegments,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kGreen.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _isRouting
                          ? const SizedBox(width: 10, height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGreen))
                          : const Icon(Icons.alt_route_rounded, color: _kGreen, size: 13),
                      const SizedBox(width: 5),
                      Text(_isRouting ? 'Routing…' : 'Re-route',
                          style: const TextStyle(
                              color: _kGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ]),
            ),
            // Divider
            Container(height: 1, color: _kBorder),
          ]),

          // Checkpoint list — NOT wrapped in GestureDetector so scroll works independently
          Expanded(
            child: NotificationListener<ScrollNotification>(
              // Prevent scroll from propagating up to the drag handler
              onNotification: (_) => true,
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                itemCount: _orderedCheckpoints.length,
                itemBuilder: (_, i) => _checkpointRow(_orderedCheckpoints[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _checkpointRow(Map<String, dynamic> cp) {
    final id        = cp['id'] as int;
    final isStart   = _isStartCp(cp);
    final isEnd     = _isEndCp(cp);
    final isDeleting = _deletingId == id;
    final color     = isStart ? _kGreen : isEnd ? _kRed : _kBlue;
    final mids = _orderedCheckpoints.where((c) => !_isStartCp(c) && !_isEndCp(c)).toList();
    final midIdx = mids.indexWhere((c) => c['id'] == id);
    final label = isStart ? 'S' : isEnd ? 'E' : '${midIdx + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(children: [
        // Badge
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: Text(label,
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cp['name'] ?? '',
                style: const TextStyle(
                    color: _kText, fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            Text(
              '${(cp['lat'] as num).toDouble().toStringAsFixed(5)}, '
              '${(cp['lng'] as num).toDouble().toStringAsFixed(5)}',
              style: const TextStyle(color: _kMuted, fontSize: 10),
            ),
          ],
        )),
        // Radius badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: _kBorder.withOpacity(0.5),
            borderRadius: BorderRadius.circular(6)),
          child: Text('${cp['radius_meters']}m',
              style: const TextStyle(color: _kMuted, fontSize: 10)),
        ),
        const SizedBox(width: 6),
        // Edit
        _iconBtn(Icons.edit_outlined, _kAmber, () => _editCp(cp)),
        const SizedBox(width: 5),
        // Delete
        isDeleting
            ? const SizedBox(width: 28, height: 28,
                child: Center(child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))))
            : _iconBtn(Icons.delete_outline_rounded, _kRed, () => _deleteCp(cp)),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
      );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _buildFab({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _kSurface,
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SAVE SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _SaveSheet extends StatefulWidget {
  final LatLng point;
  final TextEditingController nameCtrl;
  final int initialRadius;
  final bool isSaving;
  final _PlacingStep step;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _SaveSheet({
    required this.point, required this.nameCtrl,
    required this.initialRadius, required this.isSaving,
    required this.step, required this.onRadiusChanged,
    required this.onCancel, required this.onSave,
  });

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
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
        : widget.step == _PlacingStep.settingEnd ? Icons.sports_score_rounded
        : Icons.add_location_alt_rounded;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: color.withOpacity(0.4))),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 36, height: 3,
              decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(color: _kText, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  '${widget.point.latitude.toStringAsFixed(6)}, '
                  '${widget.point.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: _kMuted, fontSize: 11, fontFamily: 'monospace'),
                ),
              ]),
            ]),
            const SizedBox(height: 20),
            Text('NAME', style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
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
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color)),
              ),
            ),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('DETECTION RADIUS',
                  style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('$_radius m',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ]),
            Slider(
              value: _radius.toDouble(), min: 10, max: 100, divisions: 18,
              activeColor: color,
              inactiveColor: _kBorder,
              onChanged: (v) {
                setState(() => _radius = v.round());
                widget.onRadiusChanged(v.round());
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kMuted,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: widget.isSaving ? null : widget.onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: widget.isSaving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text('Save $title', style: const TextStyle(fontWeight: FontWeight.w800)),
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  EDIT SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _EditSheet extends StatefulWidget {
  final Map<String, dynamic> cp;
  final TextEditingController nameCtrl;
  final int initialRadius;
  final bool isSaving;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _EditSheet({
    required this.cp, required this.nameCtrl,
    required this.initialRadius, required this.isSaving,
    required this.onRadiusChanged, required this.onCancel, required this.onSave,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late int _radius;

  @override
  void initState() { super.initState(); _radius = widget.initialRadius; }

  @override
  Widget build(BuildContext context) {
    final lat = (widget.cp['lat'] as num).toDouble();
    final lng = (widget.cp['lng'] as num).toDouble();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: const Border(top: BorderSide(color: _kAmber, width: 1.5)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 36, height: 3,
              decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Edit Checkpoint',
                    style: TextStyle(color: _kText, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                    style: const TextStyle(color: _kMuted, fontSize: 11, fontFamily: 'monospace')),
              ]),
            ]),
            const SizedBox(height: 20),
            Text('NAME', style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: widget.nameCtrl,
              autofocus: true,
              style: const TextStyle(color: _kText),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                filled: true, fillColor: _kBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kAmber)),
              ),
            ),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('DETECTION RADIUS',
                  style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _kAmber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('$_radius m',
                    style: const TextStyle(color: _kAmber, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ]),
            Slider(
              value: _radius.toDouble(), min: 10, max: 500, divisions: 49,
              activeColor: _kAmber,
              inactiveColor: _kBorder,
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: widget.isSaving ? null : widget.onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAmber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: widget.isSaving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w800)),
              )),
            ]),
          ],
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
  const _GeoResult({required this.displayName, required this.shortName,
      required this.lat, required this.lng});
}