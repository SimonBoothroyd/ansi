/// **The one answer a glyph gives a pointer.**
///
/// A `⋯`, a `−`, a fold chevron, a letter in the A–Z margin: a control whose
/// whole body is one mark. On a phone that is enough — a finger arrives at the
/// glyph and the thing happens. On a desk it is not: a mouse asks *is this a
/// door?* before it clicks, and a keyboard asks *where am I?* before it
/// presses. Neither question has an answer unless the control gives one.
///
/// Before this, every glyph in the app was a bare [GestureDetector], so the
/// answer was the same everywhere and it was *nothing*: no ground, no ring, and
/// — because Forui's [FTappableStyle] defaults its cursor to
/// [MouseCursor.defer] — not even a pointer.
///
/// `AnsiTap` is the answer, said once:
///
/// * **hover / press** — a ground of `colors.secondary` (herb-soft) under the
///   glyph, and the glyph itself in `colors.secondaryForeground` (herb-deep).
/// * **focus** — the theme's outline: 2 px herb, 2 px clear of the target
///   (`core/theme/ansi_theme.dart` sets it for the whole app, so a Forui
///   button and a swept glyph ring identically).
/// * **cursor** — a click cursor, from the theme's [FTappableStyle].
/// * **hit area** — at least [ansiTapTarget] square, which is 32 where a mouse
///   is doing the pointing and, on purpose, the call site's own padding where a
///   finger is (see [kAnsiTouchTarget]).
///
/// Those two colours are not new numbers. They are the pair Forui's own
/// `FButtonVariant.ghost` already hovers with, which is why a `⋯` drawn as a
/// ghost [FButton] and a `⋯` drawn as an [AnsiTap] read as the same control in
/// two shapes rather than as two controls.
///
/// **Nothing here changes the phone.** A ground only exists while a pointer is
/// over the control or a finger is down on it, and a phone has no pointer; the
/// ring only exists under focus traversal, which a phone has no key for; and
/// the minimum target is zero where the pointer is a finger, so no swept
/// control's geometry moves by a pixel on a phone.
///
/// ## Using it
///
/// The call site hands over its padding and its rest ink, because the ground
/// has to cover the *target* rather than the glyph, and the hover ink has to
/// replace something:
///
/// ```dart
/// AnsiTap(
///   onTap: remove,
///   padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
///   color: AnsiColors.muted,
///   child: const Icon(FLucideIcons.minus, size: 16),
/// )
/// ```
///
/// The [Icon] carries no colour of its own: `color` is published through an
/// [IconTheme] so [AnsiTap] can take it back on hover. An [Icon] that keeps an
/// explicit `color:` opts itself out of the herb-deep half and keeps only the
/// ground — which is why the sweep stripped them.
///
/// `test/structure/glyph_controls_test.dart` holds the sweep: a bare tap around
/// an icon-only child fails the build, with a named allow-list for the few that
/// must stay.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_tokens.dart';

/// The smallest a control **should** be where the pointer is a finger.
///
/// Written down, and deliberately not applied. The phone's glyphs are smaller
/// than this today — a `−` on a Week card is 28×36, the `×` on the copy report
/// is 13 square — and growing every one of them to 44 from underneath would
/// re-lay-out the week card, the header row and every dense line. This pass was
/// asked to leave the phone alone, so it does. Raising the phone's targets is a
/// real pass and a separate one, and it should move the padding at the call
/// sites, where it can be seen, rather than pad them invisibly from here.
const double kAnsiTouchTarget = 44;

/// The smallest a control may be where the pointer is a mouse.
///
/// Smaller than [kAnsiTouchTarget] on purpose: a cursor is a pixel and a
/// fingertip is a centimetre. It is also the number that makes the hover ground
/// *legible* — a herb-soft tint the size of a 14 px chevron reads as a smudge,
/// and at 32 square it reads as a control.
const double kAnsiPointerTarget = 32;

/// The smallest a control may be, in this build's idiom: [kAnsiPointerTarget]
/// where a mouse is doing the pointing, and whatever padding the call site
/// already carries where a finger is.
///
/// Read from the platform rather than from the window: a narrow window on a
/// desk is still driven by a mouse, and a landscape iPad is still driven by a
/// finger. It is the question `AnsiLayout` refuses to answer — that file is
/// about how much room there is, this is about what is doing the pointing.
double get ansiTapTarget => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => 0,
  _ => kAnsiPointerTarget,
};

/// A glyph-only control, with the app's one hover, focus and cursor.
///
/// See the library doc for the contract.
class AnsiTap extends StatelessWidget {
  const AnsiTap({
    required this.onTap,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AnsiRadii.box,
    this.color,
    this.minTarget = true,
    this.semanticsLabel,
    super.key,
  });

  /// What the control does. Null disables it: no ground, no ring, no cursor.
  final VoidCallback? onTap;

  /// The glyph — usually a bare [Icon] or a one-letter [Text].
  final Widget child;

  /// The room around the glyph. It belongs to [AnsiTap] rather than to the
  /// call site so the ground covers the whole target and not just the mark.
  final EdgeInsets padding;

  /// The ground's corner radius, and the focus ring's.
  final double radius;

  /// The glyph's ink at rest, published through an [IconTheme] so hover can
  /// take it back. Null leaves the ink to whatever the child sets — which is
  /// what a control drawing text in its own style wants.
  final Color? color;

  /// Whether the target is grown to [ansiTapTarget] square on a mouse.
  ///
  /// True is the default and the right answer nearly everywhere. False is for a
  /// control whose *row* is the geometry — the A–Z margin's letters, where
  /// twenty-seven 32 px rows would be a column, not a margin.
  final bool minTarget;

  /// {@macro forui.foundation.doc_templates.semanticsLabel}
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final target = minTarget ? ansiTapTarget : 0.0;
    return FTappable(
      onPress: onTap,
      semanticsLabel: semanticsLabel,
      behavior: HitTestBehavior.opaque,
      focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
        borderRadius: BorderRadius.circular(radius),
      ),
      builder: (context, variants, child) {
        final lit =
            variants.contains(FTappableVariant.hovered) ||
            variants.contains(FTappableVariant.pressed);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: lit ? colors.secondary : const Color(0x00000000),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: color == null && !lit
              ? child!
              : IconTheme.merge(
                  data: IconThemeData(
                    color: lit ? colors.secondaryForeground : color,
                  ),
                  child: child!,
                ),
        );
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: target, minHeight: target),
        child: Padding(
          padding: padding,
          // The glyph keeps its place in a target grown around it.
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}
