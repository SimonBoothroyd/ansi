/// **Where the scrollbar is, and the room the app keeps for it.**
///
/// On a phone a scrollbar is a hint that fades. On the web and on a desk
/// Flutter draws a persistent one *over* the content, hard against the right
/// edge of whatever scrolls — and it is drawn last, so it wins. Every control
/// the app puts at the end of a row therefore ends up under the thumb: the `⋯`
/// on a ledger row, the `−` on a Week agenda line, the `›` on a day heading.
/// That is the owner's second report — *on Library as well, for example, they
/// collide with the scroll bar* — and it is not a hover problem at all. The
/// control answers the pointer correctly; the pointer never reaches it.
///
/// Two halves fix it, and they have to agree on one number:
///
/// * **[AnsiScrollBehavior]** draws the scrollbar the app's way instead of the
///   platform's: [kAnsiScrollbarThickness] wide, [kAnsiScrollbarMargin] clear
///   of the edge, always visible where a mouse is the pointer and never drawn
///   at all where a finger is. It is installed once, at the app root
///   (`app.dart`), so no scroll view opts in or out.
/// * **[ansiScrollGutter]** is the room a wide pane leaves on its right so its
///   last control stops before the thumb starts. It is the thickness, the
///   margin, and 8 px of air — one number, derived, so the bar cannot be
///   widened without the gutter following.
///
/// The gutter is **zero wherever the chrome is under the content**
/// ([AnsiShell.bar]): that is the phone and the half-screen window, where the
/// scrollbar is a fading hint over a page that is already gutter-padded and
/// nothing collides. So the phone is untouched, by the same rule that decides
/// everything else about width in this app.
///
/// ## Mouse drag-to-scroll
///
/// Deliberately **not** enabled. `dragDevices` is left at Flutter's default, so
/// a mouse scrolls with the wheel and the thumb — which is the whole point of
/// drawing the thumb where it can be reached — and not by dragging the body.
/// Adding `PointerDeviceKind.mouse` would not have broken drag-to-reorder (the
/// three reorderable lists start their drag from an explicit
/// `ReorderableDragStartListener` grip, whose own recogniser accepts every
/// device and does not consult this behaviour) and it would not have broken the
/// shopping list's swipe (a `Dismissible`'s recogniser is likewise its own).
/// What it *would* break is selecting text: a click-drag across a method step
/// or an ingredient row would scroll the list instead of selecting the words,
/// on a device whose whole idiom is that you can copy what you read. The wheel
/// is not missing, so there is nothing to trade for.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';

/// How wide the app draws its scrollbar.
const double kAnsiScrollbarThickness = 8;

/// How far clear of the pane's edge the bar sits.
const double kAnsiScrollbarMargin = 2;

/// The thumb's ink: the app's muted grey, thinned to a fifth.
///
/// Not the hairline ([AnsiColors.line]): a rule you read past and a thing you
/// grab are different jobs, and at 8 px wide on paper the hairline is a
/// smudge. Not a new colour either — it is [AnsiColors.muted] at a weight.
const Color kAnsiScrollbarThumb = Color(0x4066736A);

/// The air between the last control in a row and the scrollbar's near edge.
const double kAnsiScrollbarClearance = 8;

/// The room a wide pane keeps on its right for the scrollbar, and for air.
///
/// Derived rather than typed: widen the bar and the gutter widens with it, so
/// the two halves of this file cannot drift apart.
const double kAnsiScrollGutter =
    kAnsiScrollbarThickness + kAnsiScrollbarMargin + kAnsiScrollbarClearance;

/// The gutter [context]'s pane owes the scrollbar: [kAnsiScrollGutter] once the
/// chrome is beside the content, and nothing while it is under it.
///
/// Zero on a phone and in a half-screen window on purpose — see the library
/// doc. Reads the shell's form, so a pane that calls this rebuilds on resize.
double ansiScrollGutter(BuildContext context) =>
    AnsiShell.of(context).beside ? kAnsiScrollGutter : 0;

/// [base] with [ansiScrollGutter] added to its right edge.
///
/// The way a wide pane's scroll view states its padding: the phone's number
/// stays written down as the phone's number, and the gutter is added to it
/// rather than replacing it.
///
/// ```dart
/// ListView(padding: ansiScrollPadding(context, const EdgeInsets.all(20)), ...)
/// ```
EdgeInsets ansiScrollPadding(BuildContext context, EdgeInsets base) =>
    base.copyWith(right: base.right + ansiScrollGutter(context));

/// The app's scrollbar: drawn where the app wants it, in the app's hairline.
///
/// Installed once at the root, so this is the scrollbar for every list, sheet
/// and pane in the app.
///
/// **On a mouse platform** the bar is always visible. A thumb that appears only
/// once you have already scrolled is no use to someone deciding *whether* to:
/// on the web a list that reaches past the fold has to say so at rest.
///
/// **On a touch platform** no bar is drawn at all, which is what the phone has
/// always looked like — Flutter's own iOS/Android behaviours draw a fading hint
/// only while a drag is in flight, and reproducing that is not worth a second
/// code path.
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
      // A horizontal strip — the unit chips, a day's columns — is scrolled by
      // the wheel and by its own edges; a bar under it would eat a row of the
      // content it is measuring.
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
