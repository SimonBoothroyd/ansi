/// Authoring a recipe measure's word and number. Pure Dart.
///
/// Labels are read by [measureLabelAsAuthored]. Refused: a word that names a
/// catalog unit ([unitFromLabel]; ADR-0016), and a unit whose family the
/// recipe's `makes` does not state, since a recipe has no density (ADR-0018).
/// [recipeMeasureUnitChoices] is the same gate as an offer;
/// [recipeMeasuresOrphanedBy] as a pre-Save warning.
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart'
    show measureAlreadyNamed, measureLabelAsAuthored;
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';

/// [measures] with each word said once, from a loaded list that also carries
/// merge-hidden duplicates. The row [keep] names wins its word; otherwise the
/// first of each word wins.
List<RecipeMeasure> offeredRecipeMeasures(
  List<RecipeMeasure> measures, {
  String? keep,
}) {
  final byLabel = <String, RecipeMeasure>{};
  for (final m in measures) {
    if (!byLabel.containsKey(m.label) || m.id == keep) byLabel[m.label] = m;
  }
  final said = <String>{};
  return [
    for (final m in measures)
      if (said.add(m.label)) byLabel[m.label]!,
  ];
}

/// [label], [amount] and [unit] as a [RecipeMeasure], or the refusal a form
/// prints.
///
/// [id] is a fresh uuid for a new word, or the existing row's id when
/// re-stating it; a row is never its own duplicate. [yields] are the recipe's
/// stated denominations and [measures] its live measures. Failures, in the
/// order checked:
///
/// - `recipe_measure/no_yield` — the recipe does not say what a batch makes;
/// - `recipe_measure/no_label` — nothing was typed;
/// - `recipe_measure/unit_word` — the word merely names a catalog unit;
/// - `recipe_measure/word_taken` — this recipe already says it;
/// - `recipe_measure/unit_cannot_measure` — the unit is `batch` or imprecise;
/// - `recipe_measure/amount` — the number is missing, zero, negative or NaN;
/// - `recipe_measure/unit_family` — the recipe states no yield in the unit's
///   family.
Result<RecipeMeasure> authorRecipeMeasure({
  required String id,
  required String recipeId,
  required String label,
  required double? amount,
  required Unit unit,
  required List<YieldDenomination> yields,
  List<RecipeMeasure> measures = const [],
  int sortOrder = 0,
}) {
  final word = measureLabelAsAuthored(label);
  if (yields.isEmpty) {
    return const Err(
      Failure('recipe_measure/no_yield', kRecipeMeasureNoYieldRefusal),
    );
  }
  if (word.isEmpty) {
    return const Err(
      Failure('recipe_measure/no_label', kRecipeMeasureNoLabelRefusal),
    );
  }
  if ((unitFromLabel(word) ?? unitFromWord(word)) != null) {
    return Err(
      Failure('recipe_measure/unit_word', recipeMeasureUnitWordRefusal(word)),
    );
  }
  final taken = measureAlreadyNamed(word, measures);
  if (taken != null && taken.id != id) {
    return Err(
      Failure(
        'recipe_measure/word_taken',
        recipeMeasureWordTakenRefusal(taken),
      ),
    );
  }
  if (!kRecipeMeasureFamilies.contains(unit.family)) {
    return Err(
      Failure(
        'recipe_measure/unit_cannot_measure',
        recipeMeasureUnitCannotMeasureRefusal(word, unit),
      ),
    );
  }
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (amount == null || !amount.isFinite || !(amount > 0)) {
    return Err(
      Failure('recipe_measure/amount', recipeMeasureAmountRefusal(word)),
    );
  }
  final measure = RecipeMeasure(
    id: id,
    recipeId: recipeId,
    label: word,
    amount: amount,
    unit: unit,
    sortOrder: sortOrder,
  );
  // Checked through the same resolution a line uses.
  if (!recipeMeasureResolvesAgainst(measure, yields)) {
    return Err(
      Failure(
        'recipe_measure/unit_family',
        recipeMeasureUnitFamilyRefusal(word, unit, yields),
      ),
    );
  }
  return Ok(measure);
}

/// The units a word may be said in against [yields]: every catalog unit of a
/// family the recipe states, in catalog order. Empty with no yield, or when the
/// only yield's family is not in [kRecipeMeasureFamilies].
List<Unit> recipeMeasureUnitChoices(List<YieldDenomination> yields) {
  final families = {
    for (final y in yields)
      if (kRecipeMeasureFamilies.contains(y.unit.family)) y.unit.family,
  };
  return [
    for (final u in kIngredientUnits)
      if (families.contains(u.family)) u,
  ];
}

/// The unit the authoring form opens on: the first stated yield's own unit,
/// else the head of [recipeMeasureUnitChoices], else null.
Unit? recipeMeasureOpeningUnit(List<YieldDenomination> yields) {
  final choices = recipeMeasureUnitChoices(yields);
  if (choices.isEmpty) return null;
  final stated = yields.first.unit;
  return choices.contains(stated) ? stated : choices.first;
}

/// The [measures] that resolve against [from] (the recipe's current yields) but
/// not against [to] (what a Save would state). Already-orphaned words are not
/// reported. Used to warn before the Save; it never refuses.
List<RecipeMeasure> recipeMeasuresOrphanedBy({
  required List<RecipeMeasure> measures,
  required List<YieldDenomination> from,
  required List<YieldDenomination> to,
}) => [
  for (final m in measures)
    if (recipeMeasureResolvesAgainst(m, from) &&
        !recipeMeasureResolvesAgainst(m, to))
      m,
];

/// Why no measure can be coined yet; also shown on the disabled MEASURES list.
const kRecipeMeasureNoYieldRefusal =
    'A measure is a share of a batch. Say what a batch makes first, under '
    'MAKES.';

/// Why a measure cannot be minted without its name.
const kRecipeMeasureNoLabelRefusal =
    'A measure needs a name — what you call one of these.';

/// Why a unit's name cannot be minted as a measure.
String recipeMeasureUnitWordRefusal(String label) =>
    '“$label” is already a unit. Call the measure something else, like “blob”.';

/// Why a name cannot be minted twice; suggests re-stating the existing row.
String recipeMeasureWordTakenRefusal(RecipeMeasure taken) =>
    '“${taken.label}” is already a measure here, at '
    '${_said(taken.amount, taken.unit)}. Re-state that one instead.';

/// Why a measure cannot be minted without its number.
String recipeMeasureAmountRefusal(String label) =>
    'Say what one “$label” comes to — a number above zero.';

/// Why a measure cannot be said in `batch`, or in an imprecise word.
String recipeMeasureUnitCannotMeasureRefusal(String label, Unit unit) {
  final fact = unit.family == UnitFamily.batch
      ? '“$label” can’t be a share of a batch'
      : '“${unit.label}” is not a size';
  return '$fact. Say what one “$label” comes to as a weight, a volume or a '
      'count.';
}

/// Why a measure in this unit cannot be read against this recipe: no yield is
/// stated in the unit's family (ADR-0008).
String recipeMeasureUnitFamilyRefusal(
  String label,
  Unit unit,
  List<YieldDenomination> yields,
) =>
    'This recipe makes ${yields.map((y) => _said(y.qty, y.unit)).join(' · ')}, '
    'and a recipe has no density to say “$label” in ${unit.label}. Add what a '
    'batch makes in ${unit.label} under MAKES.';

/// `15 g`, `1.25 cup` ([formatAmountIn]).
String _said(double amount, Unit unit) =>
    '${formatAmountIn(amount, unit)} ${unit.label}';
