/// What the ingredient page says about a row while it is being **read** — one
/// line per fact, in the words the form's own fields and entries already use.
///
/// Pure functions, apart from the widgets, because the page has two postures
/// over one route and the fastest way to make them disagree is to let each
/// write its own sentence. Every line here is a stored fact restated, never a
/// new one: the macro line is the picker row's ([formatMacroLine]), the density
/// is the density entry's own headline plus the sentence it was entered as
/// (read back through [volumeWeightFromDensity]), the piece weight is the
/// piece-weight entry's sentence with its number in place, and the admitted
/// units are the chips' own labels off [allowedUnitsFor].
///
/// **Honest numbers (invariant 3).** A row with no macros reads `needs macros`
/// — the words the dock and the manager's stub band already use — never four
/// zeros. A row whose macros are a machine's and unconfirmed states them: the
/// status strip above says they are left out of totals, which is the fact the
/// page owes a reader, and hiding numbers the editing posture shows would be
/// the two postures telling two stories.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/serving_measure.dart';
import 'macros_format.dart';

/// The volume unit a stored density is read back in. A ratio is not something
/// a kitchen holds, and `cup` is the measure a person can picture.
const kDensityReadingUnit = cup;

/// `60 kcal · 1P 0F 15C /100 g`, or `needs macros` on a row that has none.
///
/// **A row that states a serving leads with the label's own line** —
/// `190 kcal · 7P 16F 7C per 2 tbsp` — because that is the line a person can
/// check against the jar in their hand without a calculator. The per-100
/// figures then read as the aside they are ([per100Fact]).
String macrosFact(Ingredient ingredient, {Measure? serving}) {
  final figures = macrosFactFigures(ingredient, serving: serving);
  if (figures == null) return 'needs macros';
  return '${formatMacroLine(figures.macros)} ${figures.per}';
}

/// The same fact as its two parts — the figures, and the tail that says what
/// they are per — for the posture that draws it as one dense line, energy as
/// a glyph. Null on a row with no panel, where [macrosFact]'s words are the
/// whole answer.
({Macros macros, String per})? macrosFactFigures(
  Ingredient ingredient, {
  Measure? serving,
}) {
  final macros = ingredient.macros;
  if (macros == null) return null;
  final printed = servingPrintedMacros(ingredient, serving: serving);
  if (printed == null || serving == null) {
    return (macros: macros, per: macroBasisSuffix(ingredient.macrosBasis));
  }
  return (
    macros: printed,
    per: 'per ${serving.label.substring(kServingMeasurePrefix.length)}',
  );
}

/// The label's figures, reversed out of the stored per-100 and the serving —
/// `642 kcal/100 ml × 29.57 ml` back to the 190 the jar prints.
///
/// It is the entry arithmetic run backwards, unrounded, which is exactly why
/// the serving is kept: nothing is re-derived from a rounded figure and
/// nothing is invented. Null on a row with no macros or no serving.
Macros? servingPrintedMacros(Ingredient ingredient, {Measure? serving}) {
  final macros = ingredient.macros;
  if (macros == null || serving == null || !(serving.amount > 0)) return null;
  if (serving.basis != ingredient.macrosBasis) return null;
  return macros.scaledBy(serving.amount / 100);
}

/// `per 100 ml · 642 kcal · 23.7P 54.1F 23.7C` — the muted line under a
/// label-led macro fact, for the reader who wants to see what the totals use.
/// Null where the fact already says it.
String? per100Fact(Ingredient ingredient, {Measure? serving}) {
  final macros = ingredient.macros;
  if (macros == null ||
      servingPrintedMacros(ingredient, serving: serving) == null) {
    return null;
  }
  return 'per 100 ${ingredient.macrosBasis.dbValue} · '
      '${formatMacroLine(macros)}';
}

