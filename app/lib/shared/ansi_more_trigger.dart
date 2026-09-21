/// The `⋯` that opens a menu.
///
/// The default is a ghost icon button. [AnsiMoreTrigger.inline] is the bare
/// glyph for a dense row. It draws the trigger only; the [FPopoverMenu] that
/// owns it holds the menu.
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
      // The gap stays outside the tap and its hover ground.
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
    // Forui's ghost variant already hovers and rings with the tokens
    // [AnsiTap] uses.
    return FButton.icon(
      variant: FButtonVariant.ghost,
      size: compact ? FButtonSizeVariant.sm : FButtonSizeVariant.md,
      onPress: onTap,
      child: Icon(FLucideIcons.ellipsis, size: size, color: color),
    );
  }
}
