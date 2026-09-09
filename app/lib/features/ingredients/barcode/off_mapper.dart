/// Open Food Facts payload → [IngredientDraft] — PURE DART (invariant 2), so it
/// is tested off committed fixtures with no network.
///
/// The mapping is deliberately narrow. OFF returns hundreds of nutriment
/// keys, several of which *look* like the ones we want; this file reads four
/// and explains why the near-misses are left alone. Anything the payload does
/// not establish comes out null with a reason attached — never zero.
///
/// The one place it reads WIDELY is the basis — which 100 the four numbers are
/// per. OFF files a per-100 ml label under the same `*_100g` keys as a per-100
/// g one and defaults `nutrition_data_per` to `100g` for both, so the panel
/// alone cannot say; [_basisFor] weighs the rest of the payload instead.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/unit_words.dart';
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
  final panel = _readPanel(product);

  return IngredientDraft(
    // Falls back to the brand, then to blank — an empty name field the user
    // types into beats a name we assembled out of parts.
    suggestedName: productName ?? brand ?? '',
    source: DraftSource.barcode,
    barcode: code,
    productName: productName,
    brand: brand,
    macros: panel.macros,
    macrosBasis: panel.basis,
    macrosGap: panel.gap,
    servingPanel: panel.serving,
    // densityGPerMl stays null on purpose: OFF holds no density, and a pack
    // size is a volume OR a mass, never the ratio between them.
    packSize: parsePackQuantity(_text(product['quantity'])),
  );
}

/// What the panel read as: per-100 macros in their basis, or a per-serving
/// panel carried as printed, or nothing — with the gap saying which.
typedef _Panel = ({
  Macros? macros,
  MacrosBasis basis,
  DraftMacrosGap gap,
  DraftServingPanel? serving,
});

_Panel _readPanel(Map<String, Object?> p) {
  final per = _perKey(p);
  final n = p['nutriments'];
  final nutriments = n is Map<String, Object?> ? n : const <String, Object?>{};

  // A per-serving panel: the four printed figures ride through as printed, with
  // OFF's numeric `serving_quantity` when it has one. Never a per-100 figure
  // from here — the serving's mass is what the conversion needs, and
  // `serving_size` is free text ("1 serving (16 fl oz)") that is never parsed
  // into a number. The host lands the panel on the form's per-serving mode and
  // does the arithmetic in front of the person holding the pack.
  if (per == 'serving') {
    final printed = _four(nutriments, '_serving');
    if (printed == null) {
      // Flagged per serving but the only serving keys are `*_prepared_*`
      // (the NESQUIK shape): there is no printed panel to carry, and no
      // serving weight would make one.
      return (
        macros: null,
        basis: _basisFor(p),
        gap: DraftMacrosGap.noPanel,
        serving: null,
      );
    }
    final (amount, servingBasis) = _servingQuantity(p);
    return (
      macros: null,
      basis: servingBasis ?? _basisFor(p),
      gap: DraftMacrosGap.perServingPanel,
      serving: DraftServingPanel(
        printed: printed,
        servingAmount: amount,
        servingBasis: servingBasis,
        servingSize: _text(p['serving_size']),
      ),
    );
  }
  final macros = _four(nutriments, '_100g');
  return (
    macros: macros,
    basis: _basisFor(p),
    gap: macros == null ? DraftMacrosGap.noPanel : DraftMacrosGap.none,
    serving: null,
  );
}

