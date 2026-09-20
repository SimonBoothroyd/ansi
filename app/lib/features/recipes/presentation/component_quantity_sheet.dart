/// The quantity + unit-chip sheet for a **component** line (step 8.6 / D2,
/// design board frame d) — the 7.7 sheet's anatomy with batch math on the
/// chips.
///
/// Same dock, the same [UnitChipRow], the same live conversion line, the same
/// Optional row. What differs is the OFFER, and each difference is a
/// consequence of a component being a recipe rather than an ingredient
/// ([componentUnitChoices]):
///
/// - **the target recipe's own words lead it** — `3 blob` of a sauce, a word
///   the household coined on that recipe and nowhere else (ADR-0018). A word
///   is an amount in a unit, so it resolves through the recipe's own `makes`
///   exactly as `¼ cup` does, and the whole-batch word leads even that
///   ([wholeMeasureOfRecipe]);
/// - then `batch`, then **the yields' families**, kitchen-trimmed. `batch` is
///   always sayable, and a family opens only because the recipe states a yield
///   in it. There is no density for a recipe, so a family nobody stated is not
///   offered; the fix is the yield's optional second denomination, not a guess;
/// - the conversion line reads in batches ("0.25 cup = 0.25 of a batch ·
///   makes 1 cup"), and a recipe with no yield gets the *not-an-error* state:
///   the `batch` chip alone, the honest note, and one tap to go set the yield.
///   The link, the page and scaling all work meanwhile — only derived numbers
///   wait. No words either, because a word is an amount and an amount says
///   nothing about a batch until the batch has one too.
///
/// The 7.7 **stored-selection rule carries over** to both kinds: an imported
/// line's printed unit, and a word whose `makes` has been edited out from under
/// it, are admissible chips even when this sheet would not otherwise offer
/// them — marked as outside the filter and rendered with the honest unresolved
/// line, never silently rewritten.
///
/// **A line whose word has GONE selects nothing.** There is no honest
/// denomination to preselect: the word was the only place its amount lived, and
/// a chip lit here would claim the line says something it does not. So the row
/// opens with the offer and no selection, the number is kept, and the pointer
/// is kept with it until somebody picks a chip — which is the repair, the other
/// one being to put the word back under the target recipe's MEASURES.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/format.dart';
import '../../ingredients/presentation/unit_chips.dart';
import '../domain/component_math.dart' show YieldDenomination;
import '../domain/component_units.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'recipe_chip.dart';

/// What the component sheet resolved to: the amount, the denomination it counts
/// — **exactly one** of a catalog `unit` and one of the target's own words
/// (`recipeMeasureId`) — and whether the line is optional.
///
/// It is the nullability `LineItem.unit` carries, for the same reason: a line's
/// amount is said in a catalog unit **or** in one of the target recipe's words,
/// never both and never neither (migration 0048). The one case where both are
/// null is a line whose word has gone and whose reader picked nothing, where
/// the caller writes neither and the line keeps the pointer it already had.
typedef ComponentQuantity = ({
  double? quantity,
  Unit? unit,
  String? recipeMeasureId,
  bool optional,
});

/// Opens the component quantity sheet for [target]; resolves to the chosen
/// amount, or null if dismissed.
///
/// [onSetYield] is the deep link the no-yield state offers ("Set the yield").
/// Null where there is nowhere to send the user (a host with no router).
///
/// [initialMeasureId] is `LineItem.recipeMeasureId` — the pointer the line
/// actually carries. Pass it whenever the line has one: the word itself is
/// looked up on [target], because that is where it lives.
Future<ComponentQuantity?> showComponentQuantitySheet(
  BuildContext context, {
  required SubRecipeTarget target,
  double? initialQuantity,
  Unit? initialUnit,
  String? initialMeasureId,
  bool initialOptional = false,
  VoidCallback? onSetYield,
}) {
  return showAnsiSheet<ComponentQuantity>(
    context: context,
    builder: (sheetContext) => ComponentQuantityEditor(
      target: target,
      initialQuantity: initialQuantity,
      initialUnit: initialUnit,
      initialMeasureId: initialMeasureId,
      initialOptional: initialOptional,
      onSetYield: onSetYield == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onSetYield();
            },
      onDone: (result) => Navigator.of(sheetContext).pop(result),
    ),
  );
}

class ComponentQuantityEditor extends HookWidget {
  const ComponentQuantityEditor({
    required this.target,
    required this.onDone,
    this.initialQuantity,
    this.initialUnit,
    this.initialMeasureId,
    this.initialOptional = false,
    this.onSetYield,
    super.key,
  });

  final SubRecipeTarget target;
  final double? initialQuantity;

  /// The line's stored unit — always an admissible chip (the 7.7 rule).
  final Unit? initialUnit;

  /// The line's `recipe_measure_id`, when it says one of the target's own
  /// words. The word itself is read off [target] — never joined onto the line,
  /// which is what makes a re-stated `blob` follow through everywhere at once.
  final String? initialMeasureId;

  /// Whether the line already says it may be left out.
  final bool initialOptional;

  final ValueChanged<ComponentQuantity> onDone;
  final VoidCallback? onSetYield;

