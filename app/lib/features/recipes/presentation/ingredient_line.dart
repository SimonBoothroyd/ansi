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
/// sub-recipe chip's shape, because it is the same kind of claim — a fact
/// about the line that changes what a total covers. It sits in the identity
/// column, never the amount column: "1 lime" is still what the recipe says.
/// The tag is also the whole statement: a tagged row prints nothing in its
/// macro slot, because *optional* twice on one line is once too many.
///
/// **Where a week owns the page, that tag is a switch**
/// ([RecipeIngredientLine.onToggleOptional]): `optional` with an empty ring
/// becomes `included` with a check, and the week stores the answer. Optional
/// has two owners — the recipe says *may be skipped*, the week says *this
/// time, yes* — and only a surface that holds a week can answer the second.
/// Without the callback the tag is what it has always been: a fact, and
/// nothing to tap.
///
/// **A line the week leaves out reads struck and muted**
/// ([RecipeIngredientLine.struck]), amount and name alike — the grammar week
/// mode draws, here read-only.
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
    this.struck = false,
    this.included = false,
    this.onToggleOptional,
    super.key,
  });

  final LineUses uses;

  /// Whether this week leaves the row out: the amount and the name are struck
  /// and muted, as week mode draws them. False everywhere no week is in play.
  final bool struck;

  /// Whether this week has ticked the row's optional line(s) IN — the tag then
  /// reads `included` rather than `optional`.
  final bool included;

  /// Ticks the row's optional line(s) in for this week, or back out; the
  /// argument is what the row is to BECOME. Set only where a week owns the
  /// page, which is the only place the question exists: from the Library the
  /// tag states a fact and writes nothing.
  final ValueChanged<bool>? onToggleOptional;

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
    size: 10,
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
      style: ansiMono(size: 15, color: AnsiColors.muted).copyWith(
        fontStyle: imprecise ? FontStyle.italic : FontStyle.normal,
        decoration: struck ? TextDecoration.lineThrough : null,
      ),
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
                      struck: struck,
                      included: included,
                      onToggleOptional: onToggleOptional,
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
    this.struck = false,
    this.included = false,
    this.onToggleOptional,
  });

  final LineUses uses;
  final String notes;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onOpenIngredient;
  final bool struck;
  final bool included;
  final ValueChanged<bool>? onToggleOptional;

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
    // a line here is left out of the totals, and one is. A row this week
    // ticked in wears the same tag, lit — the week cleared the flag, and the
    // answer it gave is what the tag is now saying.
    final optional = uses.uses.any((u) => u.optional) || widget.included;

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
          if (optional)
            OptionalTag(
              included: widget.included,
              onToggle: widget.onToggleOptional,
            ),
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
            style:
                (dangling || widget.struck
                        ? ansiSans(size: 16, color: AnsiColors.muted)
                        : ansiSans(size: 16, weight: FontWeight.w500))
                    .copyWith(
                      decoration: widget.struck
                          ? TextDecoration.lineThrough
                          : null,
                    ),
            recognizer: nameIsDoor ? _openIngredient : null,
          ),
          // Two spaces, no middle dot: the note is a modifier of the name
          // ("Onion  finely chopped"), and a separator between them promised
          // two facts where there is one.
          for (final part in [
            if (notes.isNotEmpty) notes,
            if (dangling) 'linked recipe missing',
          ])
            TextSpan(text: '  $part', style: noteStyle),
          ...optionalSpans(
            optional: optional,
            included: widget.included,
            onToggle: widget.onToggleOptional,
          ),
        ],
      ),
    );
  }
}

/// The `optional` tag as a run of spans, so every three-part line — the page's,
/// the editor's, the week's — hangs it off the end of the identity in one
/// voice rather than each surface inventing its own placement. Empty when the
/// line is not optional.
List<InlineSpan> optionalSpans({
  required bool optional,
  bool included = false,
  ValueChanged<bool>? onToggle,
}) => optional
    ? [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OptionalTag(included: included, onToggle: onToggle),
          ),
        ),
      ]
    : const [];

/// The `optional` tag: the sub-recipe chip's shape — a 6 px box in the herb
/// wash, muted mono — because it is the same kind of mark on the same kind of
/// line, and a second pill geometry beside [RecipeChip] read as a second
/// vocabulary. Public so the page test can find it by type.
///
/// **With [onToggle] it is the switch**, and the shape says so: an empty ring
/// before the word, the way a box a person may tick is drawn. Ticked, the box
/// fills — herb, paper text, a check where the ring was — and the word becomes
/// `included`. Same radius, same padding, so the answer changes without the
/// line moving.
class OptionalTag extends StatelessWidget {
  const OptionalTag({this.included = false, this.onToggle, super.key});

  /// Whether the week has ticked this line in. Drawn filled, and the word is
  /// `included`.
  final bool included;

  /// Ticks the line in or back out; the argument is what it is to BECOME.
  /// Null everywhere the tag only states a fact.
  final ValueChanged<bool>? onToggle;

  /// The tap target's height where the tag is a switch. A 10 pt badge is a
  /// small thing to hit, so the target is padded out to a comfortable one
  /// rather than the badge drawn bigger — week mode's own idiom.
  static const double switchHitHeight = 44;

  @override
  Widget build(BuildContext context) {
    final onToggle = this.onToggle;
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: included ? AnsiColors.herb : AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (included)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  FLucideIcons.check,
                  size: 9,
                  color: AnsiColors.paper,
                ),
              )
            else if (onToggle != null)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: _EmptyRing(),
              ),
            Text(
              included ? 'included' : 'optional',
              style: ansiMono(
                size: 10,
                color: included ? AnsiColors.paper : AnsiColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
    if (onToggle == null) return badge;
    return Semantics(
      label: included
          ? 'included this week · tap to leave it out'
          : 'optional · tap to include this week',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggle(!included),
        child: Container(
          constraints: const BoxConstraints(minHeight: switchHitHeight),
          alignment: Alignment.center,
          child: badge,
        ),
      ),
    );
  }
}

/// The unticked box: an empty ring before the word, so the tag reads as a
/// question rather than a label before anybody has touched it.
class _EmptyRing extends StatelessWidget {
  const _EmptyRing();

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: AnsiColors.muted, width: 1.5),
    ),
  );
}

/// One use's amount string — [amountOfLine], which is where the words live so
/// that the week's variant and the shopping list can quote a line's amount in
/// exactly the voice the recipe page prints it in.
String amountOfLineItem(LineItem item) => amountOfLine(item);