/// **Which 100 the panel is per** — grams or millilitres.
///
/// OFF stores both columns under the same `*_100g` keys, so this is the only
/// thing standing between an oat milk's per-100 ml label and a row that says
/// it weighs 46 kcal per 100 g. Read strongest evidence first:
///
/// 1. `nutrition_data_per` **naming ml**, however it is spelt (`100ml`,
///    `100 ml`). Somebody changed that field on purpose, so it wins outright.
/// 2. The **net quantity on the pack** — "1,5 l", "1 kg", "7.25oz". It is the
///    legally printed contents, in the unit the label is obliged to use, so a
///    litre bottle is a litre label and a 1 kg bag of coffee beans is a
///    per-100 g one whatever aisle it is sold in.
/// 3. `serving_quantity_unit`. Weaker than the pack, because OFF derives it by
///    normalising the free-text `serving_size` and a US "1 cup (62 g)" of dry
///    macaroni comes back as `ml` — a serving measured by volume, not a label
///    printed per volume.
/// 4. OFF's own category taxonomy: `en:beverages`. Last, because it describes
///    what a product IS rather than how it is measured, and the drinks branch
///    holds beans, leaves and powders as well as liquids — which is exactly
///    what step 2 has already settled by the time this is reached.
///
/// **`100g` is not evidence.** It is the field's default in OFF's own entry
/// form, written unchanged by every app and bot that never asked; the oat milk
/// this rule exists for carries it beside twelve `en:beverages` categories and
/// a label printed per 100 ml. So an explicit gram reading and a missing one
/// are treated alike: unstated, and the pack is asked instead. Nothing here
/// invents a density — the basis says which unit the numbers are per, and
/// crossing between the two still needs a number a person typed.
MacrosBasis _basisFor(Map<String, Object?> p) {
  if (_perKey(p)?.endsWith('ml') ?? false) return MacrosBasis.perMl;

  final packUnit = parsePackQuantity(_text(p['quantity']))?.unit;
  final servingUnit = unitFromWord(
    _text(p['serving_quantity_unit']) ?? '',
    families: const {UnitFamily.mass, UnitFamily.volume},
  );
  for (final unit in [packUnit, servingUnit]) {
    if (unit == null) continue;
    return unit.family == UnitFamily.volume
        ? MacrosBasis.perMl
        : MacrosBasis.perG;
  }

  final categories = p['categories_tags'];
  if (categories is List && categories.contains('en:beverages')) {
    return MacrosBasis.perMl;
  }
  return MacrosBasis.perG;
}

/// `nutrition_data_per`, reduced to the letters and digits contributors agree
/// on: `100 ml`, `100_ml` and `100ML` are all `100ml`, and `serving` stays
/// itself. Null when OFF holds nothing there.
String? _perKey(Map<String, Object?> p) => _text(
  p['nutrition_data_per'],
)?.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// The four macros under one OFF key [suffix] (`_100g`, `_serving`), or null
/// unless all four are there.
///
/// Only the plain keys. The near-misses are real and wrong: `energy-kcal`
/// (no suffix) is whatever column the contributor typed in, and
/// `*_prepared_100g` describes the made-up drink, not the powder in the tin
/// — a cocoa powder mapped from its prepared panel would understate every
/// recipe that used it by roughly a factor of ten. All four or none, the
/// same rule a vocab row's macros obey ([Macros.tryParse]) — three numbers
/// and an invented zero is exactly the dishonest total invariant 3 exists to
/// prevent.
Macros? _four(Map<String, Object?> n, String suffix) {
  final kcal = _number(n['energy-kcal$suffix']);
  final protein = _number(n['proteins$suffix']);
  final carb = _number(n['carbohydrates$suffix']);
  final fat = _number(n['fat$suffix']);
  if (kcal == null || protein == null || carb == null || fat == null) {
    return null;
  }
  return Macros(kcal: kcal, protein: protein, carb: carb, fat: fat);
}

/// OFF's numeric `serving_quantity` with the basis its unit names, or
/// `(null, null)` when there is none or the unit is neither g nor ml. A
/// positive number only — a zero serving is no serving.
///
/// A serving with **no unit at all** keeps its number and takes the basis
/// [_basisFor] reads off the rest of the payload: "250" on a carton of oat
/// milk is 250 ml, and reading the blank as grams is the same mistake the
/// `100g` default invites one field over.
(double?, MacrosBasis?) _servingQuantity(Map<String, Object?> p) {
  final amount = _number(p['serving_quantity']);
  if (amount == null || !(amount > 0)) return (null, null);
  return switch (_text(p['serving_quantity_unit'])?.toLowerCase()) {
    'g' => (amount, MacrosBasis.perG),
    'ml' => (amount, MacrosBasis.perMl),
    null => (amount, _basisFor(p)),
    _ => (null, null),
  };
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
  // A pack is a weight or a volume: "6 pieces" is a count, not a pack size.
  final unit = unitFromWord(
    m.group(2)!,
    families: const {UnitFamily.mass, UnitFamily.volume},
  );
  if (unit == null) return null;
  return DraftPackSize(amount, unit);
}

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
