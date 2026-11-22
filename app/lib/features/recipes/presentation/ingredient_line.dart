/// The three-part ingredient line: a fixed-width amount column, the identity
/// with its note as a muted-italic modifier, and an edit pencil where editable.
/// Shared by the recipe page and the import preview.
///
/// A multi-use identity joins each use's amount with " + ", never summed. A
/// component line's identity is a [RecipeChip]; a missing target or a retired
/// ingredient reads as its stored text, muted and tagged. Tags, week state and
/// macro figures are all passed in: this file computes no number.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_tap.dart';
import '../../ingredients/presentation/macro_line_text.dart';
import '../domain/line_display.dart';
import '../domain/method_uses.dart';
import '../domain/recipe.dart';
import 'recipe_chip.dart';

/// The amount column's width, shared by the recipe page, the import review's
/// collapsed row and the editor's line so identities align.
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
    this.scaled = false,
    this.picked,
    this.onPick,
    this.quotes = const [],
    super.key,
  });

  final LineUses uses;

  /// Where a week asks about an optional row: whether it is in. Non-null puts
  /// the `optional` pill at the row's end as its switch ([OptionalPick]); out,
  /// the row greys. Null where nothing asks (the Library), and the tag after
  /// the name is then the recipe's own fact.
  final bool? picked;

  /// Flips [picked]. Null leaves the pill inert: the week states an amount,
  /// which is changed in the week's editor.
  final VoidCallback? onPick;

  /// The steps that use this row, quoted under the name: how an optional
  /// ingredient is used, at a glance.
  final List<StepUse> quotes;

  /// Whether [uses] are scaled off the recipe's own servings, so each amount
  /// prints as a cook measures it ([amountOfLine]).
  final bool scaled;

  /// Whether this week leaves the row out: amount and name struck and muted.
  final bool struck;

  /// This row's macros at the amount shown (`142 🔥 · 3P 11F 8C`), drawn under
  /// the identity. Null when the per-line toggle is off, when [macroMarker]
  /// already prints the reason, or when the surface has no summary.
  final Macros? macroLine;

  /// Why the total left this row out, in the macro panel's words. Never set
  /// beside [macroLine].
  final String? macroLineNote;

  /// Why this row is out of the macro total (`needs a piece weight`, `stub
  /// ingredient`), drawn as an amber dot and the reason under the amount. Null
  /// when the row is counted or there is no summary.
  final String? macroMarker;

  /// Opens the fix the marker implies. When set, the marker is a door.
  final VoidCallback? onFixMacro;

  /// When set, the row shows an edit pencil and the amount column is tappable.
  /// Null on the read-only recipe page.
  final VoidCallback? onEditAmount;

  /// The muted mono of the macro slot, for figures and reason alike.
  static final _lineStyle = ansiMono(
    size: 10,
    color: AnsiColors.muted,
  ).copyWith(height: 1.3);

  /// Pushes a component row's target recipe. Null in the import preview, where
  /// the recipe does not exist yet.
  final ValueChanged<String>? onOpenSubRecipe;

  /// Pushes an ingredient row's page, given [LineUses.ingredientId]. Null in
  /// the import preview and for a row that resolved to no ingredient.
  final ValueChanged<String>? onOpenIngredient;

  @override
  Widget build(BuildContext context) {
    final amount = uses.uses
        .map((u) => amountOfLineItem(u, scaled: scaled))
        .where((a) => a.isNotEmpty)
        .join(' + ');
    final notes = uses.notes.join(' + ');
    // An imprecise line ("a pinch") reads in italic mono, not as a number.
    final imprecise = uses.uses.every(
      (u) => u.measure == null && u.unit?.family == UnitFamily.imprecise,
    );

    final amountText = Text(
      amount,
      style: ansiMono(size: 15, color: AnsiColors.muted).copyWith(
        fontStyle: imprecise ? FontStyle.italic : FontStyle.normal,
        decoration: struck ? TextDecoration.lineThrough : null,
      ),
    );

    // An optional row the week leaves out greys; its pill stays full strength,
    // because the pill is what puts it back.
    Widget dim(Widget child) =>
        picked == false ? Opacity(opacity: 0.45, child: child) : child;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: kLineAmountWidth,
                child: dim(
                  Column(
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: dim(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Identity(
                        uses: uses,
                        notes: notes,
                        onOpen: onOpenSubRecipe,
                        onOpenIngredient: onOpenIngredient,
                        struck: struck,
                        tagged: picked == null,
                      ),
                      for (final quote in quotes)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: StepQuote(quote),
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
              ),
              if (onEditAmount != null) ...[
                const SizedBox(width: 8),
                AnsiTap(
                  onTap: onEditAmount,
                  semanticsLabel: 'Edit the amount',
                  color: AnsiColors.herb,
                  child: const Icon(FLucideIcons.pencil, size: 14),
                ),
              ],
              if (picked case final picked?) ...[
                const SizedBox(width: 10),
                OptionalPick(
                  picked: picked,
                  onTap: onPick,
                  name: uses.uses.first.subRecipe?.title ?? uses.ingredientName,
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

/// An amber dot and the reason, under the amount — marked in place because the
/// macro panel may be below the fold.
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

/// The identity cell: an ingredient's name or a component's recipe chip, with
/// the note after it.
///
/// Stateful only to own the name span's tap recognizer. The tap target is the
/// name span, not the cell: the cell spans the row's width, so a cell-wide
/// gesture would answer for blank space and the note.
class _Identity extends StatefulWidget {
  const _Identity({
    required this.uses,
    required this.notes,
    this.onOpen,
    this.onOpenIngredient,
    this.struck = false,
    this.tagged = true,
  });

  final LineUses uses;
  final String notes;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onOpenIngredient;
  final bool struck;

  /// Whether an optional use is tagged after the name. False where the row's
  /// pill already says it.
  final bool tagged;

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
    // A folded multi-use row is tagged if any use is optional.
    final optional = widget.tagged && uses.uses.any((u) => u.optional);
    // Every use of a folded row shares one identity.
    final removed = uses.uses.any((u) => u.ingredientDeleted);

    // A resolved component: the chip is the identity.
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

    // A dangling component reads as its stored text, muted.
    final dangling = uses.isComponent;
    final ingredientId = uses.ingredientId;
    final openIngredient = widget.onOpenIngredient;
    // A retired ingredient has no page to open, so its name is not a door.
    final nameIsDoor =
        ingredientId != null && openIngredient != null && !removed;
    _openIngredient.onTap = nameIsDoor
        ? () => openIngredient(ingredientId)
        : null;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: uses.ingredientName,
            // Muted for a missing target, a retired ingredient or a line this
            // week leaves out; struck only for the last.
            style:
                (dangling || removed || widget.struck
                        ? ansiSans(size: 16, color: AnsiColors.muted)
                        : ansiSans(size: 16, weight: FontWeight.w500))
                    .copyWith(
                      decoration: widget.struck
                          ? TextDecoration.lineThrough
                          : null,
                    ),
            recognizer: nameIsDoor ? _openIngredient : null,
          ),
          ...noteSpans(notes, size: 16),
          if (dangling) ...noteSpans('linked recipe missing', size: 16),
          ...optionalSpans(optional: optional),
          ...removedIngredientSpans(removed: removed),
        ],
      ),
    );
  }
}

