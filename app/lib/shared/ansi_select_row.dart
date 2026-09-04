/// A bordered row you pick one of: a name, a tick when it is the pick, and a
/// herb outline instead of a fill so the unpicked rows stay legible.
///
/// The two filing sheets pick a shelf this way.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

class AnsiSelectRow extends StatelessWidget {
  const AnsiSelectRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
    this.enabled = true,
    this.labelSize = 15,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The quiet mono aside a row can carry — "here now", the shelf the recipe
  /// is on already.
  final String? note;

  /// False greys the row and refuses the tap: a "move" that moves nothing is
  /// a tap that lies about what it did.
  final bool enabled;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(AnsiRadii.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: ansiSerif(
                  size: labelSize,
                  color: enabled ? AnsiColors.ink : AnsiColors.muted,
                ),
              ),
            ),
            if (note case final note?)
              Text(note, style: ansiMono(size: 10, color: AnsiColors.muted)),
            if (selected)
              const Icon(FLucideIcons.check, size: 16, color: AnsiColors.herb),
          ],
        ),
      ),
    );
  }
}
