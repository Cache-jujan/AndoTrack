import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/checkpoint_service.dart';

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

  static const String _darkTileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  // Tapped position (pending)
  LatLng? _pendingPoint;

  // All saved checkpoints
  List<Map<String, dynamic>> _checkpoints = [];

  int _radiusMeters = 20;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCheckpoints();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckpoints() async {
    setState(() => _isLoading = true);
    final data = await CheckpointService.getCheckpoints(widget.raceId);
    setState(() {
      _checkpoints = data.cast<Map<String, dynamic>>();
      _isLoading = false;
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() => _pendingPoint = point);
    _showAddCheckpointSheet(point);
  }

  void _showAddCheckpointSheet(LatLng point) {
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
        onRadiusChanged: (val) => setState(() => _radiusMeters = val),
        onCancel: () {
          setState(() => _pendingPoint = null);
          Navigator.pop(context);
        },
        onSave: () => _saveCheckpoint(point),
      ),
    );
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

    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.pop(context); // close sheet

    if (result['success'] == true) {
      setState(() => _pendingPoint = null);
      await _loadCheckpoints(); // refresh list
      _showSnack('✓ Checkpoint saved!', isError: false);
    } else {
      _showSnack(result['message'] ?? 'Failed to save.', isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? const Color(0xFFFF4D4D) : const Color(0xFF00FF9C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Place Checkpoints',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Race ${widget.raceId}  ·  Tap map to add',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
        ),
        actions: [
          // Checkpoint count badge
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF9C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF00FF9C).withOpacity(0.3),
              ),
            ),
            child: Text(
              '${_checkpoints.length} saved',
              style: const TextStyle(
                color: Color(0xFF00FF9C),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(10.3157, 123.8854),
              initialZoom: 15,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: _darkTileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.andotrack_app',
              ),

              // Radius circles for saved checkpoints
              CircleLayer(
                circles: _checkpoints.map((cp) {
                  return CircleMarker(
                    point: LatLng(
                      (cp['lat'] as num).toDouble(),
                      (cp['lng'] as num).toDouble(),
                    ),
                    radius: (cp['radius_meters'] as num).toDouble(),
                    color: const Color(0xFF00B4FF).withOpacity(0.12),
                    borderColor: const Color(0xFF00B4FF).withOpacity(0.5),
                    borderStrokeWidth: 1.5,
                    useRadiusInMeter: true,
                  );
                }).toList(),
              ),

              // Saved checkpoint markers
              MarkerLayer(
                markers: [
                  // Saved checkpoints
                  ..._checkpoints.asMap().entries.map((entry) {
                    final index = entry.key;
                    final cp = entry.value;
                    return Marker(
                      point: LatLng(
                        (cp['lat'] as num).toDouble(),
                        (cp['lng'] as num).toDouble(),
                      ),
                      width: 48,
                      height: 56,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00B4FF),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00B4FF).withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0D14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF00B4FF).withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              cp['name'] ?? '',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Pending tap marker
                  if (_pendingPoint != null)
                    Marker(
                      point: _pendingPoint!,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFFB800).withOpacity(0.2),
                          border: Border.all(
                            color: const Color(0xFFFFB800),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Color(0xFFFFB800),
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── Instruction banner ───────────────────────────
          if (_checkpoints.isEmpty && !_isLoading)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFB800).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.touch_app_rounded,
                      color: Color(0xFFFFB800),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Tap anywhere on the map to place a checkpoint',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Saved checkpoints list (bottom) ──────────────
          if (_checkpoints.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.07)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'CHECKPOINTS',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Tap map to add more',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: _checkpoints.length,
                        itemBuilder: (context, index) {
                          final cp = _checkpoints[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00B4FF).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF00B4FF).withOpacity(0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00B4FF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    cp['name'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${cp['radius_meters']}m radius',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.3),
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      '${(cp['lat'] as num).toStringAsFixed(4)}, '
                                      '${(cp['lng'] as num).toStringAsFixed(4)}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.2),
                                        fontSize: 9,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Loading overlay ──────────────────────────────
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00FF9C),
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Add checkpoint bottom sheet ───────────────────────────
class _AddCheckpointSheet extends StatefulWidget {
  final LatLng point;
  final TextEditingController nameController;
  final int initialRadius;
  final bool isSaving;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _AddCheckpointSheet({
    required this.point,
    required this.nameController,
    required this.initialRadius,
    required this.isSaving,
    required this.onRadiusChanged,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_AddCheckpointSheet> createState() => _AddCheckpointSheetState();
}

class _AddCheckpointSheetState extends State<_AddCheckpointSheet> {
  late int _radius;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.07)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFFB800).withOpacity(0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: Color(0xFFFFB800),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'New Checkpoint',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.point.latitude.toStringAsFixed(5)}, '
              '${widget.point.longitude.toStringAsFixed(5)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),

            const SizedBox(height: 20),

            // Name field
            Text(
              'CHECKPOINT NAME',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: widget.nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Start Line, KM 5, Finish',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00B4FF)),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Radius slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DETECTION RADIUS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_radius m',
                    style: const TextStyle(
                      color: Color(0xFF00B4FF),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _radius.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              activeColor: const Color(0xFF00B4FF),
              inactiveColor: Colors.white.withOpacity(0.1),
              onChanged: (val) {
                setState(() => _radius = val.round());
                widget.onRadiusChanged(val.round());
              },
            ),

            const SizedBox(height: 8),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white38,
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                      backgroundColor: const Color(0xFF00B4FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: widget.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Save Checkpoint',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}