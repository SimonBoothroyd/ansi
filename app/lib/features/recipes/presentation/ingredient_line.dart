/// The v3 three-part ingredient line (LOCKED design): a fixed-width amount
/// column, the ingredient identity with its notes as a muted-italic modifier,
/// and — in an editable context — a pinned-right edit pencil.
///
/// The amount column is a FIXED width so the identity left-aligns on every row
/// regardless of amount length; a long (or joined multi-use) amount wraps
/// within its own column, and the notes wrap in the identity column. A
/// multi-use identity joins each use's amount with " + " and its notes in
/// parallel — never summed (invariant 3). Shared by the recipe page and the
/// import preview so the preview reads exactly as the saved recipe will.
///
/// **A component line is an ordinary line** (step 8.6 / D1, design board frame
/// a): same amount column, same note modifier — only the identity cell
/// changes, to a [RecipeChip] that pushes the target's page. A component whose
/// target is missing (a sync race, D5) degrades to the plain text it stored,
/// muted, and says so; nothing derived, nothing invented.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../domain/line_display.dart';
import '../domain/recipe.dart';
import 'format.dart';
import 'recipe_chip.dart';

class RecipeIngredientLine extends StatelessWidget {
  const RecipeIngredientLine({
    required this.uses,
    this.onEditAmount,
    this.onOpenSubRecipe,
    super.key,
  });

  final LineUses uses;

  /// When set, the row shows a pinned-right edit pencil and the amount column
  /// is tappable — the editable preview's tap-to-edit-amount gesture. Null on
  /// the read-only recipe page.
  final VoidCallback? onEditAmount;

  /// Pushes a component row's target recipe (step 8.6). Null where navigating
  /// away would be wrong — the import review preview, where the recipe does
  /// not exist yet.
  final ValueChanged<String>? onOpenSubRecipe;

  /// The amount column width (design board `.l3` grid): wide enough for
  /// "400 g" or "2 tin", narrow enough that a long joined amount wraps.
  static const double _amountWidth = 84;

  @override
  Widget build(BuildContext context) {
    final amount = uses.uses
        .map(amountOfLineItem)
        .where((a) => a.isNotEmpty)
        .join(' + ');
    final notes = uses.notes.join(' + ');
    // An imprecise line ("a pinch") reads in italic mono — a printed number
    // would misrepresent it (invariant 3).
    final imprecise = uses.uses.every(
      (u) => u.measure == null && u.unit.family == UnitFamily.imprecise,
    );

    final amountText = Text(
      amount,
      style: ansiMono(
        size: 15,
        color: AnsiColors.muted,
      ).copyWith(fontStyle: imprecise ? FontStyle.italic : FontStyle.normal),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _amountWidth,
                child: onEditAmount == null
                    ? amountText
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onEditAmount,
                        child: amountText,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Identity(
                  uses: uses,
                  notes: notes,
                  onOpen: onOpenSubRecipe,
                ),
              ),
              if (onEditAmount != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEditAmount,
                  child: const Icon(
                    FLucideIcons.pencil,
                    size: 14,
                    color: AnsiColors.herb,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(height: 1, color: AnsiColors.line),
      ],
    );
  }
}

/// The identity cell: an ingredient's name, or a component's recipe chip —
/// with the notes as the same muted-italic modifier either way.
class _Identity extends StatelessWidget {
  const _Identity({required this.uses, required this.notes, this.onOpen});

  final LineUses uses;
  final String notes;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final target = uses.uses.first.subRecipe;
    final noteStyle = ansiSans(
      size: 16,
      color: AnsiColors.muted,
    ).copyWith(fontStyle: FontStyle.italic);

    // A component whose target resolved: the chip IS the identity, with the
    // note beside it exactly as an ingredient's would be.
    if (uses.isComponent && target != null) {
      final id = target.id;
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          RecipeChip(
            title: target.title,
            onTap: onOpen == null ? null : () => onOpen!(id),
          ),
          if (notes.isNotEmpty) Text(notes, style: noteStyle),
        ],
      );
    }

    // A dangling link (D5) reads as the plain text it stored, muted, and says
    // why there is no chip. An ingredient row is the first branch's `else`.
    final dangling = uses.isComponent;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: uses.ingredientName,
            style: dangling
                ? ansiSans(size: 16, color: AnsiColors.muted)
                : ansiSans(size: 16, weight: FontWeight.w500),
          ),
          for (final part in [
            if (notes.isNotEmpty) notes,
            if (dangling) 'linked recipe missing',
          ]) ...[
            TextSpan(
              text: '  ·  ',
              style: ansiSans(size: 16, color: AnsiColors.line),
            ),
            TextSpan(text: part, style: noteStyle),
          ],
        ],
      ),
    );
  }
}

/// One use's amount string: quantity + measure/unit, in the recipe page's data
/// voice. A count unit shows only its number ("6"); a measure or a mass/volume
/// unit shows "2 tin" / "400 g"; an imprecise unit its label ("a pinch").
String amountOfLineItem(LineItem item) {
  final qty = formatQuantity(item.quantity);
  final measure = item.measure;
  if (measure != null) {
    return qty.isEmpty ? measure.label : '$qty ${measure.label}';
  }
  if (item.unit.family == UnitFamily.count) {
    return qty.isEmpty ? item.unit.label : qty;
  }
  if (qty.isEmpty) return item.unit.label;
  return '$qty ${item.unit.label}';
}
