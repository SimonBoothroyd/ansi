/// The serving a label prints, kept as one named measure on the row. Pure Dart.
///
/// The macros are stored per 100 of the row's basis; the serving is an
/// `ingredient_measure` labelled `serving · 1 cup`, whose amount is that
/// serving in the basis unit. Per-100 × the serving amount gives the label's
/// own figures back, unrounded.
///
/// One serving per row: the label uses a reserved prefix, so a later save
/// replaces it. It is never a density (ADR-0008 §2).
library;

import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';

/// What every serving measure's label opens with. Reserved: the measures editor
/// never produces it, so the prefix identifies the row's one serving.
const kServingMeasurePrefix = 'serving · ';

/// `serving · 2 tbsp` — the label one serving of [amount] [unit] is stored
/// under.
String servingMeasureLabel(double amount, Unit unit) =>
    '$kServingMeasurePrefix${formatServingPhrase(amount, unit)}';

/// `2 tbsp` — the serving as the pack says it, with the app's one number rule.
String formatServingPhrase(double amount, Unit unit) =>
    '${formatAmountIn(amount, unit)} ${unit.label}';

/// Whether [measure] is the row's serving rather than one of its measures.
/// Every list of measures leaves it out, the unit picker included: a serving is
/// what a panel is printed per, not a size anyone cooks in. A line already
/// stored on one still draws its chip, by the rule that admits any stored
/// choice.
bool isServingMeasure(Measure measure) =>
    measure.label.startsWith(kServingMeasurePrefix);

/// What a chip for [measure] says: `serving (237 ml)` for the row's serving, as
/// `piece (110 g)` reads, and its own label otherwise. Only a line already
/// stored on the serving draws this chip.
String measureChipLabel(Measure measure) => isServingMeasure(measure)
    ? 'serving (${formatNumber(measure.amount)} '
          '${measure.basis.baseUnit.label})'
    : measure.label;

/// The serving [measures] holds, or null when the row states none.
Measure? servingMeasureOf(Iterable<Measure> measures) {
  for (final m in measures) {
    if (isServingMeasure(m)) return m;
  }
  return null;
}

/// The amount and unit a serving measure's label states, or null when the label
/// does not parse. A household can rename the serving in the measures editor;
/// it then stops being read as a serving.
({double amount, Unit unit})? servingFromMeasureLabel(String label) {
  if (!label.startsWith(kServingMeasurePrefix)) return null;
  return parseServingPhrase(label.substring(kServingMeasurePrefix.length));
}

/// Both readings a pack's serving line states: the `2 tbsp` it says and the `(7
/// g)` it converts that to. Each half is null when its words are not a measure
/// this app knows ("1 serving"). Nothing is converted: both figures are the
/// pack's.
({({double amount, Unit unit})? said, ({double amount, Unit unit})? bracketed})
readPrintedServing(String? servingSize) {
  if (servingSize == null) return (said: null, bracketed: null);
  final open = servingSize.indexOf('(');
  final close = open == -1 ? -1 : servingSize.indexOf(')', open + 1);
  return (
    said: parseServingPhrase(
      open == -1 ? servingSize : servingSize.substring(0, open),
    ),
    bracketed: close == -1
        ? null
        : parseServingPhrase(servingSize.substring(open + 1, close)),
  );
}

/// `2 tbsp`, `¼ cup`, `1/4 cup`, `1 1/2 fl oz`, `1 Cup` → an amount and a
/// catalog unit, or null. The numeric head is read by [parseAmount], so
/// whatever [formatAmount] wrote reads back.
({double amount, Unit unit})? parseServingPhrase(String phrase) {
  final m = RegExp(
    r'^\s*([0-9\u00bc-\u00be\u2150-\u215e]'
    r'[0-9 .,/\u00bc-\u00be\u2150-\u215e]*?)\s*'
    r'([a-zA-Z][a-zA-Z ]*?)\s*$',
  ).firstMatch(phrase);
  if (m == null) return null;
  final amount = parseAmount(m.group(1)!);
  if (amount == null || !(amount > 0) || !amount.isFinite) return null;
  final unit = unitFromWord(
    m.group(2)!,
    families: const {UnitFamily.mass, UnitFamily.volume},
  );
  if (unit == null) return null;
  return (amount: amount, unit: unit);
}
