/// Table-driven over REAL Open Food Facts payloads, captured verbatim on
/// 2026-08-31 from `GET /api/v2/product/{barcode}.json` with the client's own
/// `fields=` projection ([OffLookup.fields]). The only edit is the removal of
/// the `nutriments_estimated` block OFF returns unasked — ~1.5 kB of modelled
/// micronutrients this mapper never looks at.
///
/// The barcodes are named in each case so a future reader can re-fetch them.
/// Real payloads matter here because the whole risk of this mapper is OFF's
/// shape, not our arithmetic: the near-miss keys (`energy-kcal` with no
/// suffix, `*_prepared_100g`), the empty-string `quantity`, the comma-list
/// `brands` and the `100ml` basis are all things a hand-written fixture would
/// have quietly got wrong.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/macros.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/ingredients/barcode/ingredient_draft.dart';
import 'package:mise/features/ingredients/barcode/off_lookup.dart';
import 'package:mise/features/ingredients/barcode/off_mapper.dart';

Map<String, Object?> loadFixture(String name) {
  final file = File('test/features/ingredients/barcode/fixtures/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

typedef _Case = ({
  String fixture,
  String barcode,
  String why,
  String? suggestedName,
  String? brand,
  Macros? macros,
  MacrosBasis basis,
  DraftMacrosGap gap,
  DraftPackSize? packSize,
});

const _cases = <_Case>[
  (
    fixture: 'nutella_per_100g',
    barcode: '3017620422003',
    why: 'a full per-100 g panel, and a `quantity` OFF stores as ""',
    suggestedName: 'Nutella',
    brand: 'Nutella',
    macros: Macros(kcal: 539, protein: 6.3, carb: 57.5, fat: 30.9),
    basis: MacrosBasis.perG,
    gap: DraftMacrosGap.none,
    packSize: null,
  ),
  (
    fixture: 'oatly_per_100ml',
    barcode: '7394376616020',
    why: 'a liquid label read per 100 ml — the basis rides through, 7.7',
    suggestedName: 'Ruokaan Fraiche',
    brand: 'Oatly',
    macros: Macros(kcal: 177, protein: 1, carb: 9, fat: 15),
    basis: MacrosBasis.perMl,
    gap: DraftMacrosGap.none,
    packSize: DraftPackSize(200, ml),
  ),
  (
    fixture: 'monster_per_100ml',
    barcode: '0070847811169',
    why:
        'per 100 ml with real zeros in the panel — zeros OFF asserts are '
        'kept, unlike the zeros we refuse to invent',
    suggestedName: 'Monster Energy',
    brand: 'Monster',
    macros: Macros(
      kcal: 48.6077062234771,
      protein: 0,
      carb: 12.2575954824421,
      fat: 0,
    ),
    basis: MacrosBasis.perMl,
    gap: DraftMacrosGap.none,
    packSize: DraftPackSize(16, oz),
  ),
  (
    fixture: 'nesquik_no_panel',
    barcode: '3033710065967',
    why:
        'THE SPARSE ONE — name, brand and pack size, but every nutriment '
        'is a `*_prepared_100g` key describing the made-up drink, not the '
        'powder in the tin',
    suggestedName: 'NESQUIK Cacao',
    brand: 'Nestlé',
    macros: null,
    basis: MacrosBasis.perG,
    gap: DraftMacrosGap.noPanel,
    packSize: DraftPackSize(1, kg),
  ),
];

void main() {
  group('draftFromOffBody', () {
    for (final c in _cases) {
      test('${c.fixture} (${c.barcode}) — ${c.why}', () {
        final draft = draftFromOffBody(loadFixture(c.fixture));

        expect(draft, isNotNull, reason: 'fixture is a found product');
        expect(draft!.barcode, c.barcode);
        expect(draft.suggestedName, c.suggestedName);
        expect(draft.brand, c.brand);
        expect(draft.macros, c.macros);
        expect(draft.macrosBasis, c.basis);
        expect(draft.macrosGap, c.gap);
        expect(draft.packSize, c.packSize);

        // Invariant across every row: a lookup prefills, it never completes.
        expect(draft.source, DraftSource.barcode);
        expect(draft.sourceValue, 'off:${c.barcode}');
        expect(draft.attribution, 'Open Food Facts · ODbL');
        // OFF holds no density — D1's never-invent line in one assertion.
        expect(draft.densityGPerMl, isNull);
        // A gap is explained iff the macros are missing.
        expect(draft.macrosGap == DraftMacrosGap.none, draft.macros != null);
      });
    }

    test('a not-found body maps to nothing (5060335637000)', () {
      // OFF answers an unknown code `{"status": 0}` — the mapper refuses it
      // rather than producing an empty draft the form would happily save.
      expect(draftFromOffBody(loadFixture('unknown_not_found')), isNull);
    });

    test('a per-serving panel leaves the macros blank, with the reason', () {
      // Constructed, not captured: OFF's API normalizes contributed panels
      // onto `*_100g` keys, so `nutrition_data_per: "serving"` is rare in a
      // live response — but it is in OFF's schema and D1 rules on it, so the
      // branch is pinned here. Everything else is shaped like the fixtures.
      final draft = draftFromOffBody({
        'status': 1,
        'code': '1234567890128',
        'product': <String, Object?>{
          'code': '1234567890128',
          'product_name': 'Trail mix',
          'nutrition_data_per': 'serving',
          'serving_size': '1 serving (40 g)',
          'nutriments': <String, Object?>{
            'energy-kcal_serving': 210.0,
            'proteins_serving': 6.0,
            'carbohydrates_serving': 18.0,
            'fat_serving': 13.0,
          },
        },
      });

      expect(draft!.macros, isNull);
      expect(draft.macrosGap, DraftMacrosGap.perServingPanel);
      expect(draft.macrosGap.message, contains('would be a guess'));
      // The name still arrives — a missing panel is not a failed lookup.
      expect(draft.suggestedName, 'Trail mix');
    });

    test('a half-filled panel is no panel — three numbers and a zero is a '
        'lie the totals would then tell', () {
      final draft = draftFromOffBody({
        'status': 1,
        'product': <String, Object?>{
          'code': '1234567890128',
          'product_name': 'Half a label',
          'nutrition_data_per': '100g',
          'nutriments': <String, Object?>{
            'energy-kcal_100g': 120,
            'proteins_100g': 3,
            'carbohydrates_100g': 20,
            // fat_100g absent
          },
        },
      });

      expect(draft!.macros, isNull);
      expect(draft.macrosGap, DraftMacrosGap.noPanel);
    });

    test('a shapeless body is rejected, not coerced', () {
      expect(draftFromOffBody({'status': 1}), isNull);
      expect(draftFromOffBody({'status': 1, 'product': 'nope'}), isNull);
      expect(draftFromOffBody(const {}), isNull);
    });

    test('the name falls back to the brand, then to blank', () {
      Map<String, Object?> body(Map<String, Object?> product) => {
        'status': 1,
        'product': {'code': '1234567890128', ...product},
      };

      expect(
        draftFromOffBody(
          body({'product_name': '', 'brands': 'Ferrero'}),
        )!.suggestedName,
        'Ferrero',
      );
      expect(draftFromOffBody(body(const {}))!.suggestedName, '');
      // The raw name stays null when OFF stored "" — absent, not blank.
      expect(
        draftFromOffBody(body({'product_name': '  '}))!.productName,
        isNull,
      );
    });
  });

  group('parsePackQuantity', () {
    test('reads the pack sizes OFF actually stores', () {
      expect(parsePackQuantity('400 ml'), const DraftPackSize(400, ml));
      expect(parsePackQuantity('200ml'), const DraftPackSize(200, ml));
      expect(parsePackQuantity('1 kg'), const DraftPackSize(1, kg));
      expect(parsePackQuantity('5.2 oz'), const DraftPackSize(5.2, oz));
      expect(parsePackQuantity('1 gram'), const DraftPackSize(1, g));
      // The US entries carry a parenthetical conversion after the number.
      expect(parsePackQuantity('1 oz (28.3 g)'), const DraftPackSize(1, oz));
      // A comma decimal, which European contributors type.
      expect(parsePackQuantity('1,5 l'), const DraftPackSize(1.5, l));
    });

    test('refuses what it cannot land on a catalog unit', () {
      // Not approximated — the pack size is only ever an opt-in measure, so
      // "not offered" is a perfectly good answer.
      expect(parsePackQuantity('6 x 33cl'), isNull);
      expect(parsePackQuantity('33 cl'), isNull);
      expect(parsePackQuantity('1 pack'), isNull);
      expect(parsePackQuantity(''), isNull);
      expect(parsePackQuantity(null), isNull);
      expect(parsePackQuantity('0 g'), isNull);
    });
  });
}
