// lib/roles/race_director/shell/race_director_shell.dart
//
// WEB-ONLY persistent sidebar shell for the Race Director role.
//
// Responsibilities:
//   • Sidebar navigation (Home, Races, Staff Accounts, Statistics, Settings)
//   • Responsive: full sidebar ≥ 860 px, icon-only rail < 860 px
//   • Displays logged-in user name + logout in sidebar footer
//   • Renders currently selected screen in main content area
//   • ZERO business logic — layout and navigation only
//
// Do NOT add API calls, race data fetching, or runner logic here.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/features/auth/screens/login_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/race_director_dashboard_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/race_director_home_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/staff_accounts_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/race_director_stats_screen.dart';
import 'package:andotrack_app/roles/race_director/screens/race_director_settings_screen.dart';

// ── Nav items ─────────────────────────────────────────────────────────────────

enum _NavItem {
  home,
  races,
  staff,
  stats,
  settings;

  String get label {
    switch (this) {
      case _NavItem.home:     return 'Home';
      case _NavItem.races:    return 'Races';
      case _NavItem.staff:    return 'Staff Accounts';
      case _NavItem.stats:    return 'Statistics';
      case _NavItem.settings: return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case _NavItem.home:     return Icons.home_rounded;
      case _NavItem.races:    return Icons.flag_rounded;
      case _NavItem.staff:    return Icons.badge_rounded;
      case _NavItem.stats:    return Icons.bar_chart_rounded;
      case _NavItem.settings: return Icons.settings_rounded;
    }
  }

  IconData get iconOutlined {
    switch (this) {
      case _NavItem.home:     return Icons.home_outlined;
      case _NavItem.races:    return Icons.flag_outlined;
      case _NavItem.staff:    return Icons.badge_outlined;
      case _NavItem.stats:    return Icons.bar_chart_outlined;
      case _NavItem.settings: return Icons.settings_outlined;
    }
  }
}

// ── Shell ─────────────────────────────────────────────────────────────────────

class RaceDirectorShell extends StatefulWidget {
  const RaceDirectorShell({super.key});

  @override
  State<RaceDirectorShell> createState() => _RaceDirectorShellState();
}

class _RaceDirectorShellState extends State<RaceDirectorShell> {
  _NavItem _selected = _NavItem.home;
  String   _userName = '';

  // ── Design tokens ─────────────────────────────────────────────
  static const _kBg          = Color(0xFF080810);
  static const _kSurface     = Color(0xFF0D0D18);
  static const _kSurfaceHigh = Color(0xFF141422);
  static const _kBorder      = Color(0xFF1E1E32);
  static const _kGreen       = Color(0xFF00FF9C);
  static const _kTextPri     = Colors.white;
  static const _kTextSub     = Color(0xFF8888AA);
  static const _kTextMuted   = Color(0xFF3A3A55);

