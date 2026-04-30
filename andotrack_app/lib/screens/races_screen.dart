// ============================================================
// RacesScreen — Organizer view
// ─────────────────────────────────────────────────────────────
// • Lists all races with full metadata (location, date, slots)
// • Create Race sheet with all DB fields (name, distance,
//   category, description, location, sponsors, max_participants,
//   scheduled_start, registration_fee, status)
// • Start / Stop race lifecycle actions
// • Status pill: upcoming | registration_open | race_day |
//                active | finished
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class RacesScreen extends StatefulWidget {
  /// Called when the organizer taps a race card to switch the active race.
  final void Function(int id, String name, String status)? onRaceSelected;

  const RacesScreen({super.key, this.onRaceSelected});

  @override
  State<RacesScreen> createState() => _RacesScreenState();
}

class _RacesScreenState extends State<RacesScreen> {
  List<Map<String, dynamic>> _races = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final races = await ApiService.getRaces();
      setState(() {
        _races = races;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Race lifecycle ─────────────────────────────────────────────────────────

  Future<void> _startRace(int raceId, String raceName) async {
    if (!await _confirm(
      'Start "$raceName"?',
      'Runners will be able to join and GPS tracking will begin.',
      confirmText: 'Start Race',
      confirmColor: const Color(0xFF00FF9C),
    )) return;
    try {
      await ApiService.startRace(raceId);
      _showSnack('Race started!', isError: false);
      _load();
    } catch (e) {
      _showSnack('Failed to start: $e', isError: true);
    }
  }

  Future<void> _stopRace(int raceId, String raceName) async {
    if (!await _confirm(
      'Stop "$raceName"?',
      'This will end the race and freeze the leaderboard. Cannot be undone.',
      confirmText: 'Stop Race',
      confirmColor: const Color(0xFFFF4D4D),
    )) return;
    try {
      await ApiService.stopRace(raceId);
      _showSnack('Race stopped.', isError: false);
      _load();
    } catch (e) {
      _showSnack('Failed to stop: $e', isError: true);
    }
  }

  // ── Create Race ───────────────────────────────────────────────────────────

  void _openCreateRace() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateRaceSheet(
        onCreated: () {
          Navigator.pop(context);
          _load();
          _showSnack('Race created!', isError: false);
        },
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _confirm(
    String title,
    String message, {
    required String confirmText,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
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
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 8),
              Text(message,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5), fontSize: 13)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side:
                            BorderSide(color: Colors.white.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(confirmText,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.w600)),
      backgroundColor:
          isError ? const Color(0xFFFF4D4D) : const Color(0xFF00FF9C),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── Status styling ────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF00FF9C);
      case 'finished':
        return const Color(0xFF666680);
      case 'registration_open':
        return const Color(0xFF00B4FF);
      case 'race_day':
        return const Color(0xFFFFB800);
      default: // upcoming
        return const Color(0xFF8B5CF6);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.play_circle_outline_rounded;
      case 'finished':
        return Icons.flag_rounded;
      case 'registration_open':
        return Icons.how_to_reg_rounded;
      case 'race_day':
        return Icons.today_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'registration_open':
        return 'REG OPEN';
      case 'race_day':
        return 'RACE DAY';
      default:
        return status.toUpperCase();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Races',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        systemOverlayStyle:
            const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFF00FF9C),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00FF9C),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label:
            const Text('Create Race', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _openCreateRace,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00FF9C), strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFFF4D4D), size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.white38),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again',
                            style: TextStyle(color: Color(0xFF00FF9C))),
                      ),
                    ],
                  ),
                )
              : _races.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 64,
                              color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 16),
                          Text('No races yet',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('Tap + Create Race to get started',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.2),
                                  fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF00FF9C),
                      backgroundColor: const Color(0xFF0D0D14),
                      onRefresh: _load,
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _races.length,
                        itemBuilder: (context, index) {
                          final race = _races[index];
                          final raceId = race['id'] as int;
                          final name =
                              race['name']?.toString() ?? 'Race #$raceId';
                          final status =
                              race['status']?.toString() ?? 'upcoming';
                          final distance = race['distance_km'];
                          final category = race['category']?.toString();
                          final location = race['location']?.toString();
                          final scheduled =
                              race['scheduled_start']?.toString();
                          final maxP = race['max_participants'];
                          final participantCount =
                              race['participant_count'];
                          final fee = race['registration_fee'];
                          final statusColor = _statusColor(status);

                          return GestureDetector(
                            onTap: widget.onRaceSelected != null
                                ? () => widget.onRaceSelected!(
                                    raceId, name, status)
                                : null,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.07)),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // ── Header row ──────────────────────────
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Status icon
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: statusColor
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: statusColor
                                                    .withOpacity(0.3)),
                                          ),
                                          child: Icon(
                                            _statusIcon(status),
                                            color: statusColor,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Name + status badge
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(name,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15)),
                                              const SizedBox(height: 5),
                                              Wrap(
                                                spacing: 6,
                                                children: [
                                                  // Status pill
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                    decoration:
                                                        BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(6),
                                                    ),
                                                    child: Text(
                                                        _statusLabel(status),
                                                        style: TextStyle(
                                                            color:
                                                                statusColor,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold,
                                                            letterSpacing:
                                                                0.8)),
                                                  ),
                                                  // Category pill
                                                  if (category != null)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 7,
                                                          vertical: 2),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: Colors.white
                                                            .withOpacity(
                                                                0.05),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                      ),
                                                      child: Text(
                                                          category,
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.4),
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Chevron if tappable
                                        if (widget.onRaceSelected != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 4),
                                            child: Icon(
                                              Icons
                                                  .arrow_forward_ios_rounded,
                                              color: Colors.white
                                                  .withOpacity(0.2),
                                              size: 14,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // ── Meta chips ───────────────────────────
                                  if (location != null ||
                                      scheduled != null ||
                                      maxP != null ||
                                      distance != null) ...[
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (distance != null)
                                            _MetaChip(
                                              icon: Icons.straighten_rounded,
                                              label:
                                                  '${(distance as num).toStringAsFixed(1)} km',
                                            ),
                                          if (location != null)
                                            _MetaChip(
                                              icon: Icons.place_outlined,
                                              label: location,
                                            ),
                                          if (scheduled != null)
                                            _MetaChip(
                                              icon: Icons
                                                  .calendar_today_outlined,
                                              label:
                                                  _formatDate(scheduled),
                                            ),
                                          if (maxP != null)
                                            _MetaChip(
                                              icon: Icons.group_outlined,
                                              label:
                                                  '${participantCount ?? 0}/$maxP runners',
                                            ),
                                          if (fee != null &&
                                              (fee as num) > 0)
                                            _MetaChip(
                                              icon: Icons
                                                  .payments_outlined,
                                              label:
                                                  '₱${(fee as num).toStringAsFixed(0)}',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 12),

                                  // ── Action buttons ───────────────────────
                                  if (status != 'finished')
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 12),
                                      child: Row(
                                        children: [
                                          if (status == 'upcoming' ||
                                              status ==
                                                  'registration_open' ||
                                              status == 'race_day')
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () =>
                                                    _startRace(
                                                        raceId, name),
                                                icon: const Icon(
                                                    Icons.play_arrow_rounded,
                                                    size: 18),
                                                label: const Text(
                                                    'Start Race'),
                                                style: ElevatedButton
                                                    .styleFrom(
                                                  backgroundColor:
                                                      const Color(
                                                          0xFF00FF9C),
                                                  foregroundColor:
                                                      Colors.black,
                                                  shape:
                                                      RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      10)),
                                                  textStyle: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          if (status == 'active')
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _stopRace(raceId, name),
                                                icon: const Icon(
                                                    Icons.stop_rounded,
                                                    size: 18),
                                                label: const Text(
                                                    'Stop Race'),
                                                style: OutlinedButton
                                                    .styleFrom(
                                                  foregroundColor:
                                                      const Color(
                                                          0xFFFF4D4D),
                                                  side: const BorderSide(
                                                      color: Color(
                                                          0xFFFF4D4D)),
                                                  shape:
                                                      RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      10)),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                  else
                                    // Finished — show "View Results" hint
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 12),
                                      child: Text('Race completed',
                                          style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.25),
                                              fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month - 1]} · $h:$m';
    } catch (_) {
      return raw;
    }
  }
}

