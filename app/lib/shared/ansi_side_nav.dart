/// The wide chrome: the bottom bar's four destinations beside the content,
/// with Account as the footer door.
///
/// Drawn once, outside every Navigator (`core/router/app_router.dart`), so a
/// push never animates it. A null [AnsiSideNav.index] lights nothing, which
/// is what a pushed page wears.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';
import 'guarded_navigation.dart';

/// The full sidebar's width.
const double kAnsiSidebarWidth = 188;

/// The icon rail's width, for 1024–1279.
const double kAnsiRailWidth = 64;

/// The household door's location. A literal: `shared/` does not import
/// `features/`.
const _accountRoute = '/account';

/// The four destinations: the app's loop, in the bar's order.
const _destinations = <({IconData icon, String label, String route})>[
  (icon: FLucideIcons.library, label: 'Library', route: '/'),
  (icon: FLucideIcons.calendarDays, label: 'Week', route: '/week'),
  (icon: FLucideIcons.cookingPot, label: 'Cook', route: '/cook'),
  (icon: FLucideIcons.shoppingBasket, label: 'Shop', route: '/shop'),
];

/// The branch locations, index-aligned with the shell's branches; a location
/// is checked against them to decide which destination is lit.
List<String> get ansiBranchLocations => [
  for (final d in _destinations) d.route,
];

class AnsiSideNav extends StatelessWidget {
  const AnsiSideNav({required this.form, this.index, super.key});

  /// [AnsiShell.rail] draws icons with tooltips; [AnsiShell.sidebar] draws
  /// icons with their labels. [AnsiShell.bar] never reaches here.
  final AnsiShell form;

  /// The lit destination, or null for the neutral form.
  final int? index;

  bool get _rail => form == AnsiShell.rail;

  @override
  Widget build(BuildContext context) => FSidebar(
    style: FSidebarStyleDelta.delta(
      constraints: BoxConstraints.tightFor(
        width: _rail ? kAnsiRailWidth : kAnsiSidebarWidth,
      ),
      decoration: _decoration,
      groupStyle: FSidebarGroupStyleDelta.delta(
        padding: EdgeInsetsDelta.value(
          EdgeInsets.symmetric(horizontal: _rail ? 10 : 12),
        ),
        itemStyle: _itemStyle,
      ),
    ),
    header: _Wordmark(rail: _rail),
    footer: FSidebarGroup(
      children: [
        // A push, unlike the destinations: Account is a page over where you
        // were, so its back chevron has something to pop. A `go` would
        // replace the stack and leave back with nothing under it.
        _Item(
          icon: FLucideIcons.users,
          label: 'Account',
          rail: _rail,
          onPress: () => context.pushOnce(_accountRoute),
        ),
      ],
    ),
    children: [
      FSidebarGroup(
        children: [
          for (final (i, d) in _destinations.indexed)
            _Item(
              icon: d.icon,
              label: d.label,
              rail: _rail,
              selected: i == index,
              // `go`, not a push: a destination replaces the stack, which is
              // also how a pushed page is left behind.
              onPress: () => context.goOnce(d.route),
            ),
        ],
      ),
    ],
  );

  DecorationDelta get _decoration => const DecorationDelta.boxDelta(
    color: AnsiColors.paper,
    border: Border(right: BorderSide(color: AnsiColors.line)),
  );

  FSidebarItemStyleDelta get _itemStyle => FSidebarItemStyleDelta.delta(
    // Centres an 18 px icon in 64: 10 of group padding and 13 of item
    // padding each side.
    padding: EdgeInsetsGeometryDelta.value(
      EdgeInsets.symmetric(horizontal: _rail ? 13 : 10, vertical: 10),
    ),
    iconStyle: FVariantsDelta.delta([
      FVariantOperation.all(const IconThemeDataDelta.delta(size: 18)),
      FVariantOperation.exact({
        FTappableVariantConstraint.selected,
      }, const IconThemeDataDelta.delta(color: AnsiColors.herbDeep)),
    ]),
    textStyle: FVariantsDelta.delta([
      FVariantOperation.all(const TextStyleDelta.delta(fontSize: 13)),
      // The lit destination reads herb-deep, as the bar's selected item does;
      // the herb-soft ground alone is a 1.3:1 difference.
      FVariantOperation.exact({
        FTappableVariantConstraint.selected,
      }, const TextStyleDelta.delta(color: AnsiColors.herbDeep)),
    ]),
    // Forui paints the surface colour under every item, which on paper reads
    // as white pills. Only the lit or hovered item gets a ground.
    backgroundColor: FVariantsValueDelta.delta([
      FVariantValueDeltaOperation.base(const Color(0x00000000)),
    ]),
    // The focus ring is the theme's (`core/theme/ansi_theme.dart`).
  );
}

/// A destination or the footer door: an [FSidebarItem] whose label becomes
/// a tooltip on the rail.
class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.rail,
    required this.onPress,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool rail;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final item = FSidebarItem(
      icon: Icon(icon),
      label: rail ? null : Text(label),
      selected: selected,
      onPress: onPress,
    );
    if (!rail) return item;
    // Hover or focus raises the tooltip.
    return FTooltip(
      childAnchor: Alignment.centerRight,
      tipAnchor: Alignment.centerLeft,
      tipBuilder: (context, controller) => Text(label),
      child: item,
    );
  }
}

/// `Ansi.` over the destinations, the full stop in herb. The rail keeps the
/// initial and the stop.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.rail});

  final bool rail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: rail ? 0 : 12, top: 6, bottom: 10),
    child: Text.rich(
      TextSpan(
        text: rail ? 'A' : 'Ansi',
        children: const [
          TextSpan(
            text: '.',
            style: TextStyle(color: AnsiColors.herb),
          ),
        ],
      ),
      textAlign: rail ? TextAlign.center : TextAlign.start,
      style: ansiSerif(size: AnsiType.heading, weight: FontWeight.w500),
    ),
  );
}
