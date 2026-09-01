/// The app's bottom nav bar (design board: Library · Week · Cook · Shop).
///
/// Library, Week, Cook and Shop are all live tabs. Switching tabs uses
/// `context.go` so the tab roots replace rather than stack.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

/// The tab a screen occupies, and its index in the bar.
enum AnsiTab { library, week, cook, shop }

class AnsiBottomNav extends StatelessWidget {
  const AnsiBottomNav({required this.current, super.key});

  final AnsiTab current;

  @override
  Widget build(BuildContext context) {
    return FBottomNavigationBar(
      index: current.index,
      onChange: (i) {
        final tab = AnsiTab.values[i];
        if (tab == current) return;
        switch (tab) {
          case AnsiTab.library:
            context.go('/');
          case AnsiTab.week:
            context.go('/week');
          case AnsiTab.cook:
            context.go('/cook');
          case AnsiTab.shop:
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
        style: ansiMono(size: 10, color: AnsiColors.muted, letterSpacing: 0.5),
      ),
    );
  }
}
