// MOVED TO: lib/features/checkpoint/screens/checkpoint_placement_screen.dart

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

class CheckpointPlacementScreen extends StatefulWidget {
  final int raceId;
  const CheckpointPlacementScreen({super.key, required this.raceId});

  @override
  State<CheckpointPlacementScreen> createState() =>
      _CheckpointPlacementScreenState();
}

class _CheckpointPlacementScreenState
    extends State<CheckpointPlacementScreen> {
  final MapController _mapController = MapController();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _checkpoints = [];
  bool _isLoading = true;
  bool _isSaving = false;
  int _isDeletingId = -1;
  int _radiusMeters = 20;

  // FIX 2: crosshair placement state
  bool _placingMode = false;

  // FIX 3: search
  List<_GeoResult> _searchResults = [];
  bool _isSearching = false;
  bool _searchFailed = false;
  Timer? _searchDebounce;

  // FIX 4: routing
  List<LatLng> _routePolyline = [];
  bool _isRouting = false;
  bool _routeIsRoadBased = false;

  static const String _tileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const String _nominatim = 'https://nominatim.openstreetmap.org';
  static const LatLng _defaultCenter = LatLng(10.3157, 123.8854);

  @override
  void initState() {
    super.initState();
    _loadCheckpoints();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────

  Future<void> _loadCheckpoints() async {
    setState(() => _isLoading = true);
    final data = await CheckpointService.getCheckpoints(widget.raceId);
    if (!mounted) return;
    setState(() {
      _checkpoints = data.cast<Map<String, dynamic>>();
      _isLoading = false;
    });
    _drawRoute();
  }

  // ── FIX 4: Routing ────────────────────────────────────────

  Future<void> _drawRoute() async {
    if (_checkpoints.length < 2) {
      if (mounted) setState(() { _routePolyline = []; _routeIsRoadBased = false; });
      return;
    }
    if (_isRouting) return;
    setState(() => _isRouting = true);
    try {
      final waypoints = _checkpoints
          .map((cp) => LatLng(
                (cp['lat'] as num).toDouble(),
                (cp['lng'] as num).toDouble(),
              ))
          .toList();
      final pts = await RoutingService.getRoutePolyline(waypoints);
      // OSRM returns many more points than the waypoints;
      // the straight-line fallback returns exactly the waypoints.
      final isRoad = pts.length > waypoints.length;
      if (mounted) setState(() { _routePolyline = pts; _routeIsRoadBased = isRoad; });
    } catch (_) {
      if (mounted) setState(() { _routePolyline = []; _routeIsRoadBased = false; });
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  // ── FIX 2: Crosshair placement ────────────────────────────

  LatLng get _crosshairCoord => _mapController.camera.center;

  void _enterPlacingMode() {
    _searchFocus.unfocus();
    setState(() { _placingMode = true; _searchResults = []; _searchFailed = false; });
  }

  void _cancelPlacingMode() => setState(() => _placingMode = false);

  void _confirmPlacement() {
    final point = _crosshairCoord;
    _nameController.clear();
    _radiusMeters = 20;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCheckpointSheet(
        point: point,
        nameController: _nameController,
        initialRadius: _radiusMeters,
        isSaving: _isSaving,
        onRadiusChanged: (v) => setState(() => _radiusMeters = v),
        onCancel: () { Navigator.pop(context); },
        onSave: () => _saveCheckpoint(point),
      ),
    ).whenComplete(() {
      if (mounted && !_isSaving) setState(() => _placingMode = false);
    });
  }

  Future<void> _saveCheckpoint(LatLng point) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);

    final result = await CheckpointService.createCheckpoint(
      raceId: widget.raceId,
      name: name,
      lat: point.latitude,
      lng: point.longitude,
      radiusMeters: _radiusMeters,
      orderNumber: _checkpoints.length + 1,
    );

    setState(() { _isSaving = false; _placingMode = false; });
    if (!mounted) return;
    Navigator.pop(context);

    if (result['success'] == true) {
      await _loadCheckpoints();
      _showSnack('Checkpoint saved!', isError: false);
    } else {
      _showSnack(result['message'] ?? 'Failed to save.', isError: true);
    }
  }

  Future<void> _deleteCheckpoint(Map<String, dynamic> cp) async {
    final id = cp['id'] as int;
    final name = cp['name'] ?? 'Checkpoint';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D0D14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Delete Checkpoint',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              Text('Delete "$name"? This cannot be undone.',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white38,
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4D4D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeletingId = id);
    final result = await CheckpointService.deleteCheckpoint(id);
    if (!mounted) return;
    setState(() { _isDeletingId = -1; });
    if (result['success'] == true) {
      setState(() => _checkpoints.removeWhere((c) => c['id'] == id));
      _drawRoute();
      _showSnack('Checkpoint deleted.', isError: false);
    } else {
      _showSnack(result['message'] ?? 'Failed to delete.', isError: true);
    }
  }

  // ── FIX 3: Search ─────────────────────────────────────────

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 3) {
      if (mounted) setState(() { _searchResults = []; _searchFailed = false; });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), () => _doSearch(q.trim()));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted) return;
    setState(() { _isSearching = true; _searchFailed = false; });
    try {
      final uri = Uri.parse(
        '$_nominatim/search?q=${Uri.encodeComponent(q)}'
        '&format=json&limit=6&addressdetails=1',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'AndoTrack/1.0 (andotrack@example.com)',
        'Accept-Language': 'en',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        if (list.isEmpty) { setState(() => _searchFailed = true); return; }
        setState(() {
          _searchResults = list.map((item) {
            String short = item['display_name'] as String? ?? '';
            final addr = item['address'] as Map<String, dynamic>?;
            if (addr != null) {
              final parts = <String>[];
              for (final k in ['road','suburb','city','town','village','county','state']) {
                final v = addr[k] as String?;
                if (v != null && v.isNotEmpty) { parts.add(v); if (parts.length >= 2) break; }
              }
              if (parts.isNotEmpty) short = parts.join(', ');
            }
            return _GeoResult(
              displayName: item['display_name'] as String? ?? '',
              shortName: short.isEmpty ? (item['display_name'] as String? ?? '') : short,
              lat: double.parse(item['lat'] as String),
              lng: double.parse(item['lon'] as String),
            );
          }).toList();
        });
      } else {
        setState(() => _searchFailed = true);
        _showSnack('Search error (${res.statusCode}).', isError: true);
      }
    } on TimeoutException {
      if (mounted) { setState(() => _searchFailed = true); _showSnack('Search timed out.', isError: true); }
    } catch (e) {
      if (mounted) { setState(() => _searchFailed = true); _showSnack('Search failed. Check connection.', isError: true); }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectSearchResult(_GeoResult r) {
    _mapController.move(LatLng(r.lat, r.lng), 17);
    setState(() { _searchResults = []; _searchFailed = false; _searchController.clear(); });
    _searchFocus.unfocus();
    _enterPlacingMode();
  }

  void _clearSearch() {
    _searchController.clear();
    if (mounted) setState(() { _searchResults = []; _searchFailed = false; });
    _searchFocus.unfocus();
  }

  Future<void> _locateMe() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) { _showSnack('Location permission denied.', isError: true); return; }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _mapController.move(LatLng(pos.latitude, pos.longitude), 17);
    } catch (_) { _showSnack('Could not get location.', isError: true); }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: isError ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
      backgroundColor: isError ? const Color(0xFFFF4D4D) : const Color(0xFF00FF9C),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showDropdown = _searchResults.isNotEmpty ||
        (_searchFailed && _searchController.text.length >= 3);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Place Checkpoints',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              _placingMode
                  ? 'Move map · tap "Place here" to confirm'
                  : 'Race ${widget.raceId}  ·  Tap + to add',
              style: TextStyle(
                  color: _placingMode ? const Color(0xFFFFB800) : Colors.white.withOpacity(0.4),
                  fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (!_placingMode)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _routeChip()),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 15,
              // No onTap — placement is via crosshair
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.andotrack_app',
              ),

              // FIX 4: Route polyline
              if (_routePolyline.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _routePolyline,
                    color: _routeIsRoadBased
                        ? const Color(0xFF00FF9C).withOpacity(0.6)
                        : const Color(0xFFFFB800).withOpacity(0.5),
                    strokeWidth: 3.5,
                  ),
                ]),

              // Detection-radius circles
              CircleLayer(
                circles: _checkpoints.map((cp) => CircleMarker(
                  point: LatLng((cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
                  radius: (cp['radius_meters'] as num).toDouble(),
                  color: const Color(0xFF00B4FF).withOpacity(0.12),
                  borderColor: const Color(0xFF00B4FF).withOpacity(0.5),
                  borderStrokeWidth: 1.5,
                  useRadiusInMeter: true,
                )).toList(),
              ),

              // FIX 2: height:28 → circle center == geo-coordinate
              MarkerLayer(
                markers: _checkpoints.asMap().entries.map((e) {
                  final i = e.key;
                  final cp = e.value;
                  return Marker(
                    point: LatLng((cp['lat'] as num).toDouble(), (cp['lng'] as num).toDouble()),
                    width: 64,
                    height: 28,
                    alignment: Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B4FF),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFF00B4FF).withOpacity(0.5), blurRadius: 8, spreadRadius: 1)],
                          ),
                          child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
                        ),
                        Positioned(
                          top: 32,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 64),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0D14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF00B4FF).withOpacity(0.3)),
                            ),
                            child: Text(cp['name'] ?? '',
                                style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // ── FIX 2: Crosshair ────────────────────────────────
          if (_placingMode) _crosshair(),

          // ── Search bar (hidden during placing) ────────────────
          if (!_placingMode)
            Positioned(
              top: 12, left: 12, right: 12,
              child: Column(children: [
                _searchBar(),
                if (showDropdown) _searchDropdown(),
              ]),
            ),

          // ── FABs (hidden during placing) ─────────────────────
          if (!_placingMode) ...[
            Positioned(
              right: 12, top: 76,
              child: _Fab(icon: Icons.my_location_rounded, color: const Color(0xFF00FF9C), onTap: _locateMe),
            ),
            Positioned(
              right: 12, bottom: _checkpoints.isEmpty ? 24 : 252,
              child: _Fab(icon: Icons.add_location_alt_rounded, color: const Color(0xFF00B4FF), onTap: _enterPlacingMode, large: true),
            ),
          ],

          // ── Placing mode controls ────────────────────────────
          if (_placingMode) ...[
            Positioned(
              top: 12, left: 12,
              child: GestureDetector(
                onTap: _cancelPlacingMode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                    SizedBox(width: 6),
                    Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: 32, left: 32, right: 32,
              child: GestureDetector(
                onTap: _confirmPlacement,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4FF),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: const Color(0xFF00B4FF).withOpacity(0.4), blurRadius: 16, spreadRadius: 2)],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_rounded, color: Colors.black, size: 20),
                      SizedBox(width: 8),
                      Text('Place checkpoint here',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // ── Empty hint ────────────────────────────────────────
          if (_checkpoints.isEmpty && !_isLoading && !_placingMode && !showDropdown)
            Positioned(
              top: 76, left: 12, right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFFFB800), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Tap the blue + to add your first checkpoint',
                      style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12))),
                ]),
              ),
            ),

          // ── Bottom panel ──────────────────────────────────────
          if (_checkpoints.isNotEmpty && !_placingMode)
            Positioned(bottom: 0, left: 0, right: 0, child: _bottomPanel()),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00FF9C), strokeWidth: 2)),
        ],
      ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────

  Widget _crosshair() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00B4FF).withOpacity(0.4), width: 1.5),
            ),
          ),
          Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00B4FF))),
          Container(width: 36, height: 1.5, color: const Color(0xFF00B4FF).withOpacity(0.7)),
          Container(width: 1.5, height: 36, color: const Color(0xFF00B4FF).withOpacity(0.7)),
        ],
      ),
    );
  }

  Widget _routeChip() {
    if (_isRouting) {
      return _chip(
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00FF9C))),
          SizedBox(width: 6),
          Text('Routing…', style: TextStyle(color: Color(0xFF00FF9C), fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        color: const Color(0xFF00FF9C),
      );
    }
    if (_routePolyline.length >= 2) {
      final c = _routeIsRoadBased ? const Color(0xFF00FF9C) : const Color(0xFFFFB800);
      return _chip(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_routeIsRoadBased ? Icons.alt_route_rounded : Icons.show_chart_rounded, color: c, size: 13),
          const SizedBox(width: 5),
          Text(_routeIsRoadBased ? 'ROAD' : 'STRAIGHT', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        ]),
        color: c,
      );
    }
    return _chip(
      child: Text('${_checkpoints.length} saved', style: const TextStyle(color: Color(0xFF00FF9C), fontSize: 12, fontWeight: FontWeight.bold)),
      color: const Color(0xFF00FF9C),
    );
  }

  Widget _chip({required Widget child, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: child,
    );
  }

  Widget _searchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        const Icon(Icons.search_rounded, color: Color(0xFF444460), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search location...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_isSearching)
          const Padding(padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FF9C))))
        else if (_searchController.text.isNotEmpty)
          GestureDetector(
            onTap: _clearSearch,
            child: Padding(padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: 18)),
          )
        else
          const SizedBox(width: 12),
      ]),
    );
  }

  Widget _searchDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
      ),
      child: _searchFailed && _searchResults.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(Icons.search_off_rounded, color: Colors.white.withOpacity(0.25), size: 16),
                const SizedBox(width: 10),
                Text('No results. Try a different query.', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
              ]),
            )
          : Column(
              children: _searchResults.asMap().entries.map((e) {
                final i = e.key; final r = e.value;
                return GestureDetector(
                  onTap: () => _selectSearchResult(r),
                  child: Container(
                    decoration: BoxDecoration(
                      border: i < _searchResults.length - 1
                          ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))) : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(children: [
                      const Icon(Icons.place_outlined, color: Color(0xFF444460), size: 16),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.shortName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                          Text(r.displayName, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10), overflow: TextOverflow.ellipsis, maxLines: 1),
                        ],
                      )),
                      Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.2), size: 16),
                    ]),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _bottomPanel() {
    final km = _estimateRouteKm();
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 3,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Text('CHECKPOINTS', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (km > 0)
                Text('~${km.toStringAsFixed(1)} km', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
              const SizedBox(width: 10),
              // FIX 4: Re-route button
              GestureDetector(
                onTap: _isRouting ? null : _drawRoute,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF9C).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00FF9C).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _isRouting
                        ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00FF9C)))
                        : const Icon(Icons.alt_route_rounded, color: Color(0xFF00FF9C), size: 13),
                    const SizedBox(width: 5),
                    Text(_isRouting ? 'Routing…' : 'Re-route',
                        style: const TextStyle(color: Color(0xFF00FF9C), fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ]),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: _checkpoints.length,
              itemBuilder: (context, i) {
                final cp = _checkpoints[i];
                final id = cp['id'] as int;
                final isDeleting = _isDeletingId == id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4FF).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00B4FF).withOpacity(0.15)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(color: Color(0xFF00B4FF), shape: BoxShape.circle),
                      child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(cp['name'] ?? '', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
                      child: Text('${cp['radius_meters']}m', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    isDeleting
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4D4D)))
                        : GestureDetector(
                            onTap: () => _deleteCheckpoint(cp),
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4D4D).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFF4D4D).withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.delete_outline, color: Color(0xFFFF4D4D), size: 15),
                            ),
                          ),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _estimateRouteKm() {
    if (_routePolyline.length < 2) return 0;
    double total = 0;
    const r = 6371.0;
    for (int i = 0; i < _routePolyline.length - 1; i++) {
      final a = _routePolyline[i]; final b = _routePolyline[i + 1];
      final dLat = (b.latitude - a.latitude) * math.pi / 180;
      final dLng = (b.longitude - a.longitude) * math.pi / 180;
      final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(a.latitude * math.pi / 180) * math.cos(b.latitude * math.pi / 180) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
      total += 2 * r * math.asin(math.sqrt(h));
    }
    return total;
  }
}