/// The note as spans after the name, for every surface that prints one: `Garlic
/// · peeled and crushed` — a hairline middle dot, then the note in muted italic
/// at the name's size. Empty without a note. Held by
/// `test/structure/one_note_grammar_test.dart`.
List<InlineSpan> noteSpans(String? note, {double size = 15}) {
  final text = note?.trim();
  if (text == null || text.isEmpty) return const [];
  return [
    TextSpan(
      text: '  ·  ',
      style: ansiSans(size: size, color: AnsiColors.line),
    ),
    TextSpan(
      text: text,
      style: ansiSans(
        size: size,
        color: AnsiColors.muted,
      ).copyWith(fontStyle: FontStyle.italic),
    ),
  ];
}

/// The `optional` tag as spans after the identity. Empty when the line is not
/// optional.
List<InlineSpan> optionalSpans({required bool optional}) => optional
    ? const [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(left: 8),
            child: OptionalTag(),
          ),
        ),
      ]
    : const [];

/// The `optional` tag, in the sub-recipe chip's shape: the recipe's claim that
/// a line may be skipped, and only that. Where a week owns the page the choice
/// is the row's [OptionalPick]. Public so the page test can find it by type.
class OptionalTag extends StatelessWidget {
  const OptionalTag({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AnsiColors.herbSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        'optional',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    ),
  );
}

