/// The Open Food Facts product read, run **on the device**.
///
/// It is a keyless, free, public GET, so the two reasons `import-recipe` is
/// an edge function — it holds an API key, and it spends money per call —
/// both fail to apply. OFF's rate limit (15 req/min for product reads) is
/// **per IP**, so a shared server address would pool every household onto one
/// budget; on device each phone spends its own. A barcode is an exact-key
/// fetch, not vocabulary matching, so ADR-0004's online-only rule does not
/// reach it.
///
/// Etiquette, from OFF's API docs: send a `User-Agent` of
/// `AppName/Version (contact)` so the traffic is distinguishable from a bot;
/// read operations need no account. We send a `fields=` projection so the
/// response is the handful of keys the mapper reads rather than the ~40 kB
/// full product.
///
/// Everything this file can fail with is [BarcodeLookupFailure] — the three
/// designed states on the board's "When it doesn't work" frame plus the
/// shapeless-answer case, never an exception escaping into the UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ingredient_draft.dart';
import 'off_mapper.dart';

/// Why a lookup produced no draft.
///
/// The board designs three failure states; this taxonomy is finer so the copy
/// can be, mapping onto them as: [notFound] → "isn't in Open Food Facts",
/// [offline] → "can't reach Open Food Facts", and [unavailable], [malformed]
/// and [invalidCode] → the same reachable-failure panel with their own line.
enum BarcodeLookupFailure {
  /// OFF answered, and nobody has added this product. A designed state: the
  /// user is offered a blank draft carrying the code.
  notFound,

  /// The request never got an answer — no connection, or it timed out. The
  /// one action in the app that genuinely cannot be queued.
  offline,

  /// OFF answered with an error status: a 429 (the 15 req/min limit), or a
  /// 5xx. Distinct from [offline] because the phone's connection is fine and
  /// retrying in a moment is the right advice.
  unavailable,

  /// A 200 whose body was not the product shape we asked for. Rare, and kept
  /// separate so it never reads as "this product does not exist".
  malformed,

  /// The text handed in is not a barcode at all. Refused here rather than
  /// spent as a request against a 15/min budget; the typed field gates on the
  /// same rule, so this is a backstop rather than a state a user reaches.
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
/// (`--dart-define=OFF_CONTACT=…`). Left unset the app still identifies
/// itself honestly; no address is invented on the owner's behalf.
const _offContact = String.fromEnvironment('OFF_CONTACT');

/// Reads one product from Open Food Facts by barcode.
///
/// Construct one per surface and [close] it with the surface. Stateless
/// otherwise — a lookup is a single GET.
class OffLookup {
  OffLookup({
    http.Client? client,
    String? userAgent,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       userAgent = userAgent ?? defaultUserAgent;

  /// `AppName/Version (contact)`, the shape OFF's docs ask for. With no
  /// contact configured the app still names itself honestly — inventing an
  /// address would be worse than admitting there isn't one.
  static const defaultUserAgent = _offContact == ''
      ? 'Ansi/0.1.0 (offline-first household recipe app)'
      : 'Ansi/0.1.0 ($_offContact)';

  /// The keys the mapper reads. Sent as `fields=` so OFF returns those
  /// rather than the whole product document.
  ///
  /// `categories_tags` is here for one job: it is the last thing the basis
  /// rule asks (`en:beverages`) when a payload says nothing about whether its
  /// label is per 100 g or per 100 ml.
  static const fields =
      'code,product_name,brands,quantity,serving_size,serving_quantity,'
      'serving_quantity_unit,nutrition_data_per,categories_tags,nutriments';

  final http.Client _client;
  final bool _ownsClient;
  final String userAgent;

  /// Short on purpose: the user is standing in a shop holding a tin, and the
  /// typed field beneath the scanner is a working alternative the moment we
  /// admit defeat.
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
      // `http` wraps most transport problems (DNS, refused, reset) into a
      // ClientException, and the timeout arrives separately — but not
      // everything: a TLS `HandshakeException` escapes IOClient's own catch
      // unwrapped, and the web client has its own vocabulary. To the person
      // holding the phone all of them are one fact — no answer came back —
      // and none of them may reach the UI as a thrown exception.
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
/// Accepts the separators people type and scanners occasionally emit (spaces,
/// hyphens) and the GTIN lengths in circulation: EAN-8/UPC-E's 8, UPC-A's 12,
/// EAN-13, and GTIN-14. Anything else — a letter, a wrong length — is refused
/// here rather than spent as a request against a 15/min budget.
String? normalizeBarcode(String raw) {
  final stripped = raw.trim().replaceAll(RegExp('[ -]'), '');
  if (stripped.isEmpty || !RegExp(r'^\d+$').hasMatch(stripped)) return null;
  return _gtinLengths.contains(stripped.length) ? stripped : null;
}

const _gtinLengths = {8, 12, 13, 14};
