/// The app's bottom nav bar (design board: Library · Week · Cook · Shop).
///
/// Library, Week, Cook and Shop are all live tabs. Switching tabs uses
/// `context.go` so the tab roots replace rather than stack.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/mise_theme.dart';
import '../core/theme/mise_tokens.dart';

/// The tab a screen occupies, and its index in the bar.
enum MiseTab { library, week, cook, shop }

class MiseBottomNav extends StatelessWidget {
  const MiseBottomNav({required this.current, super.key});

  final MiseTab current;

  @override
  Widget build(BuildContext context) {
    return FBottomNavigationBar(
      index: current.index,
      onChange: (i) {
        final tab = MiseTab.values[i];
        if (tab == current) return;
        switch (tab) {
          case MiseTab.library:
            context.go('/');
          case MiseTab.week:
            context.go('/week');
          case MiseTab.cook:
            context.go('/cook');
          case MiseTab.shop:
            context.go('/shop');
        }
      },
      children: const [
        _NavItem(icon: FLucideIcons.library, label: 'Library'),
        _NavItem(icon: FLucideIcons.calendarDays, label: 'Week'),
        _NavItem(icon: FLucideIcons.cookingPot, label: 'Cook'),
        _NavItem(icon: FLucideIcons.shoppingBasket, label: 'Shop'),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FBottomNavigationBarItem(
      icon: Icon(icon),
      label: Text(
        label.toUpperCase(),
        style: miseMono(size: 10, color: MiseColors.muted, letterSpacing: 0.5),
      ),
    );
  }
}