  @override
  Widget build(BuildContext context) {
    final yields = target.yields;
    final measures = target.measures;
    // The chip the sheet opens on. Null is the one line with nothing honest to
    // preselect — a word that has gone — and it is the reason [UnitChipRow]'s
    // selection is nullable at all.
    final stored = _openingChoice();
    final choice = useState<UnitChoice?>(stored);
    final quantity = useState<double?>(initialQuantity);
    final optional = useState<bool>(initialOptional);

    final picked = choice.value;
    final word = picked is RecipeMeasureOption ? picked.measure : null;
    final unit = switch (picked) {
      UnitOption(:final unit) => unit,
      RecipeMeasureOption() || null => null,
      MeasureOption(:final measure) => notAWordForARecipe(measure),
    };
    // The pointer the line will carry: the word that is picked, or — while
    // nothing has been picked at all — the one it arrived with, which is the
    // gone-word case. Picking any chip replaces it, and picking a unit clears
    // it: a line is denominated once (the repository refuses the other two
    // shapes outright).
    final measureId = word?.id ?? (picked == null ? initialMeasureId : null);

    // The offer, with the opening choice always admitted: a word whose `makes`
    // has been edited into another family is not in the honest filter, and must
    // still read as itself, marked, with the refusal under it.
    final offer = componentUnitChoices(target, measures, current: stored);

    final note = componentConversionLine(
      quantity: quantity.value,
      unit: unit,
      yields: yields,
      recipeMeasureId: measureId,
      // The LIVE words, never the resolution's: a word can be perfectly alive
      // and still unresolvable (a `makes` restated into another family under
      // it), and that line must read "3 blob — unresolved — …" rather than a
      // bare "3 — unresolved".
      measures: measures,
    );

    return AnsiSheetShell(
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: RecipeChip(title: target.title, size: 16),
        ),
        const SizedBox(height: 4),
        Text(
          yields.isEmpty
              ? 'no yield set · your recipe'
              : '${yields.map(yieldText).join(' · ')} · your recipe',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 16),
        Text('QUANTITY', style: ansiLabel()),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 132,
              child: FTextField(
                autofocus: true,
                hint: 'qty',
                // A TEXT keyboard, not the decimal pad: iOS's numeric pads
                // carry no `/`, so `1/2` could not be typed on one — and a
                // fraction is how a recipe says this number.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    // A number counting WORDS prints by the kitchen rule, like
                    // every other unitless amount: the unit lives on the
                    // measure, not on the line.
                    text: unit == null
                        ? formatQuantity(quantity.value)
                        : formatQuantityIn(quantity.value, unit),
                  ),
                  onChange: (v) => quantity.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // The picked word says what one of it comes to, exactly as a
                // picked ingredient measure does: the chip row carries the bare
                // word, the sentence beside the number carries its size.
                // Nothing at all for a gone word — the number is all this line
                // honestly says.
                word != null
                    ? recipeMeasureChipText(word)
                    : (unit?.label ?? ''),
                style: ansiMono(size: 15, color: AnsiColors.herbDeep),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          note ??
              (yields.isEmpty ? 'no yield set — amounts in batches only' : ''),
          textAlign: TextAlign.center,
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 8),
        UnitChipRow(
          offer: offer,
          selected: picked,
          // No `+` chip yet: the door behind it is the TARGET recipe's measures
          // list, which is its own control and is not built here.
          onSelect: (c) => choice.value = c,
        ),
        if (measureId != null && word == null) ...[
          const SizedBox(height: 8),
          Text(
            kGoneWordKeepsItsNumber,
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        // The no-yield state is not an error state: the link, the page and
        // scaling all work: only the derived numbers wait, one tap away.
        if (yields.isEmpty && onSetYield != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSetYield,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AnsiColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Set the yield',
                textAlign: TextAlign.center,
                style: ansiMono(size: 12),
              ),
            ),
          ),
        ],
        // The Optional row is the ingredient sheet's, word for word: a
        // sub-recipe may be left out of a total exactly as a garnish may.
        const SizedBox(height: 14),
        FSwitch(
          label: Text('Optional', style: ansiSans(size: 15)),
          value: optional.value,
          onChange: (on) => optional.value = on,
        ),
        const SizedBox(height: 4),
        Text(
          'left out of macros and the shop list, and named where it left',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 14),
        FButton(
          onPress: () => onDone((
            quantity: quantity.value,
            unit: unit,
            recipeMeasureId: measureId,
            optional: optional.value,
          )),
          child: const Text('Done'),
        ),
      ],
    );
  }

  /// Which chip the sheet opens on.
  ///
  /// A line being EDITED opens on its own stored denomination — its word where
  /// the target still holds it, else its unit — and a line whose word has gone
  /// opens on nothing at all. A FRESH amount opens on the first thing the offer
  /// leads with while that is one of the recipe's own words
  /// ([firstComponentChoice]: the whole-batch word, else the first word the
  /// recipe can still hold), and otherwise on the yield's own unit, which is
  /// the line a page prints — `¼ cup` of a `makes 1 cup` aioli — and the
  /// denomination this sheet has always opened wordless recipes on.
  UnitChoice? _openingChoice() {
    if (initialMeasureId case final id?) {
      final word = recipeMeasureById(id, target.measures);
      return word == null ? null : RecipeMeasureOption(word);
    }
    if (initialUnit case final unit?) return UnitOption(unit);
    final first = firstComponentChoice(target, target.measures);
    return first is RecipeMeasureOption
        ? first
        : UnitOption(_defaultUnit(target.yields));
  }

  /// What the sheet says about a line whose word has been retired on the target
  /// recipe, or has not synced here yet — one sentence, in the app's refusal
  /// voice: name the fact, and name both ways out.
  static const kGoneWordKeepsItsNumber =
      'The word this line was written in is gone from that recipe, so there is '
      'nothing counting it. The number is kept — put the word back under that '
      'recipe’s MEASURES, or say this line in one of the chips below.';

  /// What a fresh component line counts before anyone picks a chip, on a recipe
  /// that coins no word: the yield's own unit when it states one, and `batch`
  /// otherwise — the one denomination that never needs a yield.
  static Unit _defaultUnit(List<YieldDenomination> yields) =>
      yields.isEmpty ? batches : yields.first.unit;
}
