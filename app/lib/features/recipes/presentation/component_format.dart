/// Display copy for sub-recipe components (step 8.6) — pure Dart (no widgets),
/// so every sentence the board's frames specify is unit-testable and said the
/// same way on every surface.
///
/// One rule runs through all of it: **a share of a batch is either stated or
/// refused**. Nothing here ever renders `1×` for a component whose batch math
/// did not resolve — the refusal says which honest refusal it is instead.
library;

import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/format.dart';
import '../domain/component_math.dart';

/// A component line's amount as printed: `"0.25 cup"`, `"1 batch"`, `"3 blob"`,
/// `"8"` for a bare count. The same voice `amountOfLineItem` speaks on the
/// recipe page.
///
/// [measureLabel] is the target recipe's own word, when the line is said in
/// one. It is printed **singular, always**: `20 blob`, never `20 blobs`. The
/// word is the household's and the app does not know its grammar — a rule
/// pluraliser would turn somebody's `sourdough` into `sourdoughs` and their
/// `roux` into `rouxs`, which is a worse sentence than the singular ever is.
String componentAmountText(
  double? quantity,
  Unit? unit, {
  String? measureLabel,
}) {
  if (measureLabel != null) return measuredAmountText(quantity, measureLabel);
  // A line whose word has gone keeps its number and loses its denomination —
  // the board's `3 — its measure is gone`. There is nothing honest to put
  // where the unit was, so nothing goes there.
  if (unit == null) return formatQuantity(quantity);
  final qty = formatQuantityIn(quantity, unit);
  if (unit.family == UnitFamily.count) return qty.isEmpty ? unit.label : qty;
  if (qty.isEmpty) return unit.label;
  return '$qty ${unit.label}';
}

/// An amount said in a recipe's own word: `"3 blob"`, or the bare word when
/// there is no number yet. A measure carries no unit, so the figure prints by
/// the kitchen rule, like every other unitless amount in the app.
String measuredAmountText(double? quantity, String measureLabel) {
  final qty = formatQuantity(quantity);
  return qty.isEmpty ? measureLabel : '$qty $measureLabel';
}

/// How a recipe's own word reads in a list — *"blob · a batch makes 20"* (the
/// editor's MEASURES rows, and the manage state behind a component dock's ＋).
///
/// The word is said once: the row has just named it, and *"blob · a batch
/// makes 20 blob"* is the same word twice in eight words of English.
String recipeMeasureListText(RecipeMeasure measure) =>
    '${measure.label} · a batch makes ${formatAmount(measure.perBatch)}';

/// The one sentence a recipe measure IS — *"a batch makes 20 blob"*. It names
/// the word because its readers are places the word is NOT already on screen
/// beside it: the conversion line over a chip row, a card quoting a line.
String recipeMeasureRateText(RecipeMeasure measure) =>
    'a batch makes ${formatAmount(measure.perBatch)} ${measure.label}';

/// A Cook demand card's amount line — *"3 blob → 0.15 of a batch"*: what the
/// line said, and what it comes to, in that order, because the reader is
/// holding the parent recipe and looking for the word they wrote in it.
///
/// Null when the line says no word of the target's, where the card already
/// states its batches and an arrow from one denomination to itself says
/// nothing.
String? componentDemandLine({
  required double? quantity,
  required String? measureLabel,
  required double batches,
}) {
  if (measureLabel == null || quantity == null) return null;
  return '${measuredAmountText(quantity, measureLabel)} → '
      '${batchShareText(batches)}';
}

/// Why a recipe's word cannot be retired yet — *"Can’t delete “blob” yet · 3
/// lines still say it, in 2 recipes."*
///
/// A pure function of the counts, in the ingredient list's delete voice: name
/// what is in the way, because a number a person can go and change is
/// something they can act on and "failed" is not. [lines] is the referencing
/// line count, [recipes] the distinct recipes those lines sit in.
String recipeMeasureDeleteRefusalText({
  required String label,
  required int lines,
  required int recipes,
}) =>
    'Can’t delete “$label” yet · $lines ${plural(lines, 'line')} still '
    '${plural(lines, 'says', plural: 'say')} it, in $recipes '
    '${plural(recipes, 'recipe')}.';

/// How many whole runs of the target a resolved amount asks for: `"1 batch"`,
/// `"2 batches"`, `"0.25 of a batch"` — the board's *"¼ of a batch"*.
String batchShareText(double batches) {
  if (batches == batches.roundToDouble()) {
    final n = formatQuantity(batches);
    return '$n ${plural(batches.round(), 'batch', plural: 'batches')}';
  }
  return '${formatQuantity(batches)} of a batch';
}

/// One stated denomination as the hero pill and the picker hint read it:
/// *"makes 1 cup"*.
String yieldText(YieldDenomination denomination) =>
    'makes ${formatQuantityIn(denomination.qty, denomination.unit)} '
    '${denomination.unit.label}';

