/// The app's bottom nav bar (design board: Library · Week · Cook · Shop).
///
/// Library, Week and Cook are live tabs; Shop is shown for the shape of the app
/// but is inert until its step lands (roadmap step 6). Switching tabs uses
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
            // Not built yet (step 6): the tab renders but doesn't navigate.
            break;
        }
      },
      children: const [
        _NavItem(icon: FLucideIcons.library, label: 'Library'),
        _NavItem(icon: FLucideIcons.calendarDays, label: 'Week'),
        _NavItem(icon: FLucideIcons.cookingPot, label: 'Cook'),
        _NavItem(
          icon: FLucideIcons.shoppingBasket,
          label: 'Shop',
          enabled: false,
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FBottomNavigationBarItem(
      icon: Icon(icon, color: enabled ? null : MiseColors.line),
      label: Text(
        label.toUpperCase(),
        style: miseMono(
          size: 10,
          color: enabled ? MiseColors.muted : MiseColors.line,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
