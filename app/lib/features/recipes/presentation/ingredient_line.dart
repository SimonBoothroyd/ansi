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
    this.included = false,
    this.onToggleOptional,
    super.key,
  });

  final LineUses uses;

  /// Whether this week leaves the row out: amount and name struck and muted.
  final bool struck;

  /// Whether this week has ticked the row's optional line(s) in; the tag then
  /// reads `included`.
  final bool included;

  /// Ticks the row's optional line(s) in or out for this week; the argument is
  /// the new state. Set only where a week owns the page.
  final ValueChanged<bool>? onToggleOptional;

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
        .map(amountOfLineItem)
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
                AnsiTap(
                  onTap: onEditAmount,
                  semanticsLabel: 'Edit the amount',
                  color: AnsiColors.herb,
                  child: const Icon(FLucideIcons.pencil, size: 14),
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
    // A folded multi-use row is tagged if any use is optional, or if this week
    // ticked it in.
    final optional = uses.uses.any((u) => u.optional) || widget.included;
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
          if (optional)
            OptionalTag(
              included: widget.included,
              onToggle: widget.onToggleOptional,
            ),
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
          ...optionalSpans(
            optional: optional,
            included: widget.included,
            onToggle: widget.onToggleOptional,
          ),
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

/// The `optional` tag, in the sub-recipe chip's shape. Public so the page test
/// can find it by type.
///
/// With [onToggle] it is a switch: an empty ring before the word; ticked, it
/// fills herb with a check and reads `included`, at the same size.
class OptionalTag extends StatelessWidget {
  const OptionalTag({this.included = false, this.onToggle, super.key});

  /// Whether the week has ticked this line in.
  final bool included;

  /// Ticks the line in or out; the argument is the new state. Null where the
  /// tag only states a fact.
  final ValueChanged<bool>? onToggle;

  /// The tap target's height where the tag is a switch.
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
                child: OptionalRing(),
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

/// One use's amount string ([amountOfLine]).
String amountOfLineItem(LineItem item) => amountOfLine(item);
