// lib/roles/kit_staff/shell/kit_staff_shell.dart
//
// WEB-ONLY top-bar shell for the Kit Distribution Staff role.
//
// Responsibilities:
//   • Top bar: logo, "Kit Distribution Staff" amber badge, user name, logout
//   • Content: list of races THIS staff member is assigned to (not all races)
//   • Navigate to KitDashboardScreen on race card tap
//   • ZERO business logic — layout and navigation only
//
// Assignment filter: getRaces() → parallel getStaffAccounts(raceId) per race
// → keep only races where staff_id (or user_id or id) matches the logged-in user_id.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/utils/date_utils.dart';
import 'package:andotrack_app/features/auth/screens/login_screen.dart';
import 'package:andotrack_app/roles/kit_staff/screens/kit_dashboard_screen.dart';

// ── Shell ─────────────────────────────────────────────────────────────────────

class KitStaffShell extends StatefulWidget {
  const KitStaffShell({super.key});

  @override
  State<KitStaffShell> createState() => _KitStaffShellState();
}

class _KitStaffShellState extends State<KitStaffShell> {
  static const _kBg    = Color(0xFF080810);
  static const _kGreen = Color(0xFF00FF9C);

  String _userName = '';
  int?   _userId;
  bool   _loading = true;
  String? _error;
  List<Map<String, dynamic>> _races = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = _readUserId(prefs);
    _userName = prefs.getString('user_name') ?? 'Staff';
    await _loadRaces();
  }

  /// Normalises a raw JSON ID value to int.
  /// Handles both num (backend sends integer) and String (backend sends "42").
  /// Using 'is' type checks instead of 'as' casts avoids TypeError when the
  /// runtime type differs from the expected type.
  static int? _resolveId(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// Reads user_id from prefs as int. Falls back to parsing a stored String
  /// value so the filter is robust against future login-side type changes.
  static int? _readUserId(SharedPreferences prefs) {
    final asInt = prefs.getInt('user_id');
    if (asInt != null) return asInt;
    final asStr = prefs.getString('user_id');
    return asStr != null ? int.tryParse(asStr) : null;
  }

  /// Loads all races then filters to only those where the logged-in staff
  /// member appears in the race's staff list.
  ///
  /// ID comparison uses [_resolveId] so it handles both numeric and String-typed
  /// IDs from the backend. Debug prints are intentionally left in to allow
  /// browser-console diagnosis if the filter produces unexpected results.
  Future<void> _loadRaces() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      if (_userId == null) {
        final prefs = await SharedPreferences.getInstance();
        _userId = _readUserId(prefs);
      }

      if (_userId == null) {
        debugPrint('[KitFilter] ⚠️  No user_id in SharedPreferences — cannot filter races.');
        if (mounted) setState(() { _races = []; _loading = false; });
        return;
      }

      debugPrint('[KitFilter] logged-in user_id=$_userId (${_userId.runtimeType})');

      final allRaces = await ApiService.getRaces();

      final checks = await Future.wait(
        allRaces.map((race) async {
          final raceId = (race['id'] as num).toInt();
          try {
            final staff = await ApiService.getStaffAccounts(raceId);
            final isAssigned = staff.any((s) {
              // Skip explicitly deactivated staff; treat null as active.
              final isActive = s['is_active'];
              if (isActive == false) return false;

              // Backend may return the staff member's user ID under
              // 'staff_id', 'user_id', or 'id'. Check all three.
              final sid = _resolveId(s['staff_id'])
                       ?? _resolveId(s['user_id'])
                       ?? _resolveId(s['id']);

              debugPrint(
                '[KitFilter] race=$raceId'
                '  staff_id=${s['staff_id']}(${s['staff_id']?.runtimeType})'
                '  user_id=${s['user_id']}(${s['user_id']?.runtimeType})'
                '  id=${s['id']}(${s['id']?.runtimeType})'
                '  is_active=$isActive'
                '  → resolved=$sid  logged-in=$_userId'
                '  match=${sid == _userId}',
              );

              return sid != null && sid == _userId;
            });
            return isAssigned ? race : null;
          } catch (e) {
            debugPrint('[KitFilter] race=$raceId staff fetch error: $e');
            return null;
          }
        }),
      );

      final assigned = checks.whereType<Map<String, dynamic>>().toList();
      debugPrint('[KitFilter] result: ${assigned.length} assigned / ${allRaces.length} total');
      if (mounted) setState(() { _races = assigned; _loading = false; });
    } catch (e) {
      debugPrint('[KitFilter] _loadRaces error: $e');
      if (mounted) setState(() { _error = 'Could not load races.'; _loading = false; });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _LogoutDialog(),
    );
    if (confirmed != true || !mounted) return;

    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _openDashboard(Map<String, dynamic> race) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KitDashboardScreen(
          raceId:   (race['id'] as num).toInt(),
          raceName: race['name']?.toString() ?? 'Race',
          raceData: race,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'KS';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _KitTopBar(
            userName: _userName,
            initials: _initials(_userName),
            onLogout: _logout,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadRaces);
    }
    if (_races.isEmpty) {
      return const _EmptyState();
    }
    return _RaceGrid(races: _races, onTap: _openDashboard);
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _KitTopBar extends StatelessWidget {
  final String userName;
  final String initials;
  final VoidCallback onLogout;

  static const _kSurface = Color(0xFF0D0D18);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kGreen   = Color(0xFF00FF9C);
  static const _kAmber   = Color(0xFFFFB800);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);

  const _KitTopBar({
    required this.userName,
    required this.initials,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/favicon.png', width: 30, height: 30),
          const SizedBox(width: 10),
          const Text(
            'AndoTrack',
            style: TextStyle(
              color: _kTextPri,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 14),
          // Role badge — amber to distinguish from check-in staff (blue)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kAmber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kAmber.withOpacity(0.35)),
            ),
            child: const Text(
              'Kit Distribution Staff',
              style: TextStyle(color: _kAmber, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          // Avatar
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _kAmber.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: _kAmber.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(color: _kAmber, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(userName, style: const TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(width: 20),
          // Logout
          Tooltip(
            message: 'Log out',
            child: GestureDetector(
              onTap: onLogout,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: const Icon(Icons.logout_rounded, color: Color(0xFFFF4D4D), size: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Race grid ─────────────────────────────────────────────────────────────────

class _RaceGrid extends StatelessWidget {
  final List<Map<String, dynamic>> races;
  final ValueChanged<Map<String, dynamic>> onTap;

  static const _kTextMuted = Color(0xFF3A3A55);

  const _RaceGrid({required this.races, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ASSIGNED RACES',
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ...races.map((race) => _KitRaceCard(race: race, onTap: () => onTap(race))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Kit race card — lazy-loads per-race kit claiming counts ───────────────────

class _KitRaceCard extends StatefulWidget {
  final Map<String, dynamic> race;
  final VoidCallback onTap;

  const _KitRaceCard({required this.race, required this.onTap});

  @override
  State<_KitRaceCard> createState() => _KitRaceCardState();
}

class _KitRaceCardState extends State<_KitRaceCard> {
  bool _hovered       = false;
  bool _loadingCounts = true;
  int? _total;
  int? _claimed;

  static const _kSurface     = Color(0xFF0D0D18);
  static const _kSurfaceHigh = Color(0xFF141422);
  static const _kBorder      = Color(0xFF1E1E32);
  static const _kGreen       = Color(0xFF00FF9C);
  static const _kAmber       = Color(0xFFFFB800);
  static const _kBlue        = Color(0xFF00B4FF);
  static const _kRed         = Color(0xFFFF4D4D);
  static const _kTextPri     = Colors.white;
  static const _kTextSub     = Color(0xFF8888AA);
  static const _kTextMuted   = Color(0xFF3A3A55);

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final raceId = (widget.race['id'] as num).toInt();
      final res = await ApiService.get('/kit/$raceId/runners?status=all');
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final runners = decoded is List
            ? decoded.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        final claimed = runners.where((r) => r['claimed'] == true).length;
        if (mounted) {
          setState(() {
            _total         = runners.length;
            _claimed       = claimed;
            _loadingCounts = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingCounts = false);
      }
    } catch (_) {
      // Counts unavailable — show dashes instead of failing the card
      if (mounted) setState(() => _loadingCounts = false);
    }
  }

  static String _formatDate(dynamic iso) {
    if (iso == null) return 'Date TBD';
    try {
      final dt = parsePht(iso.toString());
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ·  $h:$m';
    } catch (_) {
      return 'Date TBD';
    }
  }

  static (Color, String) _statusMeta(String? status) {
    switch (status) {
      case 'race_day':          return (_kAmber,   'Kit Day');
      case 'active':            return (_kBlue,    'Race Active');
      case 'finished':          return (_kTextSub, 'Finished');
      case 'registration_open': return (_kGreen,   'Registration Open');
      default:                  return (_kTextSub, 'Upcoming');
    }
  }

  @override
  Widget build(BuildContext context) {
    final race    = widget.race;
    final name    = race['name']?.toString() ?? 'Unnamed Race';
    final status  = race['status']?.toString();
    final dateIso = race['scheduled_start'] ?? race['date'] ?? race['started_at'] ?? race['created_at'];

    final (statusColor, statusLabel) = _statusMeta(status);

    final unclaimed = (_total != null && _claimed != null)
        ? (_total! - _claimed!).clamp(0, 9999999)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _hovered ? _kSurfaceHigh : _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? _kAmber.withOpacity(0.3) : _kBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: icon + name + status ───────────────────────────
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _kAmber.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kAmber.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: _kAmber, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: _kTextPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                color: _kTextSub, size: 12),
                            const SizedBox(width: 5),
                            Text(
                              _formatDate(dateIso),
                              style: const TextStyle(color: _kTextSub, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.chevron_right_rounded,
                      color: _kTextMuted, size: 20),
                ],
              ),

              // ── Count row ─────────────────────────────────────────────────
              if (!_loadingCounts) ...[
                const SizedBox(height: 14),
                Container(height: 1, color: _kBorder),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _CountPill(
                      icon: Icons.people_rounded,
                      color: _kTextSub,
                      label: 'Registered',
                      value: _total?.toString() ?? '—',
                    ),
                    const SizedBox(width: 10),
                    _CountPill(
                      icon: Icons.check_box_rounded,
                      color: _kGreen,
                      label: 'Claimed',
                      value: _claimed?.toString() ?? '—',
                    ),
                    const SizedBox(width: 10),
                    _CountPill(
                      icon: Icons.check_box_outline_blank_rounded,
                      color: unclaimed != null && unclaimed > 0
                          ? _kRed
                          : _kTextSub,
                      label: 'Unclaimed',
                      value: unclaimed?.toString() ?? '—',
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 14),
                Container(height: 1, color: _kBorder),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _kAmber.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Loading kit counts…',
                      style: TextStyle(color: _kTextMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Count pill ─────────────────────────────────────────────────────────────────

class _CountPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _CountPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  static const _kTextSub   = Color(0xFF8888AA);
  static const _kTextMuted = Color(0xFF3A3A55);

  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inventory_2_outlined, color: _kTextMuted, size: 48),
          SizedBox(height: 14),
          Text(
            'You have no assigned races',
            style: TextStyle(
              color: _kTextSub,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Contact your Race Director to be assigned to a race.',
            style: TextStyle(color: _kTextMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  static const _kAmber   = Color(0xFFFFB800);
  static const _kTextSub = Color(0xFF8888AA);

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF4D4D), size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: _kTextSub, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAmber,
              side: BorderSide(color: _kAmber.withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logout dialog ─────────────────────────────────────────────────────────────

class _LogoutDialog extends StatelessWidget {
  static const _kSurface = Color(0xFF0D0D18);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);
  static const _kRed     = Color(0xFFFF4D4D);

  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Log out?',
                style: TextStyle(
                  color: _kTextPri,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You will need to sign in again.',
                style: TextStyle(color: _kTextSub, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTextSub,
                        side: const BorderSide(color: _kBorder, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
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
}
