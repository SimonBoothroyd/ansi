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

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import 'macros_format.dart';

/// The volume unit a stored density is read back in. A ratio is not something
/// a kitchen holds, and `cup` is the measure a person can picture.
const kDensityReadingUnit = cup;

/// `60 kcal · 1P 0F 15C /100 g`, or `needs macros` on a row that has none.
String macrosFact(Ingredient ingredient) {
  final macros = ingredient.macros;
  if (macros == null) return 'needs macros';
  return '${formatMacroLine(macros)} '
      '${macroBasisSuffix(ingredient.macrosBasis)}';
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
String densityFact(Ingredient ingredient) {
  final density = ingredient.densityGPerMl;
  if (density == null) return 'none yet — unlocks volume⇄weight';
  final perUnit = volumeWeightFromDensity(kDensityReadingUnit, density);
  final stated = '${formatDensity(density)} g/ml';
  if (perUnit == null) return stated;
  return '1 ${kDensityReadingUnit.label} weighs ${formatQuantity(perUnit)} g '
      '· $stated';
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
/// one — "yours" is the default reading of a row you own.
///
/// Shared with the piece-weight entry's own headline, so the number reads the
/// same whether the page is being edited or read.
String pieceWeightSourceSuffix(String? source) {
  if (source == null || source == 'manual') return '';
  if (source == 'seed:typical') return ' · typical';
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