/// The hero meta row's yield pills (design board frame b): *"makes 250 g"* and
/// a continuation pill *"· 16 tbsp"* for the optional second denomination, so
/// the row reads as the one sentence "makes 250 g · 16 tbsp". Empty for a
/// recipe that does not say what it makes.
List<String> yieldPillLabels(List<YieldDenomination> yields) => [
  for (final (i, y) in yields.indexed)
    if (i == 0)
      yieldText(y)
    else
      '· ${formatQuantityIn(y.qty, y.unit)} ${y.unit.label}',
];

/// Why a component amount could not be turned into a share of a batch, in one
/// short clause — the "Used in" row's and the picker's honest fallback.
///
/// Every branch names something the reader can act on; none of them is a
/// failure message.
String unresolvedComponentText(UnresolvedComponentAmount reason) =>
    switch (reason) {
      ComponentAmountMissing() => 'no amount set',
      ComponentYieldMissing() => 'no yield set',
      ComponentMeasureMissing() => 'its measure is gone',
      ComponentFamilyMismatch(:final lineFamily, :final yieldFamilies) =>
        'unresolved — the yield is in '
            '${yieldFamilies.map((f) => f.name).toSet().join(' / ')}, '
            'this line in ${lineFamily.name}',
      ComponentCycle() => 'unresolved — this recipe is used inside itself',
    };

/// A component amount as one line: the share of a batch when it resolves, the
/// reason when it does not.
String componentAmountSummary(ComponentAmount amount) => switch (amount) {
  ResolvedComponentAmount(:final batches) => batchShareText(batches),
  UnresolvedComponentAmount() => unresolvedComponentText(amount),
};

/// A "Used in" row's subtitle: the printed amount, then its share of a batch —
/// *"0.25 cup · 0.25 of a batch"*, *"3 blob · 0.15 of a batch"*. A line already
/// denominated in batches says it once ("1 batch"), because the printed amount
/// IS the share.
///
/// [measureLabel] comes from the resolved amount where there is one, so a row
/// whose word has gone prints its number and the refusal rather than the
/// count-family unit stored under the word.
String usedInAmountLine({
  required double? quantity,
  required Unit? unit,
  required ComponentAmount amount,
  String? measureLabel,
}) {
  final said =
      measureLabel ??
      switch (amount) {
        ResolvedComponentAmount(:final viaMeasure) => viaMeasure?.label,
        UnresolvedComponentAmount() => null,
      };
  final printed = componentAmountText(quantity, unit, measureLabel: said);
  if (said == null && unit?.family == UnitFamily.batch) return printed;
  final summary = componentAmountSummary(amount);
  return printed.isEmpty ? summary : '$printed · $summary';
}

/// The quantity sheet's live conversion line (design board frame d):
/// *"0.25 cup = 0.25 of a batch · makes 1 cup"*, *"3 blob = 0.15 of a batch ·
/// a batch makes 20 blob"*, or the honest refusal — *"3 — its measure is
/// gone"*.
///
/// Null while there is nothing to say — a line with no number yet, or one
/// already counted in batches, where "1 batch = 1 batch" is noise. A line said
/// in one of the target's [measures] always has something to say, because the
/// share is the whole point of the word.
String? componentConversionLine({
  required double? quantity,
  required Unit? unit,
  required List<YieldDenomination> yields,
  String? recipeMeasureId,
  List<RecipeMeasure> measures = const [],
}) {
  if (quantity == null) return null;
  if (recipeMeasureId == null && unit?.family == UnitFamily.batch) return null;
  final amount = resolveComponentAmount(
    quantity: quantity,
    unit: unit,
    yields: yields,
    recipeMeasureId: recipeMeasureId,
    measures: measures,
  );
  final said = switch (amount) {
    ResolvedComponentAmount(:final viaMeasure) => viaMeasure,
    UnresolvedComponentAmount() => null,
  };
  final printed = componentAmountText(
    quantity,
    unit,
    measureLabel: said?.label,
  );
  return switch (amount) {
    ResolvedComponentAmount(:final batches) when said != null =>
      '$printed = ${batchShareText(batches)} · ${recipeMeasureRateText(said)}',
    ResolvedComponentAmount(:final batches, :final against) =>
      against == null
          ? '$printed = ${batchShareText(batches)}'
          : '$printed = ${batchShareText(batches)} · ${yieldText(against)}',
    UnresolvedComponentAmount() =>
      '$printed — ${unresolvedComponentText(amount)}',
  };
}

/// The "Used in · N" tab label (design board frame b — the count rides in the
/// label, and the tab only exists while it is non-zero).
String usedInTabLabel(int count) => 'Used in · $count';

/// D5's delete refusal, in the 8.5 ingredient-delete voice: name the count,
/// because *"used in 2 recipes"* is something a person can act on and
/// *"failed"* is not. [recipes] is the distinct recipe count, [lines] the
/// referencing line count.
String deleteRefusalText({required int recipes, required int lines}) =>
    'Used in $recipes ${plural(recipes, 'recipe')} '
    '($lines ${plural(lines, 'line')}). Change those lines first.';
