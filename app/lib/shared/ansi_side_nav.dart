/// The wide chrome: the four destinations beside the content instead of under
/// it, with Account as the quiet footer door.
///
/// The same four destinations as the bottom bar (`shared/ansi_bottom_nav.dart`),
/// in the same order and with the same Lucide icons — one loop, drawn twice
/// because a bar and a sidebar are different shapes, not different navigations.
///
/// **It is drawn once, outside every Navigator** (`core/router/app_router.dart`
/// builds it in the outer shell), which is what lets a pushed page keep the
/// chrome without the chrome taking part in the push: nothing animates, nothing
/// rebuilds, and there is never a second copy sliding over the first.
///
/// **A null [AnsiSideNav.index] is the neutral form** — the sidebar with
/// nothing lit, which is what a pushed page wears. On a phone the bar being
/// gone is the signal that you have left the tab loop; on a desk the sidebar
/// cannot leave, so *nothing lit* carries the same sentence, and the page draws
/// its own back control.
///
/// Account is a footer item rather than a fifth destination: it is not a phase
/// of the loop. On wide it is also the ONLY household door — the Library header
/// does not draw a second one.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';
import 'guarded_navigation.dart';

/// The full sidebar's width. The board's number: wide enough for `Library` at
/// the item's own size, narrow enough to leave a 1280 window a real pane.
const double kAnsiSidebarWidth = 188;

/// The icon rail's width, for 1024–1279 — an iPad in landscape, where 188 px of
/// labels would cost a sixth of the window.
const double kAnsiRailWidth = 64;

/// The household door's location. Spelled here rather than imported from the
/// account feature: `shared/` does not reach into `features/`, and every other
/// location in this file is a literal too.
const _accountRoute = '/account';

/// The four destinations: the app's loop, in the bar's order.
const _destinations = <({IconData icon, String label, String route})>[
  (icon: FLucideIcons.library, label: 'Library', route: '/'),
  (icon: FLucideIcons.calendarDays, label: 'Week', route: '/week'),
  (icon: FLucideIcons.cookingPot, label: 'Cook', route: '/cook'),
  (icon: FLucideIcons.shoppingBasket, label: 'Shop', route: '/shop'),
];

/// The branch locations, index-aligned with the shell's branches — what a
/// location is checked against to decide which destination is lit.
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
        // The one door to the household on wide, and quiet: it is where you go
        // to change something about the app, not a phase of the loop.
        _Item(
          icon: FLucideIcons.users,
          label: 'Account',
          rail: _rail,
          onPress: () => context.goOnce(_accountRoute),
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
              // `go`, not a push: a destination is where you are, not a page
              // over where you were — and from a pushed page it is also how
              // the page is left behind. The tab shell keeps every branch's
              // Navigator and state either way.
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
    // The rail's padding is what centres an 18 px icon in 64: 10 of group
    // padding each side leaves a 44 px item, and 13 of item padding leaves
    // exactly the icon.
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
      // The lit destination reads herb-deep, the step the bar's selected item
      // already takes; the herb-soft ground alone is a 1.3:1 difference.
      FVariantOperation.exact({
        FTappableVariantConstraint.selected,
      }, const TextStyleDelta.delta(color: AnsiColors.herbDeep)),
    ]),
    // The rail's ground is paper, and an item at rest is part of it: Forui's
    // default paints the surface colour under every item, which on paper reads
    // as five white pills. Only the lit one, and whatever the pointer is over,
    // gets a shape of its own.
    backgroundColor: FVariantsValueDelta.delta([
      FVariantValueDeltaOperation.base(const Color(0x00000000)),
    ]),
    // The focus ring is the theme's now — 2 px herb, 2 px clear, the same one
    // every swept glyph wears (`core/theme/ansi_theme.dart`) — so the sidebar
    // no longer states its own lift here.
  );
}

/// A destination, or the footer door: an [FSidebarItem] whose label is a
/// tooltip instead of a line of text once the chrome is a rail.
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
    // Hover OR focus raises it, so the rail answers a pointer and a keyboard
    // with the same word.
    return FTooltip(
      childAnchor: Alignment.centerRight,
      tipAnchor: Alignment.centerLeft,
      tipBuilder: (context, controller) => Text(label),
      child: item,
    );
  }
}

/// `Ansi.` over the destinations — the app's name, in the app's serif, with the
/// full stop in herb. The rail keeps the initial and the stop.
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
      style: ansiSerif(size: 19, weight: FontWeight.w500),
    ),
  );
}
