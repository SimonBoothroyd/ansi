/// The app's bottom nav bar (Library · Week · Cook · Shop). One instance,
/// owned by the tab shell; it reads and drives the [StatefulNavigationShell].
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/ansi_theme.dart';

class AnsiBottomNav extends StatelessWidget {
  const AnsiBottomNav({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return FBottomNavigationBar(
      index: shell.currentIndex,
      // Re-tapping the selected tab sends that branch back to its root.
      onChange: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
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
        // No colour or weight: Forui resolves the selected variant into an
        // ancestor DefaultTextStyle, which a Text's own value would override.
        style: ansiMonoInherit(size: 10, letterSpacing: 0.5),
      ),
    );
  }
}
