import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:andotrack_app/core/services/api_service.dart';

class RacesScreen extends StatefulWidget {
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
    setState(() { _isLoading = true; _error = null; });
    try {
      final races = await ApiService.getRaces();
      setState(() { _races = races; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // ── Parse categories from JSON string or plain string ─────────────────────

  /// Safely parse the `category` field which may be:
  ///   '["5K","10K"]'  → ["5K", "10K"]
  ///   '5K'            → ["5K"]          (legacy single value)
  ///   null            → []
  static List<String> parseCategories(dynamic raw) {
    if (raw == null) return [];
    final s = raw.toString().trim();
    if (s.startsWith('[')) {
      try {
        return (jsonDecode(s) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return s.isEmpty ? [] : [s];
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

  // ── Create / Duplicate Race ────────────────────────────────────────────────

  void _openCreateRace({Map<String, dynamic>? prefill}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateRaceSheet(
        prefill: prefill,
        onCreated: () {
          Navigator.pop(context);
          _load();
          _showSnack(
            prefill != null ? 'Race duplicated!' : 'Race created!',
            isError: false,
          );
        },
      ),
    );
  }

  void _duplicateRace(Map<String, dynamic> race) {
    _openCreateRace(prefill: {
      ...race,
      'name': '${race['name'] ?? 'Race'} (Copy)',
      'scheduled_start': null, // must pick a new date
    });
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
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
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
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      backgroundColor:
          isError ? const Color(0xFFFF4D4D) : const Color(0xFF00FF9C),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ── Status styling ─────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return const Color(0xFF00FF9C);
      case 'finished': return const Color(0xFF666680);
      case 'registration_open': return const Color(0xFF00B4FF);
      case 'race_day': return const Color(0xFFFFB800);
      default: return const Color(0xFF8B5CF6);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'active': return Icons.play_circle_outline_rounded;
      case 'finished': return Icons.flag_rounded;
      case 'registration_open': return Icons.how_to_reg_rounded;
      case 'race_day': return Icons.today_rounded;
      default: return Icons.schedule_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'registration_open': return 'REG OPEN';
      case 'race_day': return 'RACE DAY';
      default: return status.toUpperCase();
    }
  }

  // ── Category badge colour (cycles through palette) ────────────────────────

  static const _catColors = [
    Color(0xFF00FF9C),
    Color(0xFF00B4FF),
    Color(0xFFFFB800),
    Color(0xFFFF6B6B),
    Color(0xFFB066FF),
  ];

  Color _catColor(int index) => _catColors[index % _catColors.length];

  // ── Build ──────────────────────────────────────────────────────────────────

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
        label: const Text('Create Race',
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openCreateRace(),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _races.length,
                        itemBuilder: (context, index) {
                          final race = _races[index];
                          final raceId = race['id'] as int;
                          final name =
                              race['name']?.toString() ?? 'Race #$raceId';
                          final status =
                              race['status']?.toString() ?? 'upcoming';
                          final distance = race['distance_km'];
                          final categories = parseCategories(race['category']);
                          final location = race['location']?.toString();
                          final scheduled =
                              race['scheduled_start']?.toString();
                          final maxP = race['max_participants'];
                          final participantCount = race['participant_count'];
                          final fee = race['registration_fee'];
                          final statusColor = _statusColor(status);

                          return GestureDetector(
                            onTap: widget.onRaceSelected != null
                                ? () => widget.onRaceSelected!(
                                    raceId, name, status)
                                : null,
                            onLongPress: () =>
                                _showRaceContextMenu(context, race),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.07)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Header row ─────────────────────────────
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
                                            color:
                                                statusColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: statusColor
                                                    .withOpacity(0.3)),
                                          ),
                                          child: Icon(_statusIcon(status),
                                              color: statusColor, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        // Name + badges
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
                                                runSpacing: 4,
                                                children: [
                                                  // Status badge
                                                  _Badge(
                                                    label: _statusLabel(status),
                                                    color: statusColor,
                                                  ),
                                                  // Category badges — one per category
                                                  ...categories
                                                      .asMap()
                                                      .entries
                                                      .map((e) => _Badge(
                                                            label: e.value,
                                                            color: _catColor(
                                                                e.key),
                                                            subtle: true,
                                                          )),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Duplicate icon
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded,
                                              size: 16),
                                          tooltip: 'Duplicate race',
                                          color: const Color(0xFF444460),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _duplicateRace(race),
                                        ),
                                        if (widget.onRaceSelected != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 4),
                                            child: Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              color: Colors.white
                                                  .withOpacity(0.2),
                                              size: 14,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // ── Meta chips ──────────────────────────────
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
                                              icon:
                                                  Icons.calendar_today_outlined,
                                              label: _formatDate(scheduled),
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
                                              icon: Icons.payments_outlined,
                                              label:
                                                  '₱${(fee as num).toStringAsFixed(0)}',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 12),

                                  // ── Action buttons ──────────────────────────
                                  if (status != 'finished')
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 12),
                                      child: Row(
                                        children: [
                                          if (status == 'upcoming' ||
                                              status == 'registration_open' ||
                                              status == 'race_day')
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () =>
                                                    _startRace(raceId, name),
                                                icon: const Icon(
                                                    Icons.play_arrow_rounded,
                                                    size: 18),
                                                label:
                                                    const Text('Start Race'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFF00FF9C),
                                                  foregroundColor: Colors.black,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
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
                                                label:
                                                    const Text('Stop Race'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      const Color(0xFFFF4D4D),
                                                  side: const BorderSide(
                                                      color:
                                                          Color(0xFFFF4D4D)),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10)),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                  else
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

  /// Long-press context menu for a race card.
  void _showRaceContextMenu(
      BuildContext context, Map<String, dynamic> race) {
    final name = race['name']?.toString() ?? 'Race';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D14),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(name,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ),
            const Divider(color: Color(0xFF1E1E30), height: 1),
            ListTile(
              leading: const Icon(Icons.copy_rounded,
                  color: Color(0xFF00B4FF), size: 20),
              title: const Text('Duplicate Race',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text('Pre-fills all fields, clear the date',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _duplicateRace(race);
              },
            ),
            const SizedBox(height: 8),
          ],
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

// ── _Badge ─────────────────────────────────────────────────────────────────────
/// Compact coloured label used for status and category tags.
/// [subtle] = category style (lower opacity fill, text same colour)
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool subtle;
  const _Badge({required this.label, required this.color, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: subtle ? color.withOpacity(0.08) : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: subtle
            ? Border.all(color: color.withOpacity(0.25))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: subtle ? color.withOpacity(0.8) : color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── _MetaChip ─────────────────────────────────────────────────────────────────
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
              style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Create Race bottom sheet ───────────────────────────────────────────────────
class _CreateRaceSheet extends StatefulWidget {
  final VoidCallback onCreated;
  final Map<String, dynamic>? prefill;
  const _CreateRaceSheet({required this.onCreated, this.prefill});

  @override
  State<_CreateRaceSheet> createState() => _CreateRaceSheetState();
}

class _CreateRaceSheetState extends State<_CreateRaceSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _distanceCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _sponsorsCtrl;
  late final TextEditingController _maxPCtrl;
  late final TextEditingController _feeCtrl;

  // Multi-select categories — replaces single _category string
  late Set<String> _selectedCategories;
  DateTime? _scheduledStart;
  bool _isSaving = false;
  String? _validationError;

  bool get _isDuplicate => widget.prefill != null;

  static const _allCategories = ['3K', '5K', '10K', '16K', '21K', '42K', 'Fun Run', 'Custom'];

  // Colour palette for category chips (matches race card badges)
  static const _chipColors = [
    Color(0xFF00FF9C),
    Color(0xFF00B4FF),
    Color(0xFFFFB800),
    Color(0xFFFF6B6B),
    Color(0xFFB066FF),
    Color(0xFF00E5FF),
    Color(0xFFFF9500),
    Color(0xFFFF3CAC),
  ];

  Color _chipColor(String cat) {
    final idx = _allCategories.indexOf(cat);
    return _chipColors[(idx < 0 ? 0 : idx) % _chipColors.length];
  }

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;

    _nameCtrl = TextEditingController(text: p?['name']?.toString() ?? '');
    _distanceCtrl = TextEditingController(
        text: p?['distance_km'] != null
            ? (p!['distance_km'] as num).toString()
            : '');
    _locationCtrl =
        TextEditingController(text: p?['location']?.toString() ?? '');
    _descCtrl =
        TextEditingController(text: p?['description']?.toString() ?? '');
    _sponsorsCtrl =
        TextEditingController(text: p?['sponsors']?.toString() ?? '');
    _maxPCtrl = TextEditingController(
        text: p?['max_participants'] != null
            ? p!['max_participants'].toString()
            : '');
    _feeCtrl = TextEditingController(
        text: p?['registration_fee'] != null &&
                (p!['registration_fee'] as num) > 0
            ? (p['registration_fee'] as num).toStringAsFixed(0)
            : '');

    // Parse categories from prefill (supports both JSON list and plain string)
    _selectedCategories = Set<String>.from(
      _RacesScreenState.parseCategories(p?['category']),
    );

    // Intentionally not pre-filling date — duplicate must set a new one.
    _scheduledStart = null;
  }

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
    if (picked == null || !mounted) return;
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
      _scheduledStart = DateTime(picked.year, picked.month, picked.day,
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
    if (_selectedCategories.isEmpty) {
      setState(() => _validationError = 'Select at least one category.');
      return;
    }

    setState(() { _isSaving = true; _validationError = null; });

    try {
      // Send categories as JSON array string → backend stores in `category` column
      final categoriesJson = jsonEncode(_selectedCategories.toList());
      await ApiService.createRace({
        'name': name,
        'distance_km': dist,
        'category': categoriesJson,
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
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
        'registration_fee': double.tryParse(_feeCtrl.text.trim()) ?? 0.0,
        'status': 'upcoming',
      });
      widget.onCreated();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _validationError = 'Failed to save race: $e';
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
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
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
                      color: (_isDuplicate
                              ? const Color(0xFF00B4FF)
                              : const Color(0xFF00FF9C))
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: (_isDuplicate
                                  ? const Color(0xFF00B4FF)
                                  : const Color(0xFF00FF9C))
                              .withOpacity(0.3)),
                    ),
                    child: Icon(
                      _isDuplicate ? Icons.copy_rounded : Icons.add_rounded,
                      color: _isDuplicate
                          ? const Color(0xFF00B4FF)
                          : const Color(0xFF00FF9C),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isDuplicate ? 'Duplicate Race' : 'Create Race',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        if (_isDuplicate)
                          const Text('All fields copied · set a new date',
                              style: TextStyle(
                                  color: Color(0xFF00B4FF),
                                  fontSize: 11)),
                      ],
                    ),
                  ),
                  if (_isDuplicate)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4FF).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF00B4FF).withOpacity(0.3)),
                      ),
                      child: const Text('COPY',
                          style: TextStyle(
                              color: Color(0xFF00B4FF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 4),
            Divider(color: Colors.white.withOpacity(0.06)),

            // Form body
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _SheetField(
                    label: 'RACE NAME',
                    child: _buildTextField(_nameCtrl, 'e.g. Cebu City Marathon 2025'),
                  ),
                  const SizedBox(height: 16),

                  // ── CATEGORIES — multi-select chips ──────────────────────
                  _SheetField(
                    label: 'CATEGORIES  (select all that apply)',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _allCategories.map((cat) {
                            final selected = _selectedCategories.contains(cat);
                            final color = _chipColor(cat);
                            return GestureDetector(
                              onTap: () => setState(() {
                                if (selected) {
                                  _selectedCategories.remove(cat);
                                } else {
                                  _selectedCategories.add(cat);
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? color.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? color.withOpacity(0.6)
                                        : Colors.white.withOpacity(0.1),
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected) ...[
                                      Icon(Icons.check_rounded,
                                          size: 12, color: color),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      cat,
                                      style: TextStyle(
                                        color: selected
                                            ? color
                                            : Colors.white.withOpacity(0.4),
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_selectedCategories.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Tap to select categories for this event',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                                fontSize: 11),
                          ),
                        ] else ...[
                          const SizedBox(height: 6),
                          Text(
                            '${_selectedCategories.length} selected: ${_selectedCategories.join(", ")}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Distance ──────────────────────────────────────────────
                  _SheetField(
                    label: 'TOTAL DISTANCE (km)',
                    child: _buildTextField(
                      _distanceCtrl,
                      'e.g. 21.1',
                      type: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SheetField(
                    label: 'START LOCATION',
                    child: _buildTextField(
                        _locationCtrl, 'e.g. Cebu City, PH'),
                  ),
                  const SizedBox(height: 16),

                  // ── Date — warning border when in duplicate mode ───────────
                  _SheetField(
                    label: _isDuplicate
                        ? 'RACE DATE & TIME  ⚠ REQUIRED'
                        : 'RACE DATE & TIME',
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isDuplicate && _scheduledStart == null
                                ? const Color(0xFFFFB800).withOpacity(0.5)
                                : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              color: _isDuplicate && _scheduledStart == null
                                  ? const Color(0xFFFFB800)
                                  : const Color(0xFF444460),
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _scheduledStart == null
                                  ? _isDuplicate
                                      ? 'Tap to set new date & time'
                                      : 'Tap to select date & time'
                                  : _formatDateTime(_scheduledStart!),
                              style: TextStyle(
                                color: _scheduledStart == null
                                    ? _isDuplicate
                                        ? const Color(0xFFFFB800)
                                        : Colors.white.withOpacity(0.2)
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

                  _SheetField(
                    label: 'SPONSORS',
                    child: _buildTextField(
                        _sponsorsCtrl, 'e.g. Brand A, Brand B'),
                  ),
                  const SizedBox(height: 16),

                  _SheetField(
                    label: 'DESCRIPTION',
                    child: _buildTextField(
                      _descCtrl,
                      'Optional description about this race...',
                      maxLines: 3,
                    ),
                  ),

                  if (_validationError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D4D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFFF4D4D).withOpacity(0.3)),
                      ),
                      child: Text(_validationError!,
                          style: const TextStyle(
                              color: Color(0xFFFF4D4D), fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _isSaving ? null : () => Navigator.pop(context),
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
                            backgroundColor: _isDuplicate
                                ? const Color(0xFF00B4FF)
                                : const Color(0xFF00FF9C),
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
                                      strokeWidth: 2, color: Colors.black))
                              : Text(
                                  _isDuplicate
                                      ? 'Save Duplicate'
                                      : 'Create Race',
                                  style: const TextStyle(
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

// ── Sheet field label wrapper ──────────────────────────────────────────────────
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
