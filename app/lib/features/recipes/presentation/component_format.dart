/// Display copy for sub-recipe components (step 8.6) — pure Dart (no widgets),
/// so every sentence the board's frames specify is unit-testable and said the
/// same way on every surface.
///
/// One rule runs through all of it: **a share of a batch is either stated or
/// refused**. Nothing here ever renders `1×` for a component whose batch math
/// did not resolve — the refusal says which honest refusal it is instead
/// (exec plan 0021, D2/D3).
library;

import '../../../core/units/units.dart';
import '../domain/component_math.dart';
import 'format.dart';

/// A component line's amount as printed: `"0.25 cup"`, `"1 batch"`, `"8"` for
/// a bare count. The same voice `amountOfLineItem` speaks on the recipe page.
String componentAmountText(double? quantity, Unit unit) {
  final qty = formatQuantity(quantity);
  if (unit.family == UnitFamily.count) return qty.isEmpty ? unit.label : qty;
  if (qty.isEmpty) return unit.label;
  return '$qty ${unit.label}';
}

/// How many whole runs of the target a resolved amount asks for: `"1 batch"`,
/// `"2 batches"`, `"0.25 of a batch"` — the board's *"¼ of a batch"*.
String batchShareText(double batches) {
  if (batches == batches.roundToDouble()) {
    final n = formatQuantity(batches);
    return '$n ${batches == 1 ? 'batch' : 'batches'}';
  }
  return '${formatQuantity(batches)} of a batch';
}

/// One stated denomination as the hero pill and the picker hint read it:
/// *"makes 1 cup"*.
String yieldText(YieldDenomination denomination) =>
    'makes ${formatQuantity(denomination.qty)} ${denomination.unit.label}';

/// The hero meta row's yield pills (design board frame b): *"makes 250 g"* and
/// a continuation pill *"· 16 tbsp"* for the optional second denomination, so
/// the row reads as the one sentence "makes 250 g · 16 tbsp". Empty for a
/// recipe that does not say what it makes.
List<String> yieldPillLabels(List<YieldDenomination> yields) => [
  for (final (i, y) in yields.indexed)
    if (i == 0) yieldText(y) else '· ${formatQuantity(y.qty)} ${y.unit.label}',
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
/// *"0.25 cup · 0.25 of a batch"*. A line already denominated in batches says
/// it once ("1 batch"), because the printed amount IS the share.
String usedInAmountLine({
  required double? quantity,
  required Unit unit,
  required ComponentAmount amount,
}) {
  final printed = componentAmountText(quantity, unit);
  if (unit.family == UnitFamily.batch) return printed;
  final summary = componentAmountSummary(amount);
  return printed.isEmpty ? summary : '$printed · $summary';
}

/// The quantity sheet's live conversion line (design board frame d):
/// *"0.25 cup = 0.25 of a batch · makes 1 cup"*, or the honest refusal.
///
/// Null while there is nothing to say — a line with no number yet, or one
/// already counted in batches, where "1 batch = 1 batch" is noise.
String? componentConversionLine({
  required double? quantity,
  required Unit unit,
  required List<YieldDenomination> yields,
}) {
  if (quantity == null) return null;
  if (unit.family == UnitFamily.batch) return null;
  final amount = resolveComponentAmount(
    quantity: quantity,
    unit: unit,
    yields: yields,
  );
  final printed = componentAmountText(quantity, unit);
  return switch (amount) {
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
    'Used in $recipes ${recipes == 1 ? 'recipe' : 'recipes'} '
    '($lines ${lines == 1 ? 'line' : 'lines'}). Change those lines first.';
