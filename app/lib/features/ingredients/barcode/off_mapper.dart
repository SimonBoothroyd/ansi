/// Open Food Facts payload → [IngredientDraft] — PURE DART (invariant 2), so
/// it is tested off committed fixtures with no network (plan 0020 D2).
///
/// The mapping is deliberately narrow. OFF returns hundreds of nutriment
/// keys, several of which *look* like the ones we want; this file reads four
/// and explains why the near-misses are left alone. Anything the payload does
/// not establish comes out null with a reason attached — never zero.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import 'ingredient_draft.dart';

/// Maps a decoded `/api/v2/product/{barcode}.json` body to a draft.
///
/// Returns null when the body carries no usable product — `status` is not 1
/// (OFF's "product not found"), or `product` is missing/not an object. The
/// caller separates those two cases: a not-found answer is a designed state,
/// a shapeless 200 is a malformed one.
IngredientDraft? draftFromOffBody(Map<String, Object?> body) {
  if (body['status'] != 1) return null;
  final product = body['product'];
  if (product is! Map<String, Object?>) return null;

  final code = _text(product['code']) ?? _text(body['code']);
  final productName = _text(product['product_name']);
  final brand = _firstBrand(_text(product['brands']));
  final (macros, basis, gap) = _readPanel(product);

  return IngredientDraft(
    // Falls back to the brand, then to blank — an empty name field the user
    // types into beats a name we assembled out of parts.
    suggestedName: productName ?? brand ?? '',
    source: DraftSource.barcode,
    barcode: code,
    productName: productName,
    brand: brand,
    macros: macros,
    macrosBasis: basis,
    macrosGap: gap,
    // densityGPerMl stays null on purpose: OFF holds no density, and a pack
    // size is a volume OR a mass, never the ratio between them.
    packSize: parsePackQuantity(_text(product['quantity'])),
  );
}

/// The panel: per-100 macros, the basis they were read in, and — when there
/// are none — why.
(Macros?, MacrosBasis, DraftMacrosGap) _readPanel(Map<String, Object?> p) {
  final per = _text(p['nutrition_data_per']);
  // A per-serving panel does not convert to per-100 without the serving's
  // mass, and OFF's `serving_size` is free text ("1 serving (16 fl oz)").
  // D1: leave the macros blank with a note rather than divide by a guess.
  if (per == 'serving') {
    return (null, MacrosBasis.perG, DraftMacrosGap.perServingPanel);
  }
  // `100ml` is a liquid label read as the label reads it (7.7). Absent or
  // unrecognised, the per-100 keys below are still per 100 of *something*,
  // and grams is both the column default and the commoner panel.
  final basis = per == '100ml' ? MacrosBasis.perMl : MacrosBasis.perG;

  final n = p['nutriments'];
  if (n is! Map<String, Object?>) {
    return (null, basis, DraftMacrosGap.noPanel);
  }
  // Only the plain `*_100g` keys. The near-misses are real and wrong:
  // `energy-kcal` (no suffix) is whatever column the contributor typed in,
  // and `*_prepared_100g` describes the made-up drink, not the powder in the
  // tin — a cocoa powder mapped from its prepared panel would understate
  // every recipe that used it by roughly a factor of ten.
  final kcal = _number(n['energy-kcal_100g']);
  final protein = _number(n['proteins_100g']);
  final carb = _number(n['carbohydrates_100g']);
  final fat = _number(n['fat_100g']);
  // All four or none, the same rule a vocab row's macros obey
  // ([Macros.tryParse]) — three numbers and an invented zero is exactly the
  // dishonest total invariant 3 exists to prevent.
  if (kcal == null || protein == null || carb == null || fat == null) {
    return (null, basis, DraftMacrosGap.noPanel);
  }
  return (
    Macros(kcal: kcal, protein: protein, carb: carb, fat: fat),
    basis,
    DraftMacrosGap.none,
  );
}

/// Parses OFF's free-text `quantity` ("400 ml", "1 kg", "1 oz (28.3 g)")
/// into a catalog quantity, or null when it does not land cleanly on one.
///
/// Null is the common answer and the safe one: the pack size is only ever
/// offered as an opt-in measure, so an unparsed "6 x 33cl" simply isn't
/// offered rather than being approximated.
DraftPackSize? parsePackQuantity(String? quantity) {
  final text = quantity?.trim();
  if (text == null || text.isEmpty) return null;
  // number + unit word, with an optional trailing parenthetical conversion
  // ("1 oz (28.3 g)") that OFF's US entries carry.
  final m = RegExp(
    r'^([0-9]+(?:[.,][0-9]+)?)\s*([a-zA-Z][a-zA-Z ]*?)\s*(?:\(.*\))?$',
  ).firstMatch(text);
  if (m == null) return null;
  final amount = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (amount == null || !(amount > 0)) return null;
  final unit = _packUnits[m.group(2)!.toLowerCase().trim()];
  if (unit == null) return null;
  return DraftPackSize(amount, unit);
}

/// The pack-size unit words OFF's `quantity` actually uses, mapped to the
/// catalog. Anything outside this table (`cl`, `dl`, "x", "pack") is left
/// unparsed rather than approximated.
const _packUnits = <String, Unit>{
  'g': g,
  'gr': g,
  'gram': g,
  'grams': g,
  'gramme': g,
  'grammes': g,
  'kg': kg,
  'kilogram': kg,
  'kilograms': kg,
  'mg': mg,
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
  'oz': oz,
  'ounce': oz,
  'ounces': oz,
  'lb': lb,
  'lbs': lb,
  'pound': lb,
  'pounds': lb,
  'fl oz': flOz,
  'floz': flOz,
  'pt': pint,
  'pint': pint,
  'pints': pint,
  'qt': quart,
  'quart': quart,
  'quarts': quart,
};

/// OFF's `brands` is a comma-separated list because contributors append the
/// parent company ("Nutella, Ferrero, Yum yum"). Only the first is the brand
/// a shopper would name.
String? _firstBrand(String? brands) {
  if (brands == null) return null;
  final first = brands.split(',').first.trim();
  return first.isEmpty ? null : first;
}

/// A non-empty trimmed string, or null. OFF returns `""` for fields a
/// contributor cleared, which must read as absent, not as a blank name.
String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A finite number, or null. OFF occasionally stores a nutriment as a string
/// ("12.5") and, rarely, as junk; neither may become a silent zero.
double? _number(Object? value) {
  final n = switch (value) {
    final num v => v.toDouble(),
    final String s => double.tryParse(s.trim()),
    _ => null,
  };
  if (n == null || !n.isFinite || n < 0) return null;
  return n;
}
