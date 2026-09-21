/// The words a person or a food database writes for a unit. Pure Dart.
///
/// A word outside the table is never approximated into a unit: it stays
/// unparsed and the caller decides what that means.
library;

import 'units.dart';

/// The catalog unit [word] names, or null. [families] narrows the answer to the
/// kinds of unit the caller accepts; omitted, every family is fair.
Unit? unitFromWord(String word, {Set<UnitFamily>? families}) {
  final unit = _unitWords[word.toLowerCase().trim()];
  if (unit == null) return null;
  if (families != null && !families.contains(unit.family)) return null;
  return unit;
}

/// The catalog unit a bare typed [label] names ("tbsp", "Cups ", "batch"), or
/// null.
///
/// Matches [kAllUnits] by id and printed label, ignoring case, whitespace and a
/// simple `s` plural. A caller that also wants printed spellings ("grams",
/// "tablespoon") falls back to [unitFromWord].
Unit? unitFromLabel(String label) {
  final normalized = label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return null;
  final singular = normalized.endsWith('s')
      ? normalized.substring(0, normalized.length - 1)
      : null;
  for (final u in kAllUnits) {
    for (final name in [u.id.toLowerCase(), u.label.toLowerCase()]) {
      if (normalized == name || singular == name) return u;
    }
  }
  return null;
}

/// The catalog volume unit a bare [label] names, or null. A volume-named weight
/// is a density, not a measure (ADR-0008), so the add-measure form redirects
/// such an entry into density.
Unit? volumeUnitFromLabel(String label) {
  final unit = unitFromLabel(label);
  return unit != null && unit.family == UnitFamily.volume ? unit : null;
}

/// Whether [label] is just the name of a catalog volume unit; see
/// [volumeUnitFromLabel].
bool isVolumeUnitLabel(String label) => volumeUnitFromLabel(label) != null;

/// The kitchen's vocabulary, in the spellings a recipe page and a product
/// label actually print.
const _unitWords = <String, Unit>{
  'g': g,
  'gr': g,
  'gram': g,
  'grams': g,
  'gramme': g,
  'grammes': g,
  'kg': kg,
  'kilo': kg,
  'kilos': kg,
  'kilogram': kg,
  'kilograms': kg,
  'oz': oz,
  'ounce': oz,
  'ounces': oz,
  'lb': lb,
  'lbs': lb,
  'pound': lb,
  'pounds': lb,
  'ml': ml,
  'millilitre': ml,
  'millilitres': ml,
  'milliliter': ml,
  'milliliters': ml,
  'l': l,
  'litre': l,
  'litres': l,
  'liter': l,
  'liters': l,
  'tsp': tsp,
  'teaspoon': tsp,
  'teaspoons': tsp,
  'tbsp': tbsp,
  'tbs': tbsp,
  'tablespoon': tbsp,
  'tablespoons': tbsp,
  'fl oz': flOz,
  'floz': flOz,
  'cup': cup,
  'cups': cup,
  'pt': pint,
  'pint': pint,
  'pints': pint,
  'qt': quart,
  'quart': quart,
  'quarts': quart,
  'piece': pieces,
  'pieces': pieces,
};