/// The row's category, in the picker's own word for a row without one — a
/// category-less row is a real and honest answer, not a gap.
String categoryFact(Ingredient ingredient) {
  final category = ingredient.category;
  return category == null || category.isEmpty ? 'no category' : category;
}

/// What a line may say about this row — the admission chips, as their labels.
String allowedUnitsFact(Ingredient ingredient) =>
    allowedUnitsFor(ingredient).map((u) => u.label).join(' · ');

/// The stated density, as the sentence it was entered as and the number it is
/// stored as: `1 cup weighs 156.15 g · 0.66 g/ml`. A row with none says what
/// the density entry's own headline says.
///
/// **A row whose serving is a volume reads the density back in that unit** —
/// `2 tbsp weighs 32 g` — with the g/ml as the aside ([densityAsideFact]),
/// because that is the sentence the pack printed and the one that was typed.
/// The stored fact is unchanged either way: one ratio, said in the unit the
/// person is holding.
String densityFact(Ingredient ingredient, {Measure? serving}) {
  final density = ingredient.densityGPerMl;
  if (density == null) return 'none yet — unlocks volume⇄weight';
  final read = _densityReading(serving);
  final perUnit = volumeWeightFromDensity(read.unit, density);
  final stated = '${formatDensity(density)} g/ml';
  if (perUnit == null) return stated;
  final grams = perUnit * read.amount;
  final phrase = formatServingPhrase(read.amount, read.unit);
  final sentence = '$phrase weighs ${formatQuantity(grams)} g';
  return read.fromServing ? sentence : '$sentence · $stated';
}

/// `1.08 g/ml` — the aside under a serving-shaped density sentence, or null
/// where [densityFact] already carries the number.
String? densityAsideFact(Ingredient ingredient, {Measure? serving}) {
  final density = ingredient.densityGPerMl;
  if (density == null || !_densityReading(serving).fromServing) return null;
  return '${formatDensity(density)} g/ml';
}

/// Which amount and unit a stored density is said in: the row's own serving
/// when it is a volume, and otherwise the cup a person can picture.
({double amount, Unit unit, bool fromServing}) _densityReading(
  Measure? serving,
) {
  final stated = serving == null
      ? null
      : servingFromMeasureLabel(serving.label);
  if (stated != null && stated.unit.family == UnitFamily.volume) {
    return (amount: stated.amount, unit: stated.unit, fromServing: true);
  }
  return (amount: 1, unit: kDensityReadingUnit, fromServing: false);
}

/// The stated piece weight as the piece-weight entry's own sentence — `1 piece
/// weighs 200 g` — or null on a row that states none, where there is no
/// sentence to say.
String? pieceWeightFact(Ingredient ingredient) {
  final weight = ingredient.pieceBasisAmount;
  if (weight == null) return null;
  return '1 piece weighs ${formatQuantity(weight)} '
      '${ingredient.macrosBasis.baseUnit.label}'
      '${pieceWeightSourceSuffix(ingredient.pieceSource)}';
}

/// ` · borrowed from onion, medium` for a seeded weight; nothing for a typed
/// one — "yours" is the default reading of a row you own. A curated seed
/// number reads **estimate**, the same word the measures list gives it.
///
/// Shared with the piece-weight entry's own headline, so the number reads the
/// same whether the page is being edited or read.
String pieceWeightSourceSuffix(String? source) {
  if (source == null || source == 'manual') return '';
  if (source == 'seed:typical') return ' · estimate';
  return ' · $source';
}

/// The other names this row answers to, joined — empty when it has none.
String aliasesFact(Iterable<IngredientAlias> aliases) =>
    aliases.map((a) => a.text).join(' · ');

/// One measure, in the measures editor's own words: `onion, medium · 110 g`.
/// The provenance word rides beside it on the row rather than inside this
/// string, exactly as the editor draws it.
String measureFact(Measure measure) =>
    '${measure.label} · ${formatQuantity(measure.amount)} '
    '${measure.basis.baseUnit.label}';
