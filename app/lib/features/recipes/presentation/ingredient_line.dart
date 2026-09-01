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
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../domain/line_display.dart';
import '../domain/recipe.dart';
import 'format.dart';

class RecipeIngredientLine extends StatelessWidget {
  const RecipeIngredientLine({
    required this.uses,
    this.onEditAmount,
    super.key,
  });

  final LineUses uses;

  /// When set, the row shows a pinned-right edit pencil and the amount column
  /// is tappable — the editable preview's tap-to-edit-amount gesture. Null on
  /// the read-only recipe page.
  final VoidCallback? onEditAmount;

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
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: uses.ingredientName,
                        style: ansiSans(size: 16, weight: FontWeight.w500),
                      ),
                      if (notes.isNotEmpty) ...[
                        TextSpan(
                          text: '  ·  ',
                          style: ansiSans(size: 16, color: AnsiColors.line),
                        ),
                        TextSpan(
                          text: notes,
                          style: ansiSans(
                            size: 16,
                            color: AnsiColors.muted,
                          ).copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
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
