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

/// The catalog unit a bare typed [label] names ("tbsp", "Cups ", "ml",
/// "batch"), or null when it names none.
///
/// The *authoring* half of this file: [unitFromWord] reads what a page or a
/// product label printed, this reads what a person typed into a label field —
/// so a word that is only a unit's name can be refused before it becomes a
/// second way to say something the chip row already says.
///
/// It asks the catalog itself — [kAllUnits], `batch` included — by the id and
/// the label the app prints, so a unit is recognised by the word the chip row
/// actually shows rather than by whichever spellings the table below happens
/// to list. Robust to casing, surrounding and inner whitespace, and the simple
/// `s` plural ("Cups ", "fl  oz", "tbsps") — the trivial disguises a typed or
/// printed word wears. A caller that also wants the printed spellings
/// ("grams", "tablespoon") falls back to [unitFromWord].
///
/// **One lookup, three readers**, because all three ask the same question of
/// a human's spelling: a measure label that is really a unit
/// ([volumeUnitFromLabel]), a label that already states its own size
/// (`measureWordStatesSize`), and a recipe measure's word against `batch`.
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

/// The catalog **volume** unit a bare [label] names, or null. Measures must
/// never duplicate volume units — density owns volume conversion (ADR-0008 §2:
/// a volume-named weight mapping IS a density) — so the add-measure form uses
/// the resolved unit to REDIRECT the entry into density instead of merely
/// refusing it.
Unit? volumeUnitFromLabel(String label) {
  final unit = unitFromLabel(label);
  return unit != null && unit.family == UnitFamily.volume ? unit : null;
}

/// Whether [label] is just the name of a catalog volume unit — see
/// [volumeUnitFromLabel]. Keeps the chip row / manage UI from offering (or
/// authoring) a volume-named measure that slipped in anyway; the seed
/// pipeline skips FDC volume portions for the same reason.
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
