/// The Open Food Facts product read, run on the device.
///
/// It is a keyless, free, public GET, and OFF's rate limit (15 req/min) is per
/// IP, so each phone spends its own budget. A barcode is an exact-key fetch, so
/// ADR-0004's online-only matching rule does not apply. Per OFF's API docs we
/// send a `User-Agent` of `AppName/Version (contact)` and a `fields=`
/// projection. Every failure is a [BarcodeLookupFailure]; no exception escapes
/// into the UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ingredient_draft.dart';
import 'off_mapper.dart';

/// Why a lookup produced no draft. [notFound] and [offline] have their own
/// panels; [unavailable], [malformed] and [invalidCode] share the
/// reachable-failure panel, each with its own line.
enum BarcodeLookupFailure {
  /// OFF answered, and nobody has added this product. A designed state: the
  /// user is offered a blank draft carrying the code.
  notFound,

  /// The request never got an answer — no connection, or it timed out. The
  /// one action in the app that genuinely cannot be queued.
  offline,

  /// OFF answered with an error status: a 429 (rate limit) or a 5xx. Distinct
  /// from [offline] because retrying in a moment is the right advice.
  unavailable,

  /// A 200 whose body was not the product shape we asked for. Rare, and kept
  /// separate so it never reads as "this product does not exist".
  malformed,

  /// The text is not a barcode. Refused here rather than spent against the rate
  /// limit; the typed field gates on the same rule.
  invalidCode,
}

/// The outcome of one lookup.
sealed class BarcodeLookupResult {
  const BarcodeLookupResult();
}

final class BarcodeFound extends BarcodeLookupResult {
  const BarcodeFound(this.draft);

  final IngredientDraft draft;
}

final class BarcodeLookupFailed extends BarcodeLookupResult {
  const BarcodeLookupFailed(this.reason, {required this.barcode});

  final BarcodeLookupFailure reason;

  /// The code that was looked up — the not-found copy names it, and the
  /// blank-draft exit carries it.
  final String barcode;
}

/// A contact for OFF's etiquette line, set at build time
/// (`--dart-define=OFF_CONTACT=…`). Unset, the app still names itself and no
/// address is invented.
const _offContact = String.fromEnvironment('OFF_CONTACT');

/// Reads one product from Open Food Facts by barcode. Construct one per surface
/// and [close] it with the surface.
class OffLookup {
  OffLookup({
    http.Client? client,
    String? userAgent,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       userAgent = userAgent ?? defaultUserAgent;

  /// `AppName/Version (contact)`, the shape OFF's docs ask for; the contact is
  /// omitted when none is configured.
  static const defaultUserAgent = _offContact == ''
      ? 'Ansi/0.1.0 (offline-first household recipe app)'
      : 'Ansi/0.1.0 ($_offContact)';

  /// The keys the mapper reads, sent as `fields=`. `categories_tags` is there
  /// for the basis rule's last resort (`en:beverages`).
  static const fields =
      'code,product_name,brands,quantity,serving_size,serving_quantity,'
      'serving_quantity_unit,nutrition_data_per,categories_tags,nutriments';

  final http.Client _client;
  final bool _ownsClient;
  final String userAgent;

  /// Short on purpose: the typed field under the scanner is a working
  /// alternative.
  final Duration timeout;

  Uri urlFor(String barcode) => Uri.https(
    'world.openfoodfacts.org',
    '/api/v2/product/$barcode.json',
    {'fields': fields},
  );

  Future<BarcodeLookupResult> lookup(String barcode) async {
    final code = normalizeBarcode(barcode);
    if (code == null) {
      return BarcodeLookupFailed(
        BarcodeLookupFailure.invalidCode,
        barcode: barcode.trim(),
      );
    }
    final http.Response response;
    try {
      response = await _client
          .get(urlFor(code), headers: {'User-Agent': userAgent})
          .timeout(timeout);
      // `http` wraps most transport problems into a ClientException, but a TLS
      // `HandshakeException` escapes unwrapped and the web client differs. All
      // of them mean no answer came back, and none may reach the UI as a throw.
    } on Exception {
      return BarcodeLookupFailed(BarcodeLookupFailure.offline, barcode: code);
    }
    // OFF answers an unknown code with a 404 whose body is `{"status": 0}`.
    if (response.statusCode == 404) {
      return BarcodeLookupFailed(BarcodeLookupFailure.notFound, barcode: code);
    }
    if (response.statusCode != 200) {
      return BarcodeLookupFailed(
        BarcodeLookupFailure.unavailable,
        barcode: code,
      );
    }
    return classifyBody(response.body, barcode: code);
  }

  /// The 200-body half of [lookup], separated so the fixture tests exercise
  /// the same not-found / malformed classification the network path uses.
  BarcodeLookupResult classifyBody(String body, {required String barcode}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return BarcodeLookupFailed(
        BarcodeLookupFailure.malformed,
        barcode: barcode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      return BarcodeLookupFailed(
        BarcodeLookupFailure.malformed,
        barcode: barcode,
      );
    }
    // OFF's own "no such product" marker, which it also serves with a 200 on
    // some paths — the status field is the authority, not the HTTP code.
    if (decoded['status'] != 1) {
      return BarcodeLookupFailed(
        BarcodeLookupFailure.notFound,
        barcode: barcode,
      );
    }
    final draft = draftFromOffBody(decoded);
    if (draft == null) {
      return BarcodeLookupFailed(
        BarcodeLookupFailure.malformed,
        barcode: barcode,
      );
    }
    return BarcodeFound(draft);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// A scanned or typed barcode reduced to the digits OFF keys on, or null when
/// it cannot be one.
///
/// Accepts spaces and hyphens, and the GTIN lengths in circulation: 8, 12, 13
/// and 14. Ten digits are taken as a UPC-A's printed middle (`0 99482 47826 1`
/// reads as `99482 47826`): the number-system digit is assumed `0` and the
/// check digit computed. Eleven digits are a UPC-A without its check digit and
/// are completed the same way. A wrong assumption costs one not-found.
String? normalizeBarcode(String raw) {
  final stripped = raw.trim().replaceAll(RegExp('[ -]'), '');
  if (stripped.isEmpty || !RegExp(r'^\d+$').hasMatch(stripped)) return null;
  return switch (stripped.length) {
    10 => _withCheckDigit('0$stripped'),
    11 => _withCheckDigit(stripped),
    _ => _gtinLengths.contains(stripped.length) ? stripped : null,
  };
}

const _gtinLengths = {8, 12, 13, 14};

/// [body] plus its GTIN check digit: weight 3 on every other digit counting
/// from the right, sum, and the digit that lifts the sum to a multiple of 10.
String _withCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final digit = body.codeUnitAt(body.length - 1 - i) - 0x30;
    sum += i.isEven ? digit * 3 : digit;
  }
  return '$body${(10 - sum % 10) % 10}';
}
