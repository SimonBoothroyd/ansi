/// Display copy for sub-recipe components (step 8.6) — pure Dart (no widgets),
/// so every sentence the board's frames specify is unit-testable and said the
/// same way on every surface.
///
/// One rule runs through all of it: **a share of a batch is either stated or
/// refused**. Nothing here ever renders `1×` for a component whose batch math
/// did not resolve — the refusal says which honest refusal it is instead.
library;

import '../../../core/units/measure.dart' show measureWordWithSize;
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
/// there is no number yet. The number counts WORDS rather than units of them —
/// the unit lives on the measure — so the figure prints by the kitchen rule,
/// like every other unitless amount in the app.
String measuredAmountText(double? quantity, String measureLabel) {
  final qty = formatQuantity(quantity);
  return qty.isEmpty ? measureLabel : '$qty $measureLabel';
}

/// How a recipe's own word reads in a list — *"blob · 15 g"* (the editor's
/// MEASURES rows, and the manage state behind a component dock's ＋).
///
/// It is the INGREDIENT side's shape, because it is now the same fact: the
/// word, then what one of it comes to, with nothing between them but the
/// separator this app uses for *and then*. The word is said once — the row has
/// just named it.
String recipeMeasureListText(RecipeMeasure measure) =>
    '${measure.label} · ${recipeMeasureAmountText(measure)}';

/// What one of the word comes to — *"15 g"*, *"1.25 cup"*, *"1 piece"*, said
/// the one way this app says an amount with its unit.
String recipeMeasureAmountText(RecipeMeasure measure) =>
    '${formatAmountIn(measure.amount, measure.unit)} ${measure.unit.label}';

/// A picked chip's own label — *"blob (15 g)"*, the ingredient dock's shape
/// ([measureWordWithSize], which leaves a word that already states its size
/// alone rather than saying it twice).
String recipeMeasureChipText(RecipeMeasure measure) =>
    measureWordWithSize(measure.label, measure.amount, measure.unit);

/// The one sentence a recipe measure IS — *"a blob is 15 g"*. It names the word
/// because its readers are places the word is NOT already on screen beside it:
/// the conversion line over a chip row, a card quoting a line.
String recipeMeasureRateText(RecipeMeasure measure) =>
    'a ${measure.label} is ${recipeMeasureAmountText(measure)}';

/// A Cook demand card's amount line — *"3 blob → 45 g → 0.15 of a batch"*: what
/// the line said, what that comes to, and what that is a share of, in that
/// order, because the reader is holding the parent recipe and looking for the
/// word they wrote in it.
///
/// **The middle step is printed, not elided.** It is the fact the word carries,
/// and the one a cook checks when the share looks wrong — *a blob is what?*
/// Without it the card asserts an arrow between two numbers with no visible
/// relationship, which is exactly the kind of derivation this app makes a point
/// of showing its work for.
///
/// Null when the line says no word of the target's, where the card already
/// states its batches and an arrow from one denomination to itself says
/// nothing.
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

/// What a MEASURES row says while the recipe cannot hold the word — *"nothing
/// to be a share of · MAKES states no mass yield"*.
///
/// The per-row half of [recipeMeasuresOrphanedWarning]: the warning is said
/// once, on the way out of the editor, and this is what the row reads
/// afterwards, for as long as the gap is there. It names the word's own family
/// because that is the thing MAKES has to say again — and it is a fact about
/// the ROW, not a refusal: the word is alive, every line saying it keeps its
/// number, and only the share has gone (ADR-0018 rule 3).
String recipeMeasureOrphanedRowNote(RecipeMeasure measure) =>
    'nothing to be a share of · MAKES states no '
    '${measure.unit.family.name} yield';

/// What the recipe editor says before a Save that takes away the `makes` a live
/// word stands on — *"“blob” (15 g) won’t say anything after this: nothing here
/// makes a batch in grams any more. It stays, and every line saying it goes
/// unresolved until MAKES says a weight again."*
///
/// It is a WARNING, not a refusal (`recipeMeasuresOrphanedBy` decides nothing):
/// what a batch makes is a fact about the recipe and the household may restate
/// it. The sentence's job is that nobody finds out from a broken line
/// afterwards, so it names the words, says they survive, and names the way
/// back.
///
/// Empty for an edit that orphans nothing, so a caller can use it as the
/// condition too.
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
/// [measureLabel] is the LIVE word the line says, which a caller reading the
/// target's measures has and this function does not. Pass it whenever the
/// recipe still holds the word, resolved or not: a word whose `makes` has been
/// edited away still reads *"3 blob · unresolved — …"*, because the word is
/// what the household wrote and only the share has gone. The fallback to the
/// resolved amount's own measure covers the callers that resolve and print in
/// one breath; a line whose word has truly GONE has no label anywhere, and
/// prints its number with the refusal.
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
/// a blob is 15 g"*, or the honest refusal — *"3 blob — no yield set"*, *"3 —
/// its measure is gone"*.
///
/// Null while there is nothing to say — a line with no number yet, or one
/// already counted in batches, where "1 batch = 1 batch" is noise.
///
/// **The word is read off the recipe's LIVE measures, not off the resolution.**
/// A measure resolves through the yield, so a word can now be perfectly alive
/// and still unresolvable — a `makes` restated into another family under it.
/// The line then reads *"3 blob — unresolved — the yield is in volume, this
/// line in mass"*: the household's word, and the gap, both said. Only a word
/// that has actually GONE loses its label, which is the one case where there is
/// no honest label to print.
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
