/// Open Food Facts payload → [IngredientDraft]. Pure Dart, tested off committed
/// fixtures.
///
/// Reads the four required macros plus optional fibre, and leaves OFF's
/// near-miss keys alone. Anything the payload does not establish comes out null
/// with a reason, never zero. The basis is the exception: OFF files per-100 ml
/// labels under the same `*_100g` keys, so [_basisFor] weighs the rest of the
/// payload.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';
import '../domain/serving_measure.dart';
import 'ingredient_draft.dart';

/// Maps a decoded `/api/v2/product/{barcode}.json` body to a draft. Returns
/// null when `status` is not 1 (not found) or `product` is missing or not an
/// object; the caller tells the two apart.
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
    serving: panel.printedServing,
    // densityGPerMl stays null on purpose: OFF holds no density, and a pack
    // size is a volume OR a mass, never the ratio between them.
    packSize: parsePackQuantity(_text(product['quantity'])),
  );
}

/// What the panel read as: per-100 macros in their basis, a per-serving panel
/// as printed, or nothing, with the gap saying which. `printedServing` rides
/// beside per-100 macros when the label named a serving.
typedef _Panel = ({
  Macros? macros,
  MacrosBasis basis,
  DraftMacrosGap gap,
  DraftServingPanel? serving,
  DraftServing? printedServing,
});

_Panel _readPanel(Map<String, Object?> p) {
  final per = _perKey(p);
  final n = p['nutriments'];
  final nutriments = n is Map<String, Object?> ? n : const <String, Object?>{};

  // A per-serving panel rides through as printed, with OFF's numeric
  // `serving_quantity` when present. It is never converted to per-100 here:
  // `serving_size` is free text and is not parsed. The form's per-serving mode
  // does the arithmetic.
  if (per == 'serving') {
    final printed = _four(nutriments, '_serving');
    if (printed == null) {
      // Flagged per serving but only `*_prepared_*` serving keys exist: there
      // is no printed panel to carry.
      return (
        macros: null,
        basis: _basisFor(p),
        gap: DraftMacrosGap.noPanel,
        serving: null,
        printedServing: null,
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
      printedServing: null,
    );
  }
  final macros = _four(nutriments, '_100g');
  final basis = _basisFor(p);
  return (
    macros: macros,
    basis: basis,
    gap: macros == null ? DraftMacrosGap.noPanel : DraftMacrosGap.none,
    serving: null,
    printedServing: macros == null ? null : _printedServing(p, basis),
  );
}

/// The serving a per-100 label prints beside its panel, e.g. "0.25 cup (28 g)".
/// The pack's own words are used when the row's basis can say them, else the
/// bracketed figure. Nothing is converted here.
DraftServing? _printedServing(Map<String, Object?> p, MacrosBasis basis) {
  final text = _text(p['serving_size']);
  if (text == null) return null;
  final family = basis.baseUnit.family;
  final printed = readPrintedServing(text);
  final candidates = [printed.said, printed.bracketed];
  for (final candidate in candidates) {
    if (candidate == null || candidate.unit.family != family) continue;
    final n = p['nutriments'];
    return DraftServing(
      amount: candidate.amount,
      unit: candidate.unit,
      printedText: text,
      printed: n is Map<String, Object?> ? _four(n, '_serving') : null,
    );
  }
  return null;
}

/// Which 100 the panel is per: grams or millilitres. Strongest evidence first:
///
/// 1. `nutrition_data_per` naming ml, however spelt.
/// 2. The net quantity on the pack ("1,5 l", "1 kg").
/// 3. The mass or volume printed in parentheses beside the serving.
/// 4. `serving_quantity_unit`. Weaker: OFF derives it from free text, and a US
///    "1 cup (62 g)" of dry macaroni comes back as `ml`.
/// 5. OFF's category taxonomy (`en:beverages`), which also holds powders.
///
/// A `nutrition_data_per` of `100g` is OFF's form default, so it is treated as
/// unstated.
MacrosBasis _basisFor(Map<String, Object?> p) {
  if (_perKey(p)?.endsWith('ml') ?? false) return MacrosBasis.perMl;

  final packUnit = parsePackQuantity(_text(p['quantity']))?.unit;
  final printedUnit = readPrintedServing(
    _text(p['serving_size']),
  ).bracketed?.unit;
  final servingUnit = unitFromWord(
    _text(p['serving_quantity_unit']) ?? '',
    families: const {UnitFamily.mass, UnitFamily.volume},
  );
  for (final unit in [packUnit, printedUnit, servingUnit]) {
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

/// `nutrition_data_per` reduced to letters and digits, so `100 ml`, `100_ml`
/// and `100ML` are all `100ml`. Null when absent.
String? _perKey(Map<String, Object?> p) => _text(
  p['nutrition_data_per'],
)?.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// The macro panel under one OFF key [suffix] (`_100g`, `_serving`), or null
/// unless all four required macros are present ([Macros.tryParse]'s rule).
///
/// Only the plain keys: `energy-kcal` with no suffix is ambiguous, and
/// `*_prepared_100g` describes the made-up drink, not the powder.
/// `fiber$suffix` rides along when present ([Macros.fiber]).
Macros? _four(Map<String, Object?> n, String suffix) {
  final kcal = _number(n['energy-kcal$suffix']);
  final protein = _number(n['proteins$suffix']);
  final carb = _number(n['carbohydrates$suffix']);
  final fat = _number(n['fat$suffix']);
  if (kcal == null || protein == null || carb == null || fat == null) {
    return null;
  }
  return Macros(
    kcal: kcal,
    protein: protein,
    carb: carb,
    fat: fat,
    fiber: _number(n['fiber$suffix']),
  );
}

/// OFF's numeric `serving_quantity` with the basis its unit names, or `(null,
/// null)` when absent, not positive, or in a unit that is neither g nor ml. A
/// serving with no unit takes the basis [_basisFor] reads.
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

/// Parses OFF's free-text `quantity` ("400 ml", "1 kg", "1 oz (28.3 g)") into a
/// catalog quantity, or null when it does not parse cleanly. The pack size is
/// only an opt-in measure, so null just means no offer.
DraftPackSize? parsePackQuantity(String? quantity) {
  // Contributors leave a stray stop or comma after the unit ("226g,"); it is
  // punctuation, not a second quantity.
  final text = quantity?.trim().replaceFirst(RegExp(r'[\s,.;:]+$'), '');
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

/// OFF's `brands` is comma-separated, with parent companies appended. Only the
/// first is kept.
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
