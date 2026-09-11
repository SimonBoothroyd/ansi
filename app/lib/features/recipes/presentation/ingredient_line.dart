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
/// **An ingredient's name is the same kind of door**, opt-in through
/// [RecipeIngredientLine.onOpenIngredient]: on the recipe page it opens that
/// ingredient's own page, the way a component's chip opens its recipe. It is
/// a callback rather than a baked-in push because the import preview draws
/// the same line for rows that name nothing the household owns yet.
///
/// **An optional line carries a tag after the note** (board frame e2) in the
/// stub badge's voice, because it is the same kind of claim — a fact about the
/// line that changes what a total covers. It sits in the identity column, never
/// the amount column: "1 lime" is still what the recipe says.
///
/// **[RecipeIngredientLine.macroLine] is opt-in**, because the import preview
/// shares this widget and has no summation behind it: the recipe page passes
/// the line's own figures when its per-line toggle is on, or the reason there
/// are none, and everything else passes neither. The caller decides which of
/// the two it is — this file never computes a number.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../../ingredients/presentation/macro_line_text.dart';
import '../domain/line_display.dart';
import '../domain/recipe.dart';
import 'recipe_chip.dart';

/// The amount column's width (design board `.l3` grid): wide enough for
/// "400 g" or "2 tin", narrow enough that a long joined amount wraps.
///
/// The one number every three-part line aligns on — the recipe page here, the
/// import review's collapsed row, and the recipe editor's line. They are one
/// layout, so they share the measurement rather than each holding an 84.
const double kLineAmountWidth = 84;

class RecipeIngredientLine extends StatelessWidget {
  const RecipeIngredientLine({
    required this.uses,
    this.onEditAmount,
    this.onOpenSubRecipe,
    this.onOpenIngredient,
    this.macroMarker,
    this.macroLine,
    this.macroLineNote,
    this.onFixMacro,
    super.key,
  });

  final LineUses uses;

  /// This row's own macros, at the amount the row is showing — `142 🔥 ·
  /// 3P 11F 8C`. Null when the page's per-line toggle is off, and null on
  /// every surface that has no summary to read.
  ///
  /// It sits under the identity, not under the amount: it is a fact about the
  /// ingredient at this amount, and the amount column belongs to what the
  /// recipe says. [macroMarker] is the amount column's, and the two never say
  /// the same thing twice — the caller passes null here when the marker is
  /// already printing the reason.
  ///
  /// It is a dense line, so energy is a glyph rather than the word
  /// ([MacroLineText]).
  final Macros? macroLine;

  /// The line's slot when there are no figures for it: the reason the total
  /// left this row out, in the macro panel's own words. Never set beside
  /// [macroLine] — a row has figures or it has a reason.
  final String? macroLineNote;

  /// Why this row is left out of the macro total, in the shared per-line
  /// words (seam **D5**) — `needs a piece weight`, `stub ingredient`. Null
  /// when the row is in the total, or when the caller has no summary to read.
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

  /// The muted mono the macro slot is drawn in, whichever of its two things
  /// it is holding — one style, so the figures and the reason read as the
  /// same aside under the name.
  static final _lineStyle = ansiMono(
    size: 10.5,
    color: AnsiColors.muted,
  ).copyWith(height: 1.3);

  /// Pushes a component row's target recipe (step 8.6). Null where navigating
  /// away would be wrong — the import review preview, where the recipe does
  /// not exist yet.
  final ValueChanged<String>? onOpenSubRecipe;

  /// Pushes an ingredient row's own page, given the row's resolved
  /// [LineUses.ingredientId]. Null where the row has nowhere to go: the
  /// import review preview, and any row that resolved to no ingredient.
  final ValueChanged<String>? onOpenIngredient;

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
                width: kLineAmountWidth,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Identity(
                      uses: uses,
                      notes: notes,
                      onOpen: onOpenSubRecipe,
                      onOpenIngredient: onOpenIngredient,
                    ),
                    if (macroLine != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: MacroLineText(macroLine!, style: _lineStyle),
                      )
                    else if (macroLineNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(macroLineNote!, style: _lineStyle),
                      ),
                  ],
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
///
/// Stateful only to own the name span's tap recognizer. The door is the NAME
/// span rather than the cell: the cell is stretched to the full width of the
/// row, so a cell-wide gesture would answer for the blank paper beside a short
/// name — and for the note, which is a fact about the line, not the identity.
class _Identity extends StatefulWidget {
  const _Identity({
    required this.uses,
    required this.notes,
    this.onOpen,
    this.onOpenIngredient,
  });

  final LineUses uses;
  final String notes;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onOpenIngredient;

  @override
  State<_Identity> createState() => _IdentityState();
}

class _IdentityState extends State<_Identity> {
  final _openIngredient = TapGestureRecognizer();

  @override
  void dispose() {
    _openIngredient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uses = widget.uses;
    final notes = widget.notes;
    final onOpen = widget.onOpen;
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
            onTap: onOpen == null ? null : () => onOpen(id),
          ),
          if (notes.isNotEmpty) Text(notes, style: noteStyle),
          if (optional) const OptionalTag(),
        ],
      );
    }

    // A dangling link (D5) reads as the plain text it stored, muted, and says
    // why there is no chip. An ingredient row is the first branch's `else`.
    final dangling = uses.isComponent;
    final ingredientId = uses.ingredientId;
    final openIngredient = widget.onOpenIngredient;
    final nameIsDoor = ingredientId != null && openIngredient != null;
    _openIngredient.onTap = nameIsDoor
        ? () => openIngredient(ingredientId)
        : null;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: uses.ingredientName,
            style: dangling
                ? ansiSans(size: 16, color: AnsiColors.muted)
                : ansiSans(size: 16, weight: FontWeight.w500),
            recognizer: nameIsDoor ? _openIngredient : null,
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