  // Sidebar widths
  static const double _kSidebarFull  = 236.0;
  static const double _kSidebarRail  = 68.0;
  static const double _kBreakpoint   = 860.0;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _userName = prefs.getString('user_name') ?? 'Race Director');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _LogoutDialog(),
    );
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _buildScreen() {
    switch (_selected) {
      // Home = overview dashboard (stats + live race quick-access)
      case _NavItem.home:     return const RaceDirectorDashboardScreen();
      // Races = full race management panel (listing + create + tap to open)
      case _NavItem.races:    return const RaceDirectorHomeScreen();
      case _NavItem.staff:    return const StaffAccountsScreen();
      case _NavItem.stats:    return const RaceDirectorStatsScreen();
      case _NavItem.settings: return const RaceDirectorSettingsScreen();
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kBreakpoint;
        final sidebarW = isWide ? _kSidebarFull : _kSidebarRail;

        return Scaffold(
          backgroundColor: _kBg,
          body: Row(
            children: [
              // ── Sidebar ──────────────────────────────────────
              _Sidebar(
                width:    sidebarW,
                isWide:   isWide,
                selected: _selected,
                userName: _userName,
                onSelect: (item) => setState(() => _selected = item),
                onLogout: _logout,
              ),

              // ── Vertical divider ──────────────────────────────
              Container(width: 1, color: _kBorder),

              // ── Main content ──────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    // Top bar
                    _TopBar(
                      title:   _selected.label,
                      isWide:  isWide,
                      userName: _userName,
                    ),
                    // Content
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: KeyedSubtree(
                          key: ValueKey(_selected),
                          child: _buildScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final double   width;
  final bool     isWide;
  final _NavItem selected;
  final String   userName;
  final ValueChanged<_NavItem> onSelect;
  final VoidCallback           onLogout;

  static const _kSurface  = Color(0xFF0D0D18);
  static const _kBorder   = Color(0xFF1E1E32);
  static const _kGreen    = Color(0xFF00FF9C);
  static const _kTextPri  = Colors.white;
  static const _kTextSub  = Color(0xFF8888AA);
  static const _kTextMuted= Color(0xFF3A3A55);

  const _Sidebar({
    required this.width,
    required this.isWide,
    required this.selected,
    required this.userName,
    required this.onSelect,
    required this.onLogout,
  });

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'RD';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve:    Curves.easeOutCubic,
      width:    width,
      color:    _kSurface,
      child:    Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Wordmark / logo ──────────────────────────────────
          Container(
            height:  64,
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 20 : 0,
              vertical: 0,
            ),
            alignment: isWide
                ? Alignment.centerLeft
                : Alignment.center,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: isWide
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/favicon.png',
                        width: 32, height: 32,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'AndoTrack',
                        style: TextStyle(
                          color:       _kTextPri,
                          fontSize:    16,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  )
                : Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color:        _kGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                      border:       Border.all(
                          color: _kGreen.withOpacity(0.3)),
                    ),
                    child: const Icon(
                        Icons.directions_run_rounded,
                        color: _kGreen, size: 17),
                  ),
          ),

          const SizedBox(height: 8),

          // ── Nav items ────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: _NavItem.values.map((item) {
                  return _NavTile(
                    item:     item,
                    selected: item == selected,
                    isWide:   isWide,
                    onTap:    () => onSelect(item),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── User + logout footer ──────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 14 : 8,
              vertical:   14,
            ),
            child: isWide
                ? Row(
                    children: [
                      // Avatar
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color:  _kGreen.withOpacity(0.1),
                          shape:  BoxShape.circle,
                          border: Border.all(
                              color: _kGreen.withOpacity(0.25)),
                        ),
                        child: Center(
                          child: Text(
                            _initials(userName),
                            style: const TextStyle(
                              color:      _kGreen,
                              fontSize:   12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Name + role
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                color:      _kTextPri,
                                fontSize:   12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Race Director',
                              style: TextStyle(
                                  color:   _kTextMuted,
                                  fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      // Logout
                      Tooltip(
                        message: 'Log out',
                        child: GestureDetector(
                          onTap: onLogout,
                          child: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color:        Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border:       Border.all(
                                  color: Colors.red.withOpacity(0.2)),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Color(0xFFFF4D4D),
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                // Rail mode — just avatar + logout stacked
                : Column(
                    children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color:  _kGreen.withOpacity(0.1),
                          shape:  BoxShape.circle,
                          border: Border.all(
                              color: _kGreen.withOpacity(0.25)),
                        ),
                        child: Center(
                          child: Text(
                            _initials(userName),
                            style: const TextStyle(
                              color:      _kGreen,
                              fontSize:   12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: onLogout,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color:        Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border:       Border.all(
                                color: Colors.red.withOpacity(0.2)),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFFF4D4D),
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Nav tile ──────────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool     selected;
  final bool     isWide;
  final VoidCallback onTap;

  static const _kGreen   = Color(0xFF00FF9C);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);

  const _NavTile({
    required this.item,
    required this.selected,
    required this.isWide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:     isWide ? '' : item.label,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin:   const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 12 : 0,
            vertical:   10,
          ),
          decoration: BoxDecoration(
            color:        selected
                ? _kGreen.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border:       selected
                ? Border.all(color: _kGreen.withOpacity(0.2))
                : null,
          ),
          child: isWide
              ? Row(
                  children: [
                    Icon(
                      selected ? item.icon : item.iconOutlined,
                      color:  selected ? _kGreen : _kTextSub,
                      size:   18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.label,
                      style: TextStyle(
                        color:      selected ? _kGreen : _kTextSub,
                        fontSize:   13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Icon(
                    selected ? item.icon : item.iconOutlined,
                    color: selected ? _kGreen : _kTextSub,
                    size:  20,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final bool   isWide;
  final String userName;

  static const _kBorder  = Color(0xFF1E1E32);
  static const _kSurface = Color(0xFF0D0D18);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);

  const _TopBar({
    required this.title,
    required this.isWide,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height:  56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color:  _kSurface,
        border: const Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color:       _kTextPri,
              fontSize:    15,
              fontWeight:  FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          // Show user name in top bar when sidebar is in rail mode
          if (!isWide)
            Text(
              userName,
              style: const TextStyle(color: _kTextSub, fontSize: 12),
              overflow: TextOverflow.ellipsis,
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

// ── Placeholder view (for screens not yet built) ──────────────────────────────

class _PlaceholderView extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;

  static const _kTextSub  = Color(0xFF8888AA);
  static const _kTextMuted= Color(0xFF3A3A55);

  const _PlaceholderView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: _kTextMuted),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  color: _kTextSub, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(color: _kTextMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
