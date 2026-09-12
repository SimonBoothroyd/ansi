/// The on-device Open Food Facts read (plan 0020 D2), over a stubbed
/// [http.Client] — no network in CI, ever. What is asserted here is the
/// request we make (etiquette + projection) and the classification of every
/// answer OFF can give.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/features/ingredients/barcode/ingredient_draft.dart';
import 'package:ansi/features/ingredients/barcode/off_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A found product, trimmed to the keys the mapper reads.
const _found = '''
{"code":"3017620422003","status":1,"product":{"code":"3017620422003",
"product_name":"Nutella","brands":"Nutella, Ferrero","nutrition_data_per":
"100g","nutriments":{"energy-kcal_100g":539,"proteins_100g":6.3,
"carbohydrates_100g":57.5,"fat_100g":30.9}}}
''';

OffLookup _lookupThat(
  Future<http.Response> Function(http.Request request) handler,
) => OffLookup(client: MockClient(handler));

void main() {
  group('the request', () {
    test(
      'carries the etiquette User-Agent and the fields projection',
      () async {
        late http.Request seen;
        final lookup = _lookupThat((request) async {
          seen = request;
          return http.Response(_found, 200);
        });

        await lookup.lookup('3017620422003');

        // OFF's docs ask for `AppName/Version (contact)` so the traffic is
        // distinguishable from a bot. No key, no account — that is the whole
        // reason this call is allowed to live on the device.
        expect(seen.headers['User-Agent'], startsWith('Ansi/0.1.0 ('));
        expect(seen.headers.containsKey('Authorization'), isFalse);
        expect(seen.url.host, 'world.openfoodfacts.org');
        expect(seen.url.path, '/api/v2/product/3017620422003.json');
        final fields = seen.url.queryParameters['fields']!.split(',');
        expect(
          fields,
          containsAll(<String>[
            'product_name',
            'brands',
            'quantity',
            'nutrition_data_per',
            'nutriments',
          ]),
        );
      },
    );

    test('normalizes the code before spending a request on it', () async {
      late Uri seen;
      final lookup = _lookupThat((request) async {
        seen = request.url;
        return http.Response(_found, 200);
      });

      await lookup.lookup(' 3017-6204-22003 ');

      expect(seen.path, '/api/v2/product/3017620422003.json');
    });

    test('refuses a non-barcode without any request at all', () async {
      var called = false;
      final lookup = _lookupThat((_) async {
        called = true;
        return http.Response(_found, 200);
      });

      final result = await lookup.lookup('not-a-barcode');

      expect(called, isFalse, reason: 'the 15/min budget is not spent on it');
      expect(
        result,
        isA<BarcodeLookupFailed>().having(
          (f) => f.reason,
          'reason',
          BarcodeLookupFailure.invalidCode,
        ),
      );
    });
  });

  group('classifying the answer', () {
    Future<BarcodeLookupResult> answer(
      FutureOr<http.Response> Function() respond,
    ) => _lookupThat((_) async => respond()).lookup('3017620422003');

    test('200 with a product → a draft that never completes a row', () async {
      final result = await answer(() => http.Response(_found, 200));

      final draft = (result as BarcodeFound).draft;
      expect(draft.suggestedName, 'Nutella');
      expect(draft.brand, 'Nutella');
      expect(draft.sourceValue, 'off:3017620422003');
      expect(draft.macros, isNotNull);
      expect(draft.densityGPerMl, isNull);
    });

    test('404 → notFound (the code OFF answers an unknown product)', () async {
      final result = await answer(
        () => http.Response('{"code":"x","status":0}', 404),
      );

      expect(
        (result as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.notFound,
      );
      // The copy names the code, so the barcode has to survive the failure.
      expect(result.barcode, '3017620422003');
    });

    test('a 200 carrying status 0 is still notFound — the body is the '
        'authority, not the HTTP code', () async {
      final result = await answer(() => http.Response('{"status":0}', 200));

      expect(
        (result as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.notFound,
      );
    });

    test('no connection → offline, not a crash', () async {
      // What the real IOClient throws for an unreachable host: a
      // ClientException wrapping the socket error.
      final result = await answer(
        () => throw http.ClientException('Network is unreachable'),
      );

      expect(
        (result as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.offline,
      );
    });

    test('a TLS failure is offline too — it escapes IOClient unwrapped, and '
        'must not reach the UI as a thrown exception', () async {
      final result = await answer(
        () => throw const HandshakeException('certificate verify failed'),
      );

      expect(
        (result as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.offline,
      );
    });

    test('a hang past the timeout → offline', () async {
      final lookup = OffLookup(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );

      final result = await lookup.lookup('3017620422003');

      expect(
        (result as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.offline,
      );
    });

    test('429 → unavailable, kept apart from offline: the phone is fine and '
        'waiting a moment is the right advice', () async {
      final result = await answer(() => http.Response('slow down', 429));

      expect(
        (result as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.unavailable,
      );
    });

    test('a 200 of nonsense → malformed, never "no such product"', () async {
      expect(
        ((await answer(
          () => http.Response('<html>oops</html>', 200),
        )) as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.malformed,
      );
      expect(
        ((await answer(
          () => http.Response('{"status":1}', 200),
        )) as BarcodeLookupFailed).reason,
        BarcodeLookupFailure.malformed,
      );
    });
  });

  group('normalizeBarcode', () {
    test('accepts the GTIN lengths in circulation, with separators', () {
      expect(normalizeBarcode('3017620422003'), '3017620422003');
      expect(normalizeBarcode('  20724696 '), '20724696');
      expect(normalizeBarcode('0-70847-81116-9'), '070847811169');
      expect(normalizeBarcode('00 70847 81116 9'), '0070847811169');
    });

    test(
      'a UPC-A typed as the pack prints it is completed to twelve digits',
      () {
        // The owner's Plant-Based Mozzarella: `0 99482 47826 1` on the pack,
        // typed as the ten middle digits. Number system 0, check digit 1.
        expect(normalizeBarcode('99482 47826'), '099482478261');
        // Eleven digits: the number system typed, the check digit not.
        expect(normalizeBarcode('09948247826'), '099482478261');
        // The check digit is computed, not assumed: the code above, typed
        // without its last digit, gets the same 9 back.
        expect(normalizeBarcode('0 70847 81116'), '070847811169');
      },
    );

    test('refuses anything else', () {
      expect(normalizeBarcode('12345'), isNull);
      expect(normalizeBarcode('123456789012345'), isNull);
      expect(normalizeBarcode('301762042200X'), isNull);
      expect(normalizeBarcode(''), isNull);
    });
  });

  test('a draft with no barcode reports itself manual, not off:null', () {
    const draft = IngredientDraft(
      suggestedName: 'x',
      source: DraftSource.barcode,
    );

    expect(draft.sourceValue, 'manual');
    expect(const IngredientDraft.blank(barcode: '1').attribution, isNull);
  });
}
