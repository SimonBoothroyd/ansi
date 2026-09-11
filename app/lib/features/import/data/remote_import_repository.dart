/// [ImportRepository] backed by the REAL `import-recipe` edge function (the
/// integration tail).
///
/// `startImport` calls `supabase.functions.invoke('import-recipe', …)` — a URL
/// goes up as `{url}`, picked photos are read from disk and base64-encoded as
/// `{images: [...]}`. The function answers `text/event-stream` and narrates its
/// stages as they land (import spec §4.7), so `functions_client` hands back a
/// live byte stream rather than a decoded body: this file parses the events,
/// reports each finished stage through `onProgress`, and returns the
/// [ReconciliationPayload] carried by the last one — which feeds the existing
/// reconciliation UI unchanged. The function is auth-scoped: `supabase_flutter`
/// attaches the signed-in user's access token, whose `household_id` claim
/// scopes matching to the household.
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
import '../domain/import_stage.dart';
import '../domain/reconciliation_payload.dart';
import 'sse.dart';

/// Longest-edge cap for an uploaded page (px) — mirrors the server adapter's
/// `UPLOAD_MAX_EDGE`. A recipe photo gains nothing above this and costs 3–5 MB
/// of base64 per page, which risks the edge payload limit on a multi-page
/// import. The server downscale stays as a safety net; the phone shouldn't send
/// full-res.
const _uploadMaxEdge = 1568;

/// Re-encode quality for the downscaled JPEG (matches the server's ~85).
const _uploadJpegQuality = 85;

/// How long the client waits for the whole of `import-recipe`.
///
/// **The timeout ladder, re-derived for the stage stream.** The function now
/// answers `text/event-stream` and sends an event as each stage lands, which
/// moves what every rung is measuring:
///
/// ```text
/// client, silence   90s  edgeSilenceTimeout — the longest GAP this will sit
///                        through before deciding the server is gone
/// platform idle    150s  Supabase's cut-off for a response that has sent
///                        NOTHING since the last byte. It bounds one GAP, not
///                        the call: the stream keeps the connection warm
///                        through the stages either side of it.
/// function, longest gap:
///   ≤ 25s intake (jsonld.ts FETCH_TOTAL_TIMEOUT_MS), or
///   ≤ 60s one model call (adapters/http.ts DEFAULT_DEADLINE_MS)
///
/// client, total    180s  this constant
/// function, total        the worst case the pipeline can reach:
///   from a link   ≤ 25s intake + ≤ 60s model + match       ⇒ ~90s
///   from photos   ≤ 60s transcribe + ≤ 60s extract + match ⇒ ~125s
/// ```
///
/// Two rungs, because there are two ways for this to go wrong and only one of
/// them is a duration. **Silence** is the honest signal that the connection is
/// dead: bytes arriving prove the server is alive, so an import must not be
/// abandoned merely for taking a while — but a gap wider than any stage can
/// account for is not slowness. It sits above the widest real gap (60s) with
/// room for a cold start, and below the platform's own 150s so the app is the
/// one that gives up, with a sentence, rather than a gateway cutting in.
/// **Total** still exists because a stream that dribbles forever would never
/// trip the silence rung, and because `functions.invoke` has no deadline of
/// its own — a hung request would leave the user on the spinner with no way
/// back but killing the app. It stays above the function's worst case (~125s).
///
/// The server half of this arithmetic is a test
/// (`supabase/functions/_shared/timeouts.test.ts`); this half is
/// `edge_import_failures_test.dart`.
const edgeInvokeTimeout = Duration(seconds: 180);

/// The longest the stage stream may go quiet before the app gives up. See the
/// ladder on [edgeInvokeTimeout].
const edgeSilenceTimeout = Duration(seconds: 90);

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

