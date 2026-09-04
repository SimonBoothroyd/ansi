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

/// How long the client waits for `import-recipe`. A multi-page photo import
/// through the vision tier is genuinely slow (tens of seconds), so this is
/// generous — but unbounded is not an option: `functions.invoke` has no
/// deadline of its own, and a hung request leaves the user on the "Reading the
/// recipe…" spinner with no way back but killing the app.
const _invokeTimeout = Duration(seconds: 60);

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
          .timeout(_invokeTimeout);
    } on TimeoutException {
      throw const ImportException(
        'the import service took too long to answer — check your connection '
        'and try again',
      );
    } on FunctionException catch (e) {
      // The edge fn returns `{error, detail}` on a handled failure (422/500);
      // surface the human-readable `error` when present.
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'the import service could not process this recipe';
      throw ImportException(message);
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