/// The unticked box: an empty ring before the word. Shared with the line card's
/// `optional` toggle.
class OptionalRing extends StatelessWidget {
  const OptionalRing({super.key});

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

/// The retired-ingredient tag as spans after the identity. Empty when the
/// ingredient is live.
List<InlineSpan> removedIngredientSpans({required bool removed}) => removed
    ? const [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(left: 8),
            child: RemovedIngredientTag(),
          ),
        ),
      ]
    : const [];

/// `ingredient removed · pick again` — the tag on a line whose vocab row was
/// retired ([LineItem.ingredientDeleted]), in [OptionalTag]'s look. The name
/// beside it is the row's last known one.
class RemovedIngredientTag extends StatelessWidget {
  const RemovedIngredientTag({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          'ingredient removed · pick again',
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ),
    );
  }
}

/// `＋ optional` / `✓ optional`: the switch at the end of an optional row
/// where a week asks about it. The word says what the row is, the mark what
/// the week says: outlined with a plus while left out, the herb ground with a
/// check once in. Not a box, which on this page would read as done.
class OptionalPick extends StatelessWidget {
  const OptionalPick({
    required this.picked,
    required this.onTap,
    required this.name,
    super.key,
  });

  final bool picked;

  /// Null leaves it inert: the week states an amount for the row.
  final VoidCallback? onTap;

  /// The row's ingredient or sub-recipe, for the screen reader.
  final String name;

  @override
  Widget build(BuildContext context) {
    final ink = picked ? AnsiColors.herbDeep : AnsiColors.muted;
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: picked ? AnsiColors.herbSoft : null,
        border: Border.all(
          color: picked ? AnsiColors.herbSoft : AnsiColors.line,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              picked ? FLucideIcons.check : FLucideIcons.plus,
              size: 11,
              color: ink,
            ),
            const SizedBox(width: 4),
            Text('optional', style: ansiMono(size: 10, color: ink)),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      checked: picked,
      label: '$name, optional',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // The target reaches past the pill on every side, so a thumb does
          // not have to find a 20-point word.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
            child: pill,
          ),
        ),
      ),
    );
  }
}

/// `step 2 “…and scatter with coriander.”`: a step that uses the row, in its
/// own words, the ingredient in ink.
class StepQuote extends StatelessWidget {
  const StepQuote(this.use, {super.key});

  final StepUse use;

  @override
  Widget build(BuildContext context) {
    final words = ansiSans(size: 13, color: AnsiColors.muted);
    return Text.rich(
      TextSpan(
        style: words,
        children: [
          TextSpan(
            text: 'step ${use.step} ',
            style: ansiMono(size: 11, color: AnsiColors.herbDeep),
          ),
          TextSpan(text: '“${use.before}'),
          TextSpan(
            text: use.word,
            style: ansiSans(size: 13, weight: FontWeight.w600),
          ),
          TextSpan(text: '${use.after}”'),
        ],
      ),
    );
  }
}

/// One use's amount string ([amountOfLine]).
String amountOfLineItem(LineItem item, {bool scaled = false}) =>
    amountOfLine(item, scaled: scaled);
