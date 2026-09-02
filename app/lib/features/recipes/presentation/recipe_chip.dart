/// The identity cell a **component** line wears (step 8.6 / D1, design board
/// frames a · d · h): the board's `.ichip` — a paper pill with the
/// cross-reference glyph and the target recipe's title.
///
/// It is the one place the "this line is a recipe" signal is drawn, so the
/// recipe page, the editor row, the picker row and the quantity sheet cannot
/// drift apart. The glyph is [FLucideIcons.cornerDownRight] — the board's "↪";
/// a raw unicode arrow would render as tofu, the bundled fonts having no such
/// glyph (the library_view rule).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';

/// The glyph every sub-recipe reference is marked with.
const kSubRecipeIcon = FLucideIcons.cornerDownRight;

class RecipeChip extends StatelessWidget {
  const RecipeChip({
    required this.title,
    this.onTap,
    this.size = 15,
    super.key,
  });

  final String title;

  /// Pushes the target's page when set. Null wherever navigating away would
  /// be wrong (the import review card, a read-only preview).
  final VoidCallback? onTap;

  final double size;

  @override
  Widget build(BuildContext context) {
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kSubRecipeIcon, size: size - 3, color: AnsiColors.herb),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: ansiSans(
                  size: size,
                  color: AnsiColors.herbDeep,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}
