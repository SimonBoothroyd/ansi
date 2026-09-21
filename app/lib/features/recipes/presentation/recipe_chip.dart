/// The identity cell of a component line: a paper pill with the cross-reference
/// glyph and the target recipe's title. Shared by the recipe page, the editor
/// row, the picker row and the quantity sheet. The glyph is
/// [FLucideIcons.cornerDownRight]; the bundled fonts have no unicode arrow.
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

  /// Pushes the target's page. Null where navigating away would be wrong (the
  /// import review card, a read-only preview).
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
