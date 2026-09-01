/// The Open Food Facts response scenario 5 serves instead of the network.
///
/// **Two mirrors, one fact.** This is a verbatim copy of the committed unit
/// fixture `test/features/ingredients/barcode/fixtures/nutella_per_100g.json`
/// (a real OFF answer for barcode 3017620422003, captured 2026-08-31), carried
/// here as a Dart const because the integration test runs ON the device: a
/// host path is not readable there, and bundling a test fixture as a Flutter
/// asset would ship it inside the app. The same reason `canned_payload.dart`
/// is Dart source rather than a JSON asset.
///
/// `test/features/ingredients/barcode/off_fixture_pin_test.dart` parses both
/// and fails if they ever diverge — the habit the normalize vectors and
/// `defaultAllowedUnitSet` already keep.
///
/// Serving this through a `MockClient` (rather than faking `OffLookup` itself)
/// keeps the real mapper, the real status/HTTP classification and the real
/// barcode normalizer in the path. Only the socket is fake.
library;

/// The barcode the fixture answers for. Matches the committed OFF fixture.
const offFixtureBarcode = '3017620422003';

/// `GET /api/v2/product/3017620422003.json` — status 1, a per-100 g panel.
const offNutellaFixtureJson = '''
{
  "code": "3017620422003",
  "product": {
    "brands": "Nutella, Ferrero, Yum yum",
    "code": "3017620422003",
    "nutriments": {
      "added-sugars": 52.13,
      "added-sugars_100g": 52.13,
      "added-sugars_unit": "g",
      "added-sugars_value": 52.13,
      "carbohydrates": 57.5,
      "carbohydrates_100g": 57.5,
      "carbohydrates_unit": "g",
      "carbohydrates_value": 57.5,
      "energy": 2252,
      "energy-kcal": 539,
      "energy-kcal_100g": 539,
      "energy-kcal_unit": "kcal",
      "energy-kcal_value": 539,
      "energy-kj": 2252,
      "energy-kj_100g": 2252,
      "energy-kj_unit": "kJ",
      "energy-kj_value": 2252,
      "energy_100g": 2252,
      "energy_unit": "kJ",
      "energy_value": 2252,
      "fat": 30.9,
      "fat_100g": 30.9,
      "fat_unit": "g",
      "fat_value": 30.9,
      "fruits-vegetables-legumes-estimate-from-ingredients_100g": 0,
      "fruits-vegetables-nuts-estimate-from-ingredients_100g": 13,
      "nova-group": 4,
      "nova-group_100g": 4,
      "nova-group_serving": 4,
      "nova-group_unit": "",
      "nova-group_value": 4,
      "proteins": 6.3,
      "proteins_100g": 6.3,
      "proteins_unit": "g",
      "proteins_value": 6.3,
      "salt": 0.107,
      "salt_100g": 0.107,
      "salt_unit": "g",
      "salt_value": 0.107,
      "saturated-fat": 10.6,
      "saturated-fat_100g": 10.6,
      "saturated-fat_unit": "g",
      "saturated-fat_value": 10.6,
      "sodium": 0.0428,
      "sodium_100g": 0.0428,
      "sodium_modifier": "~",
      "sodium_unit": "g",
      "sodium_value": 0.0428,
      "sugars": 56.3,
      "sugars_100g": 56.3,
      "sugars_unit": "g",
      "sugars_value": 56.3
    },
    "nutrition_data": "on",
    "nutrition_data_per": "100g",
    "nutrition_data_prepared_per": "100g",
    "product_name": "Nutella",
    "quantity": ""
  },
  "status": 1,
  "status_verbose": "product found"
}
''';