/// What a person is told when the stream goes quiet for longer than any stage
/// can account for. A different failure from the one above and it deserves
/// different words: the import was not slow, the connection stopped answering.
String importSilenceMessage() =>
    'the import service stopped answering part way through '
    '(nothing for ${edgeSilenceTimeout.inSeconds} seconds) — nothing was '
    'saved, so it is safe to try again';

/// What a person is told when the stream ends tidily without ever handing over
/// a recipe. It should not happen; saying so plainly beats a blank screen.
String importIncompleteMessage() =>
    'the import service stopped before it finished reading this recipe — '
    'nothing was saved, so it is safe to try again';

/// A user-facing import failure raised by the edge-backed repository (the
/// controller wraps it into an `ImportFailed` message).
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Consumes the function's stage stream: reports each stage through
/// [onProgress] and returns the [ReconciliationPayload] the `result` event
/// carries.
///
/// Separate from the HTTP call on purpose — this is the half with the rules in
/// it (which events mean what, what a silent stream means, what an `error`
/// event costs), and it takes a plain byte stream so those rules can be tested
/// without a socket.
///
/// [silence] is the SILENCE rung of the ladder on [edgeInvokeTimeout]: a
/// deadline on the GAP between events, restarted by every one of them, never on
/// the import's length.
///
/// It is an explicit [Timer] and a `listen`, rather than `Stream.timeout` and
/// an `await for`, because those two do not compose: `await for` pauses its
/// subscription between events and the timeout's clock does not survive the
/// pause, so the deadline silently never fires. A stream deadline that cannot
/// fire is worse than none — it reads as protection that is not there.
Future<ReconciliationPayload> readImportStream(
  Stream<List<int>> bytes, {
  void Function(ImportProgress)? onProgress,
  Duration silence = edgeSilenceTimeout,
}) {
  final result = Completer<ReconciliationPayload>();
  late final StreamSubscription<SseEvent> events;
  Timer? idle;

  void settle(void Function() complete) {
    if (result.isCompleted) return;
    idle?.cancel();
    complete();
    unawaited(events.cancel());
  }

  void waitAgain() {
    idle?.cancel();
    idle = Timer(
      silence,
      () => settle(
        () => result.completeError(ImportException(importSilenceMessage())),
      ),
    );
  }

  events = decodeSse(bytes).listen(
    (event) {
      waitAgain();
      try {
        switch (event.event) {
          case 'plan':
            onProgress?.call(ImportPlanned(_planFrom(event.data)));
          case 'stage':
            final stage = _stageFrom(event.data);
            if (stage != null) onProgress?.call(stage);
          case 'error':
            // The status is committed before the work runs, so a failure past
            // the first byte arrives here rather than as a 4xx/5xx. The
            // sentence is the function's own, as it was on the JSON path.
            throw ImportException(_errorFrom(event.data));
          case 'result':
            final payload = ReconciliationPayload.fromJson(
              _objectFrom(event.data),
            );
            settle(() => result.complete(payload));
        }
      } on ImportException catch (e) {
        settle(() => result.completeError(e));
      } on Object {
        // A frame shaped like a payload but not one. The person gets a
        // sentence rather than a spinner that never stops.
        settle(
          () => result.completeError(
            const ImportException(
              'the import service returned an unexpected response',
            ),
          ),
        );
      }
    },
    onError: (Object e, StackTrace stack) =>
        settle(() => result.completeError(e, stack)),
    // Ended tidily, with no recipe and no reason.
    onDone: () => settle(
      () => result.completeError(ImportException(importIncompleteMessage())),
    ),
    cancelOnError: true,
  );
  waitAgain();
  return result.future;
}

/// The stage list from a `plan` event. Ids this build does not know are dropped
/// rather than drawn as a blank row.
List<ImportStage> _planFrom(String data) {
  final stages = _objectFrom(data)['stages'];
  if (stages is! List) return const [];
  return [
    for (final id in stages)
      if (id is String && ImportStage.byId(id) != null) ImportStage.byId(id)!,
  ];
}

