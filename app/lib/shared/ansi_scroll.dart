/// The app's scrollbar, and the room wide panes keep for it.
///
/// On a mouse platform Flutter draws a persistent bar over the content's
/// right edge, covering row-end controls. [AnsiScrollBehavior] draws the bar
/// (installed once in `app.dart`); [ansiScrollGutter] keeps row ends clear
/// of it and is zero at [AnsiShell.bar]. Mouse drag-to-scroll stays off
/// because it would break text selection.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';

/// How wide the app draws its scrollbar.
const double kAnsiScrollbarThickness = 8;

/// How far clear of the pane's edge the bar sits.
const double kAnsiScrollbarMargin = 2;

/// The thumb's ink: [AnsiColors.muted] at a quarter opacity.
const Color kAnsiScrollbarThumb = Color(0x4066736A);

/// The air between the last control in a row and the scrollbar's near edge.
const double kAnsiScrollbarClearance = 8;

/// The room a wide pane keeps on its right for the scrollbar. Derived, so
/// widening the bar widens the gutter.
const double kAnsiScrollGutter =
    kAnsiScrollbarThickness + kAnsiScrollbarMargin + kAnsiScrollbarClearance;

/// The gutter [context]'s pane owes the scrollbar: [kAnsiScrollGutter] once
/// the chrome is beside the content, zero under it. Rebuilds on resize.
double ansiScrollGutter(BuildContext context) =>
    AnsiShell.of(context).beside ? kAnsiScrollGutter : 0;

/// [base] with [ansiScrollGutter] added to its right edge.
EdgeInsets ansiScrollPadding(BuildContext context, EdgeInsets base) =>
    base.copyWith(right: base.right + ansiScrollGutter(context));

/// The app's scrollbar, installed once at the root: always visible on a
/// mouse platform, never drawn on a touch platform.
class AnsiScrollBehavior extends ScrollBehavior {
  const AnsiScrollBehavior();

  bool _touch(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (_touch(getPlatform(context))) return child;
    return switch (details.direction) {
      // No bar under a horizontal strip.
      AxisDirection.left || AxisDirection.right => child,
      _ => RawScrollbar(
        controller: details.controller,
        thickness: kAnsiScrollbarThickness,
        thumbColor: kAnsiScrollbarThumb,
        radius: const Radius.circular(kAnsiScrollbarThickness / 2),
        crossAxisMargin: kAnsiScrollbarMargin,
        mainAxisMargin: kAnsiScrollbarMargin,
        thumbVisibility: true,
        child: child,
      ),
    };
  }
}
