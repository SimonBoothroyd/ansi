/// The one hover, focus and cursor answer for a glyph-only control.
///
/// Hover and press put a `colors.secondary` ground under the glyph and ink it
/// `colors.secondaryForeground`; focus draws the theme's ring; the hit area
/// is at least [ansiTapTarget]. Pass the rest ink as `color` and leave the
/// child [Icon] uncoloured, or hover cannot re-ink it. Held by
/// `test/structure/glyph_controls_answer_a_pointer_test.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_tokens.dart';

/// The smallest a control should be under a finger. Not applied: call sites
/// carry their own padding on a phone.
const double kAnsiTouchTarget = 44;

/// The smallest a control may be under a mouse, and the size at which the
/// hover ground reads as a control.
const double kAnsiPointerTarget = 32;

/// The minimum target: [kAnsiPointerTarget] under a mouse, zero under a
/// finger. Read from the platform, not the window: a narrow desktop window
/// is still driven by a mouse.
double get ansiTapTarget => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => 0,
  _ => kAnsiPointerTarget,
};

/// A glyph-only control with the app's one hover, focus and cursor.
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

  /// The glyph: usually a bare [Icon] or a one-letter [Text].
  final Widget child;

  /// The room around the glyph, inside the ground.
  final EdgeInsets padding;

  /// The ground's corner radius, and the focus ring's.
  final double radius;

  /// The glyph's ink at rest, published through an [IconTheme] so hover can
  /// replace it. Null leaves the ink to the child.
  final Color? color;

  /// Whether the target grows to [ansiTapTarget] square on a mouse. False
  /// for a control whose row is the geometry, like the A–Z margin's letters.
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