/// A `stage` event, or null when it names a stage this build does not know.
ImportStageDone? _stageFrom(String data) {
  final json = _objectFrom(data);
  final stage = json['stage'] is String
      ? ImportStage.byId(json['stage']! as String)
      : null;
  if (stage == null) return null;
  final ms = json['elapsed_ms'];
  return ImportStageDone(
    stage,
    Duration(milliseconds: ms is num ? ms.round() : 0),
  );
}

/// The sentence an `error` event carries, or a stand-in if it carries none.
String _errorFrom(String data) {
  final error = _objectFrom(data)['error'];
  return error is String && error.isNotEmpty
      ? error
      : 'the import service could not process this recipe';
}

/// One event's JSON object. A frame that is not one is a broken stream, and the
/// person is told that rather than shown an empty recipe.
Map<String, Object?> _objectFrom(String data) {
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    throw const ImportException(
      'the import service returned an unexpected response',
    );
  }
  if (decoded is! Map) {
    throw const ImportException(
      'the import service returned an unexpected response',
    );
  }
  return Map<String, Object?>.from(decoded);
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
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final body = await _bodyFor(source);
    try {
      return await _stream(body, onProgress).timeout(edgeInvokeTimeout);
    } on TimeoutException {
      // Past the TOTAL rung: the stream was still arriving, it was just never
      // going to finish inside a wait anybody should be asked to sit through.
      throw ImportException(importTimeoutMessage(source));
    }
  }

  /// Invokes the function and consumes its stage stream, reporting each stage
  /// and returning the payload the `result` event carries.
  Future<ReconciliationPayload> _stream(
    Map<String, Object?> body,
    void Function(ImportProgress)? onProgress,
  ) async {
    final FunctionResponse response;
    try {
      // The stream's own deadline is the SILENCE rung below, not this: with
      // `text/event-stream` this future completes as soon as the headers are
      // back, which is long before the work is done.
      response = await _functions.invoke('import-recipe', body: body);
    } on FunctionException catch (e) {
      // The edge fn returns `{error}` on a handled failure (4xx/5xx); surface
      // the human-readable message when present. It is what tells a person
      // whether the SITE would not give us the page (a block, a redirect loop,
      // a 404) or the MODEL ran long — two failures with different remedies.
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw ImportException(details['error'] as String);
      }
      // No message of its own: the function never answered, and something in
      // front of it did. A 504 here is the platform's gateway timeout, not a
      // rejection; every other status carries what the platform said, because
      // the remedies differ and a sentence without the status cannot tell
      // them apart — a relay 546 is the worker hitting its limits (send fewer
      // pages), a status 0 is this phone never reaching the service at all.
      final detail = _platformDetail(e.status, details);
      throw ImportException(switch (e.status) {
        504 || 408 =>
          'the import service was still working when it ran out of time '
              '($detail) — nothing was saved, so it is safe to try again',
        // Nothing was sent anywhere, so "could not process this recipe"
        // would name the wrong thing as broken.
        0 =>
          'the import service could not be reached ($detail) — nothing was '
              'saved, so it is safe to try again',
        _ => 'the import service could not process this recipe ($detail)',
      });
    }
    final data = response.data;
    if (data is! Stream<List<int>>) {
      throw const ImportException(
        'the import service returned an unexpected response',
      );
    }
    return readImportStream(data, onProgress: onProgress);
  }

  /// What the app knows about a failure the function did not explain: the
  /// platform's status and whatever it said with it, on one line and short
  /// enough to survive a toast. Status 0 is the client's own "never got
  /// there", so there is no HTTP status to print for it.
  static String _platformDetail(int status, Object? details) {
    final head = status == 0 ? 'no response' : 'HTTP $status';
    final said = (details?.toString() ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (said.isEmpty) return head;
    return '$head: ${said.length > 200 ? '${said.substring(0, 200)}…' : said}';
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
