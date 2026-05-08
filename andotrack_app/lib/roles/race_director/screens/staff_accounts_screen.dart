// lib/roles/race_director/screens/staff_accounts_screen.dart
//
// WEB-ONLY screen for Race Director to create and manage staff accounts.
//
// Staff are race-scoped (StaffAssignment model). Director picks a race from the
// selector at the top, then manages that race's staff.
//
// Backend endpoints used:
//   GET  /races/{race_id}/staff
//   POST /races/{race_id}/staff?name=&email=&role=   (backend generates password)
//   PATCH /races/{race_id}/staff/{staff_id}/deactivate

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:andotrack_app/core/services/api_service.dart';

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

// ─────────────────────────────────────────────────────────────────────────────

class StaffAccountsScreen extends StatefulWidget {
  const StaffAccountsScreen({super.key});

  @override
  State<StaffAccountsScreen> createState() => _StaffAccountsScreenState();
}

class _StaffAccountsScreenState extends State<StaffAccountsScreen> {
  // Races
  List<Map<String, dynamic>> _races      = [];
  bool                       _racesLoading = true;
  int?                       _selectedRaceId;
  String?                    _selectedRaceName;

  // Staff for selected race
  List<Map<String, dynamic>> _accounts = [];
  bool    _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaces();
  }

  Future<void> _loadRaces() async {
    setState(() { _racesLoading = true; _error = null; });
    try {
      final races = await ApiService.getRaces();
      if (!mounted) return;
      setState(() {
        _races        = races;
        _racesLoading = false;
        if (races.isNotEmpty) {
          _selectedRaceId   = (races.first['id'] as num).toInt();
          _selectedRaceName = races.first['name']?.toString();
        } else {
          _loading = false;
        }
      });
      if (races.isNotEmpty) _load();
    } catch (e) {
      if (mounted) {
        setState(() { _racesLoading = false; _loading = false;
          _error = 'Failed to load races.'; });
      }
    }
  }

  Future<void> _load() async {
    if (_selectedRaceId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final accounts = await ApiService.getStaffAccounts(_selectedRaceId!);
      if (mounted) setState(() { _accounts = accounts; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load staff.'; _loading = false; });
    }
  }

  void _selectRace(int raceId) {
    final race = _races.firstWhere((r) => (r['id'] as num).toInt() == raceId);
    setState(() {
      _selectedRaceId   = raceId;
      _selectedRaceName = race['name']?.toString();
      _accounts         = [];
    });
    _load();
  }

  void _openCreateDialog() {
    if (_selectedRaceId == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateStaffDialog(
        raceId: _selectedRaceId!,
        onCreated: (name, tempPassword) {
          _load();
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (_) => _TempPasswordDialog(
              name:         name,
              tempPassword: tempPassword,
            ),
          );
        },
      ),
    );
  }

  void _openStaffOptions(Map<String, dynamic> account) {
    final isActive = account['is_active'] as bool? ?? true;
    showDialog<void>(
      context: context,
      builder: (_) => _StaffOptionsDialog(
        account:      account,
        onDeactivate: isActive
            ? () {
                Navigator.pop(context);
                _deactivate(account);
              }
            : null,
      ),
    );
  }

  Future<void> _deactivate(Map<String, dynamic> account) async {
    final staffId = (account['staff_id'] ?? account['id']) as int;
    try {
      await ApiService.deactivateStaffAccount(_selectedRaceId!, staffId);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to deactivate: $e',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.w600)),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_racesLoading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(
            child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header + action ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff Accounts',
                    style: TextStyle(
                      color: _kTextPri, fontSize: 22,
                      fontWeight: FontWeight.w800, letterSpacing: -0.4,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Manage check-in and kit distribution staff',
                    style: TextStyle(color: _kTextSub, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              if (_selectedRaceId != null && _accounts.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _openCreateDialog,
                  icon:  const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Create Staff Account'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),

        // ── Race selector ────────────────────────────────────────────
        if (_races.isNotEmpty) _buildRaceSelector(),

        // ── Body ─────────────────────────────────────────────────────
        if (_races.isEmpty)
          const Expanded(child: _NoRacesState())
        else if (_loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator(
                color: _kGreen, strokeWidth: 2)),
          )
        else if (_error != null)
          Expanded(child: _buildError())
        else if (_accounts.isEmpty)
          Expanded(child: _buildEmpty())
        else
          Expanded(child: _buildList()),
      ],
    );
  }

  // ── Race selector ─────────────────────────────────────────────────────────

  Widget _buildRaceSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: _kTextSub, size: 14),
          const SizedBox(width: 8),
          const Text('Race:',
              style: TextStyle(color: _kTextSub, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:        _kSurface,
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: _kBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value:         _selectedRaceId,
                dropdownColor: const Color(0xFF0D0D18),
                isDense:       true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: _kTextSub, size: 16),
                items: _races.map((r) {
                  final id = (r['id'] as num).toInt();
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      r['name']?.toString() ?? 'Race $id',
                      style: const TextStyle(color: _kTextPri, fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null && val != _selectedRaceId) _selectRace(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Staff list ────────────────────────────────────────────────────────────

  Widget _buildList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              _buildTableHeader(),
              const SizedBox(height: 8),
              ..._accounts.map(
                (a) => _StaffRow(
                  account: a,
                  onTap:   () => _openStaffOptions(a),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: _kBorder),
      ),
      child: const Row(
        children: [
          SizedBox(width: 44),
          SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text('Name',
                style: TextStyle(color: _kTextMuted, fontSize: 11,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ),
          Expanded(
            flex: 2,
            child: Text('Role',
                style: TextStyle(color: _kTextMuted, fontSize: 11,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ),
          Expanded(
            flex: 2,
            child: Text('Assigned',
                style: TextStyle(color: _kTextMuted, fontSize: 11,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ),
          SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 52,
              color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 16),
          const Text('No staff assigned to this race',
              style: TextStyle(color: _kTextSub, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
              'Create accounts to give staff access to this race.',
              style: TextStyle(color: _kTextMuted, fontSize: 12)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _openCreateDialog,
            icon:  const Icon(Icons.add_rounded, size: 17),
            label: const Text('Create Staff Account'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
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
          const Icon(Icons.wifi_off_rounded, color: _kTextMuted, size: 48),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _load,
            child: const Text('Retry', style: TextStyle(color: _kBlue)),
          ),
        ],
      ),
    );
  }
}

// ── No races state ────────────────────────────────────────────────────────────

class _NoRacesState extends StatelessWidget {
  const _NoRacesState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 48, color: _kTextMuted),
          SizedBox(height: 14),
          Text('No races found',
              style: TextStyle(color: _kTextSub, fontSize: 15,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('Create a race first, then assign staff to it.',
              style: TextStyle(color: _kTextMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Staff row ─────────────────────────────────────────────────────────────────

class _StaffRow extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback         onTap;

  const _StaffRow({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name     = account['name']?.toString() ?? 'Unknown';
    final role     = account['role']?.toString() ?? '';
    final isActive = account['is_active'] as bool? ?? true;
    // Backend returns assigned_at; fall back to created_at for forwards compat
    final dateRaw  = account['assigned_at']?.toString()
                  ?? account['created_at']?.toString();

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color:  _kGreen.withOpacity(0.08),
                  shape:  BoxShape.circle,
                  border: Border.all(color: _kGreen.withOpacity(0.2)),
                ),
                child: Center(
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                        color: _kGreen, fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color:      isActive ? _kTextPri : _kTextMuted,
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (account['email'] != null)
                      Text(
                        account['email'].toString(),
                        style: const TextStyle(
                            color: _kTextMuted, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _RoleBadge(role: role),
                ),
              ),

              Expanded(
                flex: 2,
                child: Text(
                  _formatDate(dateRaw),
                  style: const TextStyle(color: _kTextSub, fontSize: 12),
                ),
              ),

              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color:  isActive ? _kGreen : _kTextMuted,
                  shape:  BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

// ── Role badge ────────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color  color;
    String label;

    switch (role) {
      case 'kit_staff':
        color = _kBlue;
        label = 'Kit Staff';
        break;
      case 'checkin_staff':
        color = _kAmber;
        label = 'Check-in';
        break;
      default:
        color = _kTextSub;
        label = role.isEmpty ? 'Staff' : role;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:       color,
          fontSize:    10,
          fontWeight:  FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Create staff dialog ───────────────────────────────────────────────────────

class _CreateStaffDialog extends StatefulWidget {
  final int raceId;
  final void Function(String name, String tempPassword) onCreated;
  const _CreateStaffDialog({required this.raceId, required this.onCreated});

  @override
  State<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<_CreateStaffDialog> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  String  _role   = 'checkin_staff';
  bool    _saving = false;
  String? _error;

  static const _kDialogSurface = Color(0xFF0D0D18);
  static const _kDialogBorder  = Color(0xFF1E1E32);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Full name is required.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'A valid email address is required.');
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final result = await ApiService.createStaffAccount(
        widget.raceId,
        name:  name,
        email: email,
        role:  _role,
      );
      final tempPassword = result['temp_password']?.toString() ?? '';
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated(name, tempPassword);
    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; _error = e.toString(); });
      }
    }
  }

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
    hintText:       hint,
    hintStyle:      const TextStyle(color: _kTextMuted),
    prefixIcon:     Icon(icon, color: _kTextSub, size: 16),
    filled:         true,
    fillColor:      Colors.white.withOpacity(0.04),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kDialogSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kDialogBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color:        _kGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(
                          color: _kGreen.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.badge_rounded,
                        color: _kGreen, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create Staff Account',
                          style: TextStyle(
                              color:      _kTextPri,
                              fontSize:   16,
                              fontWeight: FontWeight.bold)),
                      Text(
                          'A one-time password will be shown after creation',
                          style:
                              TextStyle(color: _kTextSub, fontSize: 12)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Full name
              TextField(
                controller: _nameCtrl,
                style:      const TextStyle(color: _kTextPri, fontSize: 14),
                decoration: _deco('Full name', Icons.person_outline_rounded),
              ),
              const SizedBox(height: 14),

              // Email
              TextField(
                controller:   _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style:        const TextStyle(color: _kTextPri, fontSize: 14),
                decoration:   _deco('Email address', Icons.email_outlined),
              ),
              const SizedBox(height: 14),

              // Role selector
              Container(
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(
                      color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Text('Role',
                          style: TextStyle(
                              color:      _kTextSub,
                              fontSize:   11,
                              fontWeight: FontWeight.w600)),
                    ),
                    _roleOption('checkin_staff', 'Check-in Staff',
                        Icons.qr_code_scanner_rounded, _kAmber),
                    const Divider(
                        height: 1, color: Color(0xFF1E1E32),
                        indent: 14, endIndent: 14),
                    _roleOption('kit_staff', 'Kit Distribution Staff',
                        Icons.inventory_2_outlined, _kBlue),
                  ],
                ),
              ),

              // Password note
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color:        _kAmber.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(color: _kAmber.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: _kAmber, size: 13),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A temporary password will be generated and shown once — copy it before closing.',
                        style: TextStyle(color: _kAmber, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        _kRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: _kRed.withOpacity(0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: _kRed, fontSize: 12)),
                ),
              ],

              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTextSub,
                        side:  const BorderSide(color: _kDialogBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Text('Create Account',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold)),
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

  Widget _roleOption(
      String value, String label, IconData icon, Color color) {
    final selected = _role == value;
    return InkWell(
      onTap:        () => setState(() => _role = value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? color : _kTextSub),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    color:      selected ? _kTextPri : _kTextSub,
                    fontSize:   13,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  )),
            ),
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                border: Border.all(
                    color: selected ? color : _kTextMuted, width: 2),
                color:  selected
                    ? color.withOpacity(0.15)
                    : Colors.transparent,
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Temp password dialog ──────────────────────────────────────────────────────

class _TempPasswordDialog extends StatefulWidget {
  final String name;
  final String tempPassword;
  const _TempPasswordDialog(
      {required this.name, required this.tempPassword});

  @override
  State<_TempPasswordDialog> createState() => _TempPasswordDialogState();
}

class _TempPasswordDialogState extends State<_TempPasswordDialog> {
  bool _copied = false;

  static const _kDialogSurface = Color(0xFF0D0D18);
  static const _kDialogBorder  = Color(0xFF1E1E32);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kDialogSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kDialogBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color:  _kGreen.withOpacity(0.1),
                  shape:  BoxShape.circle,
                  border: Border.all(color: _kGreen.withOpacity(0.3)),
                ),
                child: const Icon(Icons.check_rounded,
                    color: _kGreen, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.name} created',
                style: const TextStyle(
                    color: _kTextPri, fontSize: 16,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Share this temporary password with the staff member.\nIt will not be shown again.',
                style:     TextStyle(color: _kTextSub, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        _kAmber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(color: _kAmber.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: _kAmber, size: 14),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Copy this password now — it cannot be recovered later.',
                        style: TextStyle(color: _kAmber, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                width:   double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color:        Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: _kGreen.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        widget.tempPassword,
                        style: const TextStyle(
                          color:         _kGreen,
                          fontSize:      15,
                          fontWeight:    FontWeight.bold,
                          fontFamily:    'monospace',
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(
                            ClipboardData(text: widget.tempPassword));
                        if (!mounted) return;
                        setState(() => _copied = true);
                        await Future.delayed(
                            const Duration(seconds: 2));
                        if (mounted) setState(() => _copied = false);
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _copied
                            ? const Icon(Icons.check_rounded,
                                color: _kGreen, size: 18,
                                key: ValueKey('check'))
                            : const Icon(Icons.copy_rounded,
                                color: _kTextSub, size: 18,
                                key: ValueKey('copy')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

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
                    padding: const EdgeInsets.symmetric(vertical: 13),
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

// ── Staff options dialog ──────────────────────────────────────────────────────

class _StaffOptionsDialog extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback?        onDeactivate;

  const _StaffOptionsDialog(
      {required this.account, this.onDeactivate});

  static const _kDialogSurface = Color(0xFF0D0D18);
  static const _kDialogBorder  = Color(0xFF1E1E32);

  @override
  Widget build(BuildContext context) {
    final name     = account['name']?.toString() ?? 'Unknown';
    final isActive = account['is_active'] as bool? ?? true;

    return Dialog(
      backgroundColor: _kDialogSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kDialogBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color:      _kTextPri,
                      fontSize:   16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color:  isActive ? _kGreen : _kTextMuted,
                      shape:  BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isActive ? 'Active' : 'Deactivated',
                    style: TextStyle(
                      color:    isActive ? _kGreen : _kTextMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (onDeactivate != null) ...[
                GestureDetector(
                  onTap: onDeactivate,
                  child: Container(
                    width:   double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:        _kRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(
                          color: _kRed.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.block_rounded, color: _kRed, size: 16),
                        SizedBox(width: 10),
                        Text('Deactivate Account',
                            style: TextStyle(
                                color:      _kRed,
                                fontSize:   13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTextSub,
                    side:  const BorderSide(color: _kDialogBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
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