// ── Small FAB ──────────────────────────────────────────────────────────────────
class _Fab extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool large;
  const _Fab({required this.icon, required this.color, required this.onTap, this.large = false});

  @override
  Widget build(BuildContext context) {
    final sz = large ? 52.0 : 44.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: sz, height: sz,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)],
        ),
        child: Icon(icon, color: color, size: large ? 26 : 20),
      ),
    );
  }
}

// ── Geocoding result ───────────────────────────────────────────────────────────
class _GeoResult {
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;
  const _GeoResult({required this.displayName, required this.shortName, required this.lat, required this.lng});
}

// ── Add checkpoint bottom sheet ────────────────────────────────────────────────
class _AddCheckpointSheet extends StatefulWidget {
  final LatLng point;
  final TextEditingController nameController;
  final int initialRadius;
  final bool isSaving;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _AddCheckpointSheet({
    required this.point, required this.nameController,
    required this.initialRadius, required this.isSaving,
    required this.onRadiusChanged, required this.onCancel, required this.onSave,
  });

  @override
  State<_AddCheckpointSheet> createState() => _AddCheckpointSheetState();
}

class _AddCheckpointSheetState extends State<_AddCheckpointSheet> {
  late int _radius;

  @override
  void initState() { super.initState(); _radius = widget.initialRadius; }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 3,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3)),
                ),
                child: const Icon(Icons.flag_rounded, color: Color(0xFFFFB800), size: 18)),
              const SizedBox(width: 12),
              const Text('New Checkpoint', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            Text(
              '${widget.point.latitude.toStringAsFixed(6)}, ${widget.point.longitude.toStringAsFixed(6)}',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 20),
            Text('CHECKPOINT NAME', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: widget.nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'e.g. Start Line, KM 5, Finish',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00B4FF))),
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('DETECTION RADIUS', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF00B4FF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('$_radius m', style: const TextStyle(color: Color(0xFF00B4FF), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ]),
            Slider(
              value: _radius.toDouble(), min: 10, max: 100, divisions: 18,
              activeColor: const Color(0xFF00B4FF),
              inactiveColor: Colors.white.withOpacity(0.1),
              onChanged: (v) { setState(() => _radius = v.round()); widget.onRadiusChanged(v.round()); },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white38,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2,
                child: ElevatedButton(
                  onPressed: widget.isSaving ? null : widget.onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: widget.isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Save Checkpoint', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
