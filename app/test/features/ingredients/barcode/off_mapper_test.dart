/// Table-driven over REAL Open Food Facts payloads, captured verbatim on
/// 2026-08-31 (and the two per-serving ones on 2026-09-03) from
/// `GET /api/v2/product/{barcode}.json` with the client's own `fields=`
/// projection ([OffLookup.fields]). The only edit is the removal of the
/// `nutriments_estimated` block OFF returns unasked — ~1.5 kB of modelled
/// micronutrients this mapper never looks at — with ONE exception, named on
/// its case: `peanut_butter_per_serving` is a real capture whose
/// `nutrition_data_per` was flipped `100g` → `serving`. OFF's search was
/// unavailable on the day, and none of ~30 US products probed by hand was
/// flagged per serving while still carrying the plain `*_serving` four
/// (`kraft_mac_per_serving` is what those look like — the flag with only
/// `*_prepared_serving` keys under it). The peanut butter's `*_serving`
/// keys, `serving_quantity` and `serving_size` are all OFF's own.
///
/// `oat_milk_ml_label_as_100g` is a later capture (2026-09-09, the owner's own
/// scan) and the only one carrying `categories_tags`, which the projection did
/// not ask for until the basis rule needed it.
///
/// The barcodes are named in each case so a future reader can re-fetch them.
/// Real payloads matter here because the whole risk of this mapper is OFF's
/// shape, not our arithmetic: the near-miss keys (`energy-kcal` with no
/// suffix, `*_prepared_100g`), the empty-string `quantity`, the comma-list
/// `brands`, the `100ml` basis and — the sharpest of them — a `100g` that
/// means nothing at all are things a hand-written fixture would have quietly
/// got wrong.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/ingredient_draft.dart';
import 'package:ansi/features/ingredients/barcode/off_lookup.dart';
import 'package:ansi/features/ingredients/barcode/off_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

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
  DraftServingPanel? servingPanel,
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
    servingPanel: null,
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
    servingPanel: null,
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
    servingPanel: null,
  ),
  (
    fixture: 'oat_milk_ml_label_as_100g',
    barcode: '0850032825009',
    why:
        'THE ONE THE OWNER SCANNED — a carton whose label is per 100 ml, '
        'filed by OFF under `nutrition_data_per: "100g"` with no quantity '
        'and no serving at all. The gram reading is the field’s DEFAULT, not '
        'a statement; the twelve `en:beverages` categories are what the '
        'payload actually says, and the row lands per 100 ml with no density '
        'implied',
    suggestedName: 'Minor Figures Barista Oat',
    brand: 'Minor Figures',
    macros: Macros(
      kcal: 46.511627906977,
      protein: 0.42283298097252,
      carb: 9.3023255813953,
      fat: 2.1141649048626,
    ),
    basis: MacrosBasis.perMl,
    gap: DraftMacrosGap.none,
    packSize: null,
    servingPanel: null,
  ),
  (
    fixture: 'cheddar_shreds_cup_serving_as_ml',
    barcode: '0099482514778',
    why:
        'THE OWNER’S CHEDDAR SHREDS — a bag sold by weight and served by the '
        'quarter-cup, which OFF normalises into `serving_quantity_unit: ml`; '
        'the pack’s "226g," carries a stray comma and the serving’s own '
        '"(28 g)" is the label’s conversion. Per 100 g, from the pack first '
        'and the parenthetical second — never the ml. (The name is OFF’s '
        'contributor’s, typo and all: the mapper carries what it was given)',
    suggestedName: 'Mozzarella chese',
    brand: '365',
    macros: Macros(
      kcal: 285.714285714286,
      protein: 0,
      carb: 21.4285714285714,
      fat: 25,
    ),
    basis: MacrosBasis.perG,
    gap: DraftMacrosGap.none,
    packSize: DraftPackSize(226, g),
    servingPanel: null,
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
    servingPanel: null,
  ),
  (
    fixture: 'peanut_butter_per_serving',
    barcode: '0851087000250',
    why:
        'A PER-SERVING PANEL (plan 0027 M-D5) — the four `*_serving` figures '
        'ride through as printed, with OFF’s numeric serving_quantity; the '
        'per-100 keys beside them are NOT read (the row derives its own, in '
        'front of the person). Captured, with the flag flipped — see the '
        'header',
    suggestedName: 'Peanut Butter (The Bees Knees)',
    brand: 'Peanut Butter & Co',
    macros: null,
    basis: MacrosBasis.perG,
    gap: DraftMacrosGap.perServingPanel,
    packSize: null,
    servingPanel: DraftServingPanel(
      printed: Macros(kcal: 180, protein: 6, carb: 10, fat: 14),
      servingAmount: 32,
      servingBasis: MacrosBasis.perG,
      servingSize: '2 Tbsp (32 g)',
    ),
  ),
  (
    fixture: 'kraft_mac_per_serving',
    barcode: '0021000658831',
    why:
        'flagged per serving, but the only serving keys are '
        '`*_prepared_serving` (the made-up dish, not the box) — no printed '
        'panel to carry, so no serving weight would make one: no panel, '
        'and the serving row is not opened',
    suggestedName: 'mac & cheese',
    brand: 'Kraft',
    macros: null,
    basis: MacrosBasis.perG,
    gap: DraftMacrosGap.noPanel,
    packSize: DraftPackSize(7.25, oz),
    servingPanel: null,
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
        expect(draft.servingPanel, c.servingPanel);
        // A per-serving panel is carried iff the gap says so — and never
        // beside per-100 macros (M-D5: the per-100 reading is the host's).
        expect(
          draft.servingPanel != null,
          draft.macrosGap == DraftMacrosGap.perServingPanel,
        );

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

    group('a per-serving panel', () {
      // Constructed variants of the peanut-butter fixture's shape, for the
      // serving-quantity legs a single capture cannot cover.
      Map<String, Object?> body(Map<String, Object?> product) => {
        'status': 1,
        'code': '1234567890128',
        'product': <String, Object?>{
          'code': '1234567890128',
          'product_name': 'Trail mix',
          'nutrition_data_per': 'serving',
          'nutriments': <String, Object?>{
            'energy-kcal_serving': 210.0,
            'proteins_serving': 6.0,
            'carbohydrates_serving': 18.0,
            'fat_serving': 13.0,
            // OFF's own per-100 derivation sits beside the printed four;
            // the mapper leaves it alone.
            'energy-kcal_100g': 525.0,
            'proteins_100g': 15.0,
            'carbohydrates_100g': 45.0,
            'fat_100g': 32.5,
          },
          ...product,
        },
      };
      const printed = Macros(kcal: 210, protein: 6, carb: 18, fat: 13);

      test('no numeric serving: the four ride through, the amount is left for '
          'the person — never parsed out of the free text', () {
        final draft = draftFromOffBody(
          body({'serving_size': '1 serving (40 g)'}),
        )!;
        expect(draft.macros, isNull);
        expect(draft.macrosGap, DraftMacrosGap.perServingPanel);
        expect(draft.macrosGap.message, contains('type the serving weight'));
        expect(
          draft.servingPanel,
          const DraftServingPanel(
            printed: printed,
            servingSize: '1 serving (40 g)',
          ),
        );
        // The name still arrives — a missing panel is not a failed lookup.
        expect(draft.suggestedName, 'Trail mix');
      });

      test('an ml serving names the ml basis; a string quantity still '
          'reads', () {
        final draft = draftFromOffBody(
          body({'serving_quantity': '240', 'serving_quantity_unit': 'ml'}),
        )!;
        expect(draft.macrosBasis, MacrosBasis.perMl);
        expect(draft.servingPanel!.servingAmount, 240);
        expect(draft.servingPanel!.servingBasis, MacrosBasis.perMl);
      });

      test('a serving in a unit that is neither g nor ml, or a zero one, is no '
          'serving amount at all', () {
        for (final product in [
          {'serving_quantity': 1, 'serving_quantity_unit': 'oz'},
          {'serving_quantity': 0, 'serving_quantity_unit': 'g'},
          {'serving_quantity': 'a cup'},
        ]) {
          final draft = draftFromOffBody(body(product))!;
          expect(draft.servingPanel!.printed, printed, reason: '$product');
          expect(draft.servingPanel!.servingAmount, isNull, reason: '$product');
          expect(draft.servingPanel!.servingBasis, isNull, reason: '$product');
        }
      });

      test('a half-printed serving panel is no panel — the same all-or-none '
          'rule as per 100', () {
        final draft = draftFromOffBody(
          body({
            'nutriments': <String, Object?>{
              'energy-kcal_serving': 210.0,
              'proteins_serving': 6.0,
              'carbohydrates_serving': 18.0,
            },
          }),
        )!;
        expect(draft.servingPanel, isNull);
        expect(draft.macrosGap, DraftMacrosGap.noPanel);
      });
    });

    test('a half-filled panel is no panel — three numbers and a zero is a lie '
        'the totals would then tell', () {
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

    group('which 100 the panel is per', () {
      // OFF files a per-100 ml label under the same `*_100g` keys as a
      // per-100 g one, so the basis is read off everything else in the
      // payload. These are the legs of that rule, in the order it asks them.
      Map<String, Object?> body(Map<String, Object?> product) => {
        'status': 1,
        'product': <String, Object?>{
          'code': '1234567890128',
          'product_name': 'Something',
          'nutriments': <String, Object?>{
            'energy-kcal_100g': 46.0,
            'proteins_100g': 0.4,
            'carbohydrates_100g': 9.3,
            'fat_100g': 2.1,
          },
          ...product,
        },
      };
      MacrosBasis basisOf(Map<String, Object?> product) =>
          draftFromOffBody(body(product))!.macrosBasis;

      test('a `nutrition_data_per` naming ml wins outright, however it is '
          'spelt — and outranks a pack sold by weight', () {
        for (final per in ['100ml', '100 ml', '100ML', '100_ml']) {
          expect(
            basisOf({'nutrition_data_per': per}),
            MacrosBasis.perMl,
            reason: per,
          );
        }
        // The Monster shape: `100ml` on the panel, `16 oz` on the can.
        expect(
          basisOf({'nutrition_data_per': '100ml', 'quantity': '16 oz'}),
          MacrosBasis.perMl,
        );
      });

      test('`100g` is the field’s DEFAULT, not a statement: the pack is asked '
          'instead, and a mass pack is what keeps a bag of beans in grams', () {
        // Lavazza's shape, and why the beverage leg cannot come first: a 1 kg
        // bag of coffee is `en:beverages` all the way up OFF's taxonomy.
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'quantity': '1 kg',
            'categories_tags': const ['en:beverages'],
          }),
          MacrosBasis.perG,
        );
        // The same field, the same value, a litre bottle: per 100 ml.
        expect(
          basisOf({'nutrition_data_per': '100g', 'quantity': '1,5 l'}),
          MacrosBasis.perMl,
        );
        // With no pack quantity, the serving's unit is what is left to ask.
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'serving_quantity': 250,
            'serving_quantity_unit': 'ml',
          }),
          MacrosBasis.perMl,
        );
        // But the PACK outranks it, and this is why: the kraft_mac shape,
        // where OFF normalised a US "1 cup (62.369 g)" of dry macaroni into
        // `serving_quantity_unit: ml`. A serving measured by volume is not a
        // label printed per volume; the 7.25 oz box is.
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'quantity': '7.25oz',
            'serving_quantity': 62.369,
            'serving_quantity_unit': 'ml',
          }),
          MacrosBasis.perG,
        );
      });

      test('a stray stop after the pack unit is punctuation, not a reason to '
          'fall through to the serving', () {
        expect(parsePackQuantity('226g,'), const DraftPackSize(226, g));
        expect(parsePackQuantity('1,5 l.'), const DraftPackSize(1.5, l));
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'quantity': '226g,',
            'serving_quantity': 28,
            'serving_quantity_unit': 'ml',
          }),
          MacrosBasis.perG,
        );
      });

      test('the conversion printed beside the serving outranks OFF’s '
          'normalised serving unit', () {
        // A quarter-cup of shreds, weighed by the label: grams.
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'serving_size': '0.25 cup (28 g)',
            'serving_quantity': 28,
            'serving_quantity_unit': 'ml',
          }),
          MacrosBasis.perG,
        );
        // A cup of oat milk, measured by the label: millilitres.
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'serving_size': '1 Cup (237 mL)',
            'serving_quantity': 237,
            'serving_quantity_unit': 'ml',
          }),
          MacrosBasis.perMl,
        );
        // No parenthetical at all: the serving unit is what is left.
        expect(
          basisOf({
            'nutrition_data_per': '100g',
            'serving_size': '1 cup',
            'serving_quantity': 240,
            'serving_quantity_unit': 'ml',
          }),
          MacrosBasis.perMl,
        );
      });

      test(
        'with nothing measured either way, OFF’s own drinks category is '
        'the last thing asked — and grams is the answer when it is silent',
        () {
          expect(
            basisOf({
              'categories_tags': const ['en:beverages', 'en:oat-based-drinks'],
            }),
            MacrosBasis.perMl,
          );
          expect(
            basisOf({
              'categories_tags': const ['en:spreads', 'en:sweet-spreads'],
            }),
            MacrosBasis.perG,
          );
          expect(basisOf(const {}), MacrosBasis.perG);
          // Nothing is invented alongside it: a basis says which unit the four
          // numbers are per, and crossing to the other one still needs a
          // density a person typed.
          expect(
            draftFromOffBody(
              body({
                'categories_tags': const ['en:beverages'],
              }),
            )!.densityGPerMl,
            isNull,
          );
        },
      );

      test('a serving with a number and no unit takes the same reading, '
          'rather than defaulting to grams', () {
        final draft = draftFromOffBody({
          'status': 1,
          'product': <String, Object?>{
            'code': '1234567890128',
            'product_name': 'Oat drink',
            'nutrition_data_per': 'serving',
            'serving_quantity': 250,
            'categories_tags': const ['en:beverages'],
            'nutriments': <String, Object?>{
              'energy-kcal_serving': 116.0,
              'proteins_serving': 1.0,
              'carbohydrates_serving': 23.0,
              'fat_serving': 5.0,
            },
          },
        })!;
        expect(draft.servingPanel!.servingAmount, 250);
        expect(draft.servingPanel!.servingBasis, MacrosBasis.perMl);
        expect(draft.macrosBasis, MacrosBasis.perMl);
      });
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
      // US dairy and stock cartons (plan 0025 #2).
      expect(
        parsePackQuantity('1 quart (946 ml)'),
        const DraftPackSize(1, quart),
      );
      expect(parsePackQuantity('2 pints'), const DraftPackSize(2, pint));
      expect(parsePackQuantity('1 qt'), const DraftPackSize(1, quart));
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
