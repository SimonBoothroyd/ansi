/// Display copy for sub-recipe components. Pure Dart, so it is unit-testable. A
/// share of a batch is either stated or refused with its reason; nothing here
/// renders `1×` for an unresolved component.
library;

import '../../../core/units/measure.dart' show measureWordWithSize;
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/format.dart';
import '../domain/component_math.dart';

/// A component line's amount as printed: `"0.25 cup"`, `"1 batch"`, `"3 blob"`,
/// `"8"` for a bare count.
///
/// [measureLabel] is the target recipe's own word, always printed singular (`20
/// blob`): the app does not know the word's grammar.
String componentAmountText(
  double? quantity,
  Unit? unit, {
  String? measureLabel,
}) {
  if (measureLabel != null) return measuredAmountText(quantity, measureLabel);
  // A line whose word has gone keeps its number and prints no denomination.
  if (unit == null) return formatQuantity(quantity);
  final qty = formatQuantityIn(quantity, unit);
  if (unit.family == UnitFamily.count) return qty.isEmpty ? unit.label : qty;
  if (qty.isEmpty) return unit.label;
  return '$qty ${unit.label}';
}

/// An amount in a recipe's own word: `"3 blob"`, or the bare word without a
/// number. The number counts words, so it prints as a unitless amount.
String measuredAmountText(double? quantity, String measureLabel) {
  final qty = formatQuantity(quantity);
  return qty.isEmpty ? measureLabel : '$qty $measureLabel';
}

/// A recipe measure as a list row: "blob · 15 g".
String recipeMeasureListText(RecipeMeasure measure) =>
    '${measure.label} · ${recipeMeasureAmountText(measure)}';

/// What one of the word comes to: "15 g", "1.25 cup", "1 piece".
String recipeMeasureAmountText(RecipeMeasure measure) =>
    '${formatAmountIn(measure.amount, measure.unit)} ${measure.unit.label}';

/// A picked chip's label: "blob (15 g)" ([measureWordWithSize]).
String recipeMeasureChipText(RecipeMeasure measure) =>
    measureWordWithSize(measure.label, measure.amount, measure.unit);

/// "a blob is 15 g" — for places where the word is not already on screen.
String recipeMeasureRateText(RecipeMeasure measure) =>
    'a ${measure.label} is ${recipeMeasureAmountText(measure)}';

/// A Cook demand card's amount line: "3 blob → 45 g → 0.15 of a batch". The
/// middle step is printed so the share can be checked. Null when the line is
/// not said in one of the target's words.
String? componentDemandLine({
  required double? quantity,
  required RecipeMeasure? measure,
  required double batches,
}) {
  if (measure == null || quantity == null) return null;
  final total = measure.totalFor(quantity);
  return [
    measuredAmountText(quantity, measure.label),
    if (total != null)
      '${formatAmountIn(total.amount, total.unit)} ${total.unit.label}',
    batchShareText(batches),
  ].join(' → ');
}

/// "Can’t delete “blob” yet · 3 lines still say it, in 2 recipes." [lines] is
/// the referencing line count, [recipes] the distinct recipes they sit in,
/// [weeks] the weeks whose own amount says it (named when they are all that is
/// left).
String recipeMeasureDeleteRefusalText({
  required String label,
  required int lines,
  required int recipes,
  int weeks = 0,
}) {
  if (lines == 0) {
    return 'Can’t delete “$label” yet · $weeks ${plural(weeks, 'week')} '
        '${plural(weeks, 'says', plural: 'say')} it in '
        '${plural(weeks, 'its', plural: 'their')} own amount.';
  }
  final said =
      'Can’t delete “$label” yet · $lines ${plural(lines, 'line')} still '
      '${plural(lines, 'says', plural: 'say')} it, in $recipes '
      '${plural(recipes, 'recipe')}.';
  return weeks == 0
      ? said
      : '$said $weeks ${plural(weeks, 'week')} '
            '${plural(weeks, 'says', plural: 'say')} it too.';
}

/// What a MEASURES row says while MAKES no longer supports the word: "nothing
/// to be a share of · MAKES states no weight yield". The word stays alive and
/// lines keep their number (ADR-0018 rule 3).
String recipeMeasureOrphanedRowNote(RecipeMeasure measure) =>
    'nothing to be a share of · MAKES states no '
    '${measure.unit.family.said} yield';

