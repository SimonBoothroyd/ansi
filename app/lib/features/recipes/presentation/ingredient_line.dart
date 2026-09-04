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
///
/// **An optional line carries a tag after the note** (board frame e2) in the
/// stub badge's voice, because it is the same kind of claim — a fact about the
/// line that changes what a total covers. It sits in the identity column, never
/// the amount column: "1 lime" is still what the recipe says.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../domain/line_display.dart';
import '../domain/recipe.dart';
import 'recipe_chip.dart';

class RecipeIngredientLine extends StatelessWidget {
  const RecipeIngredientLine({
    required this.uses,
    this.onEditAmount,
    this.onOpenSubRecipe,
    this.macroMarker,
    this.onFixMacro,
    super.key,
  });

  final LineUses uses;

  /// Why this row is left out of the macro total, in the shared per-line
  /// words (seam **D5**) — `needs a weight`, `stub ingredient`. Null when the
  /// row is in the total, or when the caller has no summary to read.
  ///
  /// It renders as a small amber dot plus the reason at the end of the amount
  /// column, in **the same amber the import review card uses**, because it is
  /// the same claim: *this line is why a number is missing.*
  final String? macroMarker;

  /// Opens the fix the marker implies. When set, the marker is a door.
  final VoidCallback? onFixMacro;

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (onEditAmount == null)
                      amountText
                    else
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onEditAmount,
                        child: amountText,
                      ),
                    if (macroMarker != null)
                      _MacroMarker(label: macroMarker!, onTap: onFixMacro),
                  ],
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

/// The in-place marker (seam **D5**): an amber dot and the reason, under the
/// amount. Marked in place because on a long recipe the panel is below the
/// fold, and reading a name there and then hunting for the row is the failure
/// this replaces.
class _MacroMarker extends StatelessWidget {
  const _MacroMarker({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AnsiColors.aging,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              style: ansiMono(
                size: 9.5,
                color: AnsiColors.muted,
              ).copyWith(height: 1.3),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
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
    // A folded multi-use row is tagged if ANY use is optional: the tag says
    // a line here is left out of the totals, and one is.
    final optional = uses.uses.any((u) => u.optional);

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
          if (optional) const OptionalTag(),
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
          if (optional)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: OptionalTag(),
              ),
            ),
        ],
      ),
    );
  }
}

/// The `optional` tag (board frame e2's `.r3-tag`): the stub badge's exact
/// voice — `FBadge.secondary`, muted mono — so a reader who knows one knows
/// the other. Public so the page test can find it by type.
class OptionalTag extends StatelessWidget {
  const OptionalTag({super.key});

  @override
  Widget build(BuildContext context) {
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Text(
        'optional',
        style: ansiMono(size: 10, color: AnsiColors.muted),
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
