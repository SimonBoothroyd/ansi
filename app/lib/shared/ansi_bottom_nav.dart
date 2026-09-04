/// The app's bottom nav bar (design board: Library · Week · Cook · Shop).
///
/// One instance, owned by the tab shell — not one per tab screen. It reads and
/// drives the [StatefulNavigationShell], so a tap changes a branch index and
/// nothing about the bar itself moves or rebuilds.
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
      // Re-tapping the selected tab sends that branch back to its root — the
      // iOS "tap the tab you are on to go to the top" convention.
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
        // Colour and weight are deliberately absent: Forui resolves the
        // selected variant (muted → primary, 400 → 700) into an ancestor
        // DefaultTextStyle, and a Text's own value would win over it, leaving
        // the label grey while its icon greened.
        style: ansiMonoInherit(size: 10, letterSpacing: 0.5),
      ),
    );
  }
}
