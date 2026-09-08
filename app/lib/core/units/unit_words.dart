/// The words a person (or a food database) writes for a unit — PURE DART.
///
/// Two readers need this table: a recipe page's yield line ("MAKES 12
/// muffins", "Yields 1 cup") and a barcode product's pack size ("400 ml",
/// "1 oz (28.3 g)"). They were two tables that agreed on `g` and disagreed on
/// `gr`, `fl oz` and `kilo` — a word one reader understood and the other
/// refused, for no reason either could state.
///
/// The line both readers took, and this keeps: **a word outside the table is
/// never approximated into a unit.** `cl`, `x`, `pack` stay unparsed, and the
/// caller decides what that means — a count noun, or a refusal.
library;

import 'units.dart';

/// The catalog unit [word] names, or null when the table does not know it.
///
/// [families] narrows the answer to the kinds of unit the caller can accept:
/// a pack size is a weight or a volume, so "6 pieces" is not a pack size even
/// though `pieces` is a unit. Omitted, every family the table holds is fair.
Unit? unitFromWord(String word, {Set<UnitFamily>? families}) {
  final unit = _unitWords[word.toLowerCase().trim()];
  if (unit == null) return null;
  if (families != null && !families.contains(unit.family)) return null;
  return unit;
}

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
