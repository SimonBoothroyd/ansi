/// [ImportRepository] backed by the REAL `import-recipe` edge function (the
/// integration tail).
///
/// `startImport` calls `supabase.functions.invoke('import-recipe', …)` — a URL
/// goes up as `{url}`, picked photos are read from disk and base64-encoded as
/// `{images: [...]}` — and parses the returned [ReconciliationPayload] into its
/// Dart mirror, which feeds the existing reconciliation UI unchanged. The
/// function is auth-scoped: `supabase_flutter` attaches the signed-in user's
/// access token, whose `household_id` claim scopes matching to the household.
///
/// `commit` is unchanged — it always writes locally through PowerSync — so this
/// class delegates it to the SQLite repository. Only the extract→match step
/// moved server-side. With Supabase unconfigured there is nothing to extract
/// with, and `importRepositoryProvider` fails the import loudly rather than
/// substituting the canned payload.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/commit_payload.dart';
import '../domain/import_repository.dart';
import '../domain/reconciliation_payload.dart';

/// Longest-edge cap for an uploaded page (px) — mirrors the server adapter's
/// `UPLOAD_MAX_EDGE`. A recipe photo gains nothing above this and costs 3–5 MB
/// of base64 per page, which risks the edge payload limit on a multi-page
/// import. The server downscale stays as a safety net; the phone shouldn't send
/// full-res.
const _uploadMaxEdge = 1568;

/// Re-encode quality for the downscaled JPEG (matches the server's ~85).
const _uploadJpegQuality = 85;

/// How long the client waits for `import-recipe`.
///
/// **The timeout ladder.** Every rung must be strictly larger than everything
/// beneath it, or the layer above gives up on work the layer below would have
/// finished — and a client that abandons a request the server completes bills
/// the model call and shows a failure for it.
///
/// ```text
/// client   180s  this constant
/// platform 150s  Supabase's request idle timeout — a function that has sent
///                nothing by then is cut off with a gateway 504
/// function       the worst case the pipeline can actually reach:
///   from a link   ≤ 25s intake (jsonld.ts FETCH_TOTAL_TIMEOUT_MS)
///               + ≤ 60s one model call (adapters/http.ts DEFAULT_DEADLINE_MS)
///               +   match, a handful of Postgres round-trips      ⇒ ~90s
///   from photos   ≤ 60s transcribe + ≤ 60s extract + match        ⇒ ~125s
/// ```
///
/// So this sits ABOVE the platform's own cut-off, not below the function's
/// worst case. A client deadline under either number abandons a request the
/// server is still working on — and a photo import, two model calls back to
/// back, reaches those numbers routinely — which surfaces as a network-shaped
/// failure for a request that was merely slow.
///
/// Unbounded is still not an option: `functions.invoke` has no deadline of its
/// own, and a hung request would leave the user on the spinner with no way back
/// but killing the app.
const edgeInvokeTimeout = Duration(seconds: 180);

/// Downscales one page's [bytes] so its longest edge is ≈ [_uploadMaxEdge],
/// re-encoded as JPEG. Runs off the UI isolate (decoding a full-res phone photo
/// in pure Dart is heavy). GRACEFUL: any decode/encode failure — or an image
/// already within the cap — returns the original bytes rather than throwing, so
/// one odd photo can never fail the import.
Uint8List downscaleForUpload(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (longest <= _uploadMaxEdge) return bytes;
    final scale = _uploadMaxEdge / longest;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
    );
    return img.encodeJpg(resized, quality: _uploadJpegQuality);
  } on Object {
    return bytes;
  }
}

/// What a person is told when the request outlives the whole timeout ladder.
///
/// It names what was being waited on and says the import is safe to repeat:
/// nothing is written until Save at review, so a second attempt cannot
/// duplicate or half-write a recipe. The photo wording carries the one remedy
/// that actually shortens the wait — a photo import is two model calls over
/// however many pages were sent, so fewer pages is a shorter read.
String importTimeoutMessage(ImportSource source) {
  final minutes = edgeInvokeTimeout.inMinutes;
  return switch (source) {
    ImportFromPhotos() =>
      'still reading those photos after $minutes minutes — nothing was saved, '
          'so it is safe to try again (fewer pages at a time reads faster)',
    ImportFromUrl() =>
      'still reading that page after $minutes minutes — nothing was saved, so '
          'it is safe to try again',
  };
}

/// A user-facing import failure raised by the edge-backed repository (the
/// controller wraps it into an `ImportFailed` message).
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EdgeImportRepository implements ImportRepository {
  const EdgeImportRepository({
    required FunctionsClient functions,
    required ImportRepository commitDelegate,
  }) : _functions = functions,
       _commit = commitDelegate;

  final FunctionsClient _functions;

  /// The commit path is always local (PowerSync); delegate to the SQLite repo.
  final ImportRepository _commit;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async {
    final body = await _bodyFor(source);
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke('import-recipe', body: body)
          .timeout(edgeInvokeTimeout);
    } on TimeoutException {
      // Past the whole ladder — the request outlived even the platform's own
      // cut-off.
      throw ImportException(importTimeoutMessage(source));
    } on FunctionException catch (e) {
      // The edge fn returns `{error}` on a handled failure (4xx/5xx); surface
      // the human-readable message when present. It is what tells a person
      // whether the SITE would not give us the page (a block, a redirect loop,
      // a 404) or the MODEL ran long — two failures with different remedies.
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw ImportException(details['error'] as String);
      }
      // No JSON body: the function never answered and something in front of it
      // did. A 504 here is the platform's gateway timeout, not a rejection.
      throw ImportException(
        e.status == 504 || e.status == 408
            ? 'the import service was still working when it ran out of time — '
                  'nothing was saved, so it is safe to try again'
            : 'the import service could not process this recipe',
      );
    }
    final data = response.data;
    if (data is! Map) {
      throw const ImportException(
        'the import service returned an unexpected response',
      );
    }
    return ReconciliationPayload.fromJson(Map<String, Object?>.from(data));
  }

  /// Builds the invoke body: a URL passes straight through; photos are read
  /// from their on-device paths and base64-encoded (the edge fn decodes them
  /// back to bytes for the vision tier).
  Future<Map<String, Object?>> _bodyFor(ImportSource source) async {
    switch (source) {
      case ImportFromUrl(:final url):
        return {'url': url};
      case ImportFromPhotos(:final imagePaths):
        final images = <String>[];
        for (final path in imagePaths) {
          final raw = await File(path).readAsBytes();
          // Downscale off the UI isolate before encoding — a full-res page can
          // take seconds to decode in pure Dart.
          final small = await Isolate.run(() => downscaleForUpload(raw));
          images.add(base64Encode(small));
        }
        return {'images': images};
    }
  }

  @override
  Future<String> commit(CommitPayload payload) => _commit.commit(payload);
}