// ── Meta chip ─────────────────────────────────────────────────────────────────
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFF444460)),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF666680), fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Create Race bottom sheet ──────────────────────────────────────────────────
class _CreateRaceSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateRaceSheet({required this.onCreated});

  @override
  State<_CreateRaceSheet> createState() => _CreateRaceSheetState();
}

class _CreateRaceSheetState extends State<_CreateRaceSheet> {
  final _nameCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _sponsorsCtrl = TextEditingController();
  final _maxPCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();

  String _category = '10K';
  DateTime? _scheduledStart;
  bool _isSaving = false;
  String? _validationError;

  static const _categories = ['5K', '10K', '21K', '42K', 'Custom'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _distanceCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _sponsorsCtrl.dispose();
    _maxPCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00FF9C),
            surface: Color(0xFF0D0D14),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00FF9C),
            surface: Color(0xFF0D0D14),
          ),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null) return;
    setState(() {
      _scheduledStart = DateTime(
          picked.year, picked.month, picked.day,
          pickedTime.hour, pickedTime.minute);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final dist = double.tryParse(_distanceCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _validationError = 'Race name is required.');
      return;
    }
    if (dist == null || dist <= 0) {
      setState(() => _validationError = 'Enter a valid distance (km).');
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    try {
      await ApiService.createRace({
        'name': name,
        'distance_km': dist,
        'category': _category,
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'location': _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        'sponsors': _sponsorsCtrl.text.trim().isEmpty
            ? null
            : _sponsorsCtrl.text.trim(),
        'max_participants': _maxPCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(_maxPCtrl.text.trim()),
        'scheduled_start': _scheduledStart?.toIso8601String(),
        'registration_fee':
            double.tryParse(_feeCtrl.text.trim()) ?? 0.0,
        'status': 'upcoming',
      });
      widget.onCreated();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _validationError = 'Failed to create race: $e';
      });
    }
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    TextInputType type = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF00FF9C)),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF9C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF00FF9C).withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Color(0xFF00FF9C), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create New Race',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),

            // Form fields
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Race Name
                  _SheetField(
                    label: 'RACE NAME *',
                    child: _buildTextField(
                        _nameCtrl, 'e.g. Cebu City Marathon 2025'),
                  ),
                  const SizedBox(height: 16),

                  // Distance + Category
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SheetField(
                          label: 'DISTANCE (km) *',
                          child: _buildTextField(_distanceCtrl, 'e.g. 10',
                              type: TextInputType.number),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetField(
                          label: 'CATEGORY',
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.1)),
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _category,
                                dropdownColor: const Color(0xFF0D0D14),
                                style: const TextStyle(color: Colors.white),
                                items: _categories
                                    .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14))))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _category = v!),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Location
                  _SheetField(
                    label: 'START LOCATION',
                    child: _buildTextField(
                        _locationCtrl, 'e.g. Cebu City, PH'),
                  ),
                  const SizedBox(height: 16),

                  // Date & Time
                  _SheetField(
                    label: 'RACE DATE & TIME',
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                color: Color(0xFF444460), size: 16),
                            const SizedBox(width: 10),
                            Text(
                              _scheduledStart == null
                                  ? 'Tap to select date & time'
                                  : _formatDateTime(_scheduledStart!),
                              style: TextStyle(
                                color: _scheduledStart == null
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Max participants + Fee
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SheetField(
                          label: 'MAX PARTICIPANTS',
                          child: _buildTextField(_maxPCtrl, 'e.g. 500',
                              type: TextInputType.number),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetField(
                          label: 'REGISTRATION FEE (₱)',
                          child: _buildTextField(_feeCtrl, '0.00',
                              type: const TextInputType.numberWithOptions(
                                  decimal: true)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Sponsors
                  _SheetField(
                    label: 'SPONSORS',
                    child: _buildTextField(
                        _sponsorsCtrl, 'e.g. Brand A, Brand B'),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _SheetField(
                    label: 'DESCRIPTION',
                    child: _buildTextField(
                      _descCtrl,
                      'Optional description about this race...',
                      maxLines: 3,
                    ),
                  ),

                  // Validation error
                  if (_validationError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D4D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                const Color(0xFFFF4D4D).withOpacity(0.3)),
                      ),
                      child: Text(_validationError!,
                          style: const TextStyle(
                              color: Color(0xFFFF4D4D), fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white38,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.1)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF9C),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black))
                              : const Text('Create Race',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet field label wrapper ─────────────────────────────────────────────────
class _SheetField extends StatelessWidget {
  final String label;
  final Widget child;
  const _SheetField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}