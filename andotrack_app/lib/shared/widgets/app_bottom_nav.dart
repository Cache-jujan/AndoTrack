// MOVED TO: lib/shared/widgets/app_bottom_nav.dart

import 'package:flutter/material.dart';

enum NavTab { map, leaderboard, races, settings }

class AppBottomNav extends StatelessWidget {
  final NavTab current;
  final void Function(NavTab) onTap;

  const AppBottomNav({
    super.key,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: const Color(0xFF0D0D14),
      indicatorColor: const Color(0xFF00FF9C).withOpacity(0.15),
      selectedIndex: current.index,
      onDestinationSelected: (i) => onTap(NavTab.values[i]),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.map_outlined, color: Color(0xFF666680)),
          selectedIcon: Icon(Icons.map, color: Color(0xFF00FF9C)),
          label: 'Map',
        ),
        NavigationDestination(
          icon: Icon(Icons.leaderboard_outlined, color: Color(0xFF666680)),
          selectedIcon: Icon(Icons.leaderboard, color: Color(0xFF00FF9C)),
          label: 'Leaderboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.flag_outlined, color: Color(0xFF666680)),
          selectedIcon: Icon(Icons.flag, color: Color(0xFF00FF9C)),
          label: 'Races',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined, color: Color(0xFF666680)),
          selectedIcon: Icon(Icons.settings, color: Color(0xFF00FF9C)),
          label: 'Settings',
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF00FF9C);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected
                    ? activeColor
                    : Colors.white.withOpacity(0.3),
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? activeColor
                      : Colors.white.withOpacity(0.3),
                  fontSize: 10,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
