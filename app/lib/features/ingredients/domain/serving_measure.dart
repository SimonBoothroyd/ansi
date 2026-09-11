/// The serving a label prints, kept as ONE named measure on the row — PURE
/// DART (invariant 2).
///
/// A pack's "1 cup (237 mL) · 110 kcal" carries two facts: the macros, and the
/// serving they are printed per. The macros are stored per 100 of the row's
/// basis like every row's; the serving is stored as an `ingredient_measure`
/// labelled `serving · 1 cup`, whose amount is that serving in the basis unit.
/// That pairing is what lets the reading posture print the label's own figures
/// back — per-100 × the serving amount reverses the entry arithmetic exactly,
/// unrounded — instead of asking a person to check a jar against a per-100
/// figure the jar never printed.
///
/// **One serving per row.** The label is written under a reserved prefix, so a
/// later save replaces the serving rather than stacking a second one beside it.
/// Nothing here is a density: a volume serving on a per-100 ml row converts
/// through the catalog alone (ADR-0008 §2 keeps volume⇄mass to the one stored
/// `density_g_per_ml`, entered in the density section).
library;

import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';

/// What every serving measure's label opens with. Reserved: the measures
/// editor's own adds never produce it, so the prefix identifies the row's one
/// serving without a second column.
const kServingMeasurePrefix = 'serving · ';

/// `serving · 2 tbsp` — the label one serving of [amount] [unit] is stored
/// under.
String servingMeasureLabel(double amount, Unit unit) =>
    '$kServingMeasurePrefix${formatServingPhrase(amount, unit)}';

/// `2 tbsp` — the serving as the pack says it, with the app's one number rule.
String formatServingPhrase(double amount, Unit unit) =>
    '${formatAmount(amount)} ${unit.label}';

/// The serving [measures] holds, or null when the row states none.
Measure? servingMeasureOf(Iterable<Measure> measures) {
  for (final m in measures) {
    if (m.label.startsWith(kServingMeasurePrefix)) return m;
  }
  return null;
}

/// The amount and unit a serving measure's label states, or null when the
/// label carries no phrase this file wrote.
///
/// The round trip through text is deliberate: the serving is a measure like
/// any other, so a household can rename or bin it in the measures editor, and
/// a label that no longer parses simply stops being read as a serving rather
/// than becoming a second source of truth.
({double amount, Unit unit})? servingFromMeasureLabel(String label) {
  if (!label.startsWith(kServingMeasurePrefix)) return null;
  return parseServingPhrase(label.substring(kServingMeasurePrefix.length));
}

/// `2 tbsp`, `0.25 cup`, `1/4 cup`, `1 Cup` → an amount and a catalog unit, or
/// null when the words are not a kitchen measure this app knows.
({double amount, Unit unit})? parseServingPhrase(String phrase) {
  final m = RegExp(
    r'^\s*([0-9]+(?:[.,][0-9]+)?)\s*(?:/\s*([0-9]+(?:[.,][0-9]+)?)\s*)?'
    r'([a-zA-Z][a-zA-Z ]*?)\s*$',
  ).firstMatch(phrase);
  if (m == null) return null;
  final numerator = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  final denominator = m.group(2) == null
      ? 1.0
      : double.tryParse(m.group(2)!.replaceAll(',', '.'));
  if (numerator == null || denominator == null || !(denominator > 0)) {
    return null;
  }
  final amount = numerator / denominator;
  if (!(amount > 0) || !amount.isFinite) return null;
  final unit = unitFromWord(
    m.group(3)!,
    families: const {UnitFamily.mass, UnitFamily.volume},
  );
  if (unit == null) return null;
  return (amount: amount, unit: unit);
}
