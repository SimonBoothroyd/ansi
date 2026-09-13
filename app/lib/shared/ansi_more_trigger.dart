/// The `⋯` that opens a menu — the same glyph, at the same weight, wherever a
/// thing has more to offer than fits beside it.
///
/// The default is a ghost icon button, which is what a menu deserves: a tap
/// target the size of a finger. [AnsiMoreTrigger.inline] is the bare glyph for
/// a dense row that already ends in two other controls, where a button's own
/// padding would push them off the edge.
///
/// It draws the trigger only. What the menu holds — and hiding it before an
/// item acts — stays with the [FPopoverMenu] that owns it.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'ansi_tap.dart';

class AnsiMoreTrigger extends StatelessWidget {
  const AnsiMoreTrigger({
    required this.onTap,
    this.size = 18,
    this.color,
    this.compact = false,
    super.key,
  }) : _bare = false;

  /// The glyph alone, with [gap] of room before it.
  const AnsiMoreTrigger.inline({
    required this.onTap,
    this.size = 15,
    this.color,
    super.key,
  }) : _bare = true,
       compact = false;

  final VoidCallback onTap;
  final double size;
  final Color? color;

  /// The small button, for a section header rather than a screen header.
  final bool compact;

  final bool _bare;

  static const double gap = 8;

  @override
  Widget build(BuildContext context) {
    if (_bare) {
      // The gap stays OUTSIDE the tap. It is the space between this control
      // and the one before it, and a hover ground that reached into it would
      // read as one wide target rather than as the `⋯`.
      return Padding(
        padding: const EdgeInsets.only(left: gap),
        child: AnsiTap(
          onTap: onTap,
          color: color,
          semanticsLabel: 'More',
          child: Icon(FLucideIcons.ellipsis, size: size),
        ),
      );
    }
    // The button shape is left to Forui. `FButtonVariant.ghost` already hovers
    // with `secondary` under `secondaryForeground` — the same two tokens
    // [AnsiTap] uses — and rings with the theme's outline, so re-drawing it as
    // an [AnsiTap] would buy nothing and would re-size a phone control.
    return FButton.icon(
      variant: FButtonVariant.ghost,
      size: compact ? FButtonSizeVariant.sm : FButtonSizeVariant.md,
      onPress: onTap,
      child: Icon(FLucideIcons.ellipsis, size: size, color: color),
    );
  }
}