/// The recipe editor's warning before a Save that removes the `makes` a live
/// word depends on. It names the words, says they survive, and says how to
/// restore them. A warning, not a refusal. Empty when the edit orphans nothing.
String recipeMeasuresOrphanedWarning(List<RecipeMeasure> orphaned) {
  if (orphaned.isEmpty) return '';
  final n = orphaned.length;
  final words = orphaned
      .map((m) => '“${m.label}” (${recipeMeasureAmountText(m)})')
      .join(', ');
  return '$words ${plural(n, 'has', plural: 'have')} nothing left to be a '
      'share of after this. Nothing is deleted — but every line saying '
      '${plural(n, 'it', plural: 'them')} goes unresolved until MAKES says '
      'what a batch comes to in the same kind of unit again.';
}

/// `"1 batch"`, `"2 batches"`, `"0.25 of a batch"`.
String batchShareText(double batches) {
  if (batches == batches.roundToDouble()) {
    final n = formatQuantity(batches);
    return '$n ${plural(batches.round(), 'batch', plural: 'batches')}';
  }
  return '${formatQuantity(batches)} of a batch';
}

/// One stated denomination: "makes 1 cup".
String yieldText(YieldDenomination denomination) =>
    'makes ${formatQuantityIn(denomination.qty, denomination.unit)} '
    '${denomination.unit.label}';

/// The hero row's yield pills: "makes 250 g", then "· 16 tbsp" for a second
/// denomination. Empty when the recipe states no yield.
List<String> yieldPillLabels(List<YieldDenomination> yields) => [
  for (final (i, y) in yields.indexed)
    if (i == 0)
      yieldText(y)
    else
      '· ${formatQuantityIn(y.qty, y.unit)} ${y.unit.label}',
];

/// Why a component amount has no batch share, in one short clause the reader
/// can act on.
String unresolvedComponentText(UnresolvedComponentAmount reason) =>
    switch (reason) {
      ComponentAmountMissing() => 'no amount set',
      ComponentYieldMissing() => 'no yield set',
      ComponentMeasureMissing() => 'its measure is gone',
      ComponentFamilyMismatch(:final lineFamily, :final yieldFamilies) =>
        'unresolved — the yield is in '
            '${yieldFamilies.map((f) => f.said).toSet().join(' / ')}, '
            'this line in ${lineFamily.said}',
      ComponentCycle() => 'unresolved — this recipe is used inside itself',
    };

/// A component amount as one line: the share of a batch, or the reason there is
/// none.
String componentAmountSummary(ComponentAmount amount) => switch (amount) {
  ResolvedComponentAmount(:final batches) => batchShareText(batches),
  UnresolvedComponentAmount() => unresolvedComponentText(amount),
};

/// A "Used in" row's subtitle: the printed amount, then its share of a batch —
/// "0.25 cup · 0.25 of a batch". A line in batches says it once.
///
/// [measureLabel] is the live word the line says; pass it whenever the recipe
/// still holds the word, resolved or not. It falls back to the resolved
/// amount's own measure; a line whose word has gone prints its number with the
/// refusal.
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

/// The quantity sheet's live conversion line: "0.25 cup = 0.25 of a batch ·
/// makes 1 cup", "3 blob = 0.15 of a batch · a blob is 15 g", or the refusal
/// ("3 blob — no yield set", "3 — its measure is gone"). Null with no number
/// yet, or for a line already in batches.
///
/// The word is read off the recipe's live measures, not the resolution: a live
/// word can be unresolvable after a `makes` edit and still prints with its gap.
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
  final said = recipeMeasureId == null
      ? null
      : recipeMeasureById(recipeMeasureId, measures);
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

/// The "Used in · N" tab label. The tab exists only while N is non-zero.
String usedInTabLabel(int count) => 'Used in · $count';

/// The recipe delete refusal, naming the counts. [recipes] is the distinct
/// recipe count, [lines] the referencing line count.
String deleteRefusalText({required int recipes, required int lines}) =>
    'Used in $recipes ${plural(recipes, 'recipe')} '
    '($lines ${plural(lines, 'line')}). Change those lines first.';
