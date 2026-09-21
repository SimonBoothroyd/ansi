/// [ImportRepository] backed by the `import-recipe` edge function.
///
/// A URL goes up as `{url}`, photos as base64 `{images: [...]}`. The function
/// answers `text/event-stream`; this file parses the events, reports each stage
/// through `onProgress`, and returns the [ReconciliationPayload] on the last
/// one. `commit` always writes locally, so it is delegated to the SQLite
/// repository.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/commit_payload.dart';
import '../domain/import_repository.dart';
import '../domain/import_stage.dart';
import '../domain/reconciliation_payload.dart';
import 'sse.dart';

/// Longest-edge cap for an uploaded page (px), mirroring the server's
/// `UPLOAD_MAX_EDGE`. Full-resolution pages cost 3–5 MB of base64 each and risk
/// the edge payload limit.
const _uploadMaxEdge = 1568;

/// Re-encode quality for the downscaled JPEG (matches the server's ~85).
const _uploadJpegQuality = 85;

/// How long the client waits for the whole of `import-recipe`.
///
///```text
///client, silence   90s  edgeSilenceTimeout: the longest gap between events
///platform idle    150s  Supabase cuts a response silent this long
///function, gap   ≤ 64s  a model call that never produced (no heartbeats)
///client, total    240s  this constant
///function, total ~195s  worst case, from photos
///platform, whole  400s  Supabase's wall-clock limit per invocation
///```
///
/// The silence rung sits above the widest real gap and below the platform's
/// idle cut-off, so the app gives up first, with a sentence. The total rung
/// exists because `functions.invoke` has no deadline and a dribbling stream
/// never trips the silence rung. The server half is tested in
/// `supabase/functions/_shared/timeouts.test.ts`, this half in
/// `edge_import_failures_test.dart`.
const edgeInvokeTimeout = Duration(seconds: 240);

/// The longest the stage stream may go quiet before the app gives up. See the
/// ladder on [edgeInvokeTimeout].
const edgeSilenceTimeout = Duration(seconds: 90);

/// Downscales one page's [bytes] so its longest edge is about [_uploadMaxEdge],
/// re-encoded as JPEG. Any decode or encode failure, or an image already within
/// the cap, returns the original bytes.
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

/// What a person is told when the request outlives [edgeInvokeTimeout]. It says
/// the import is safe to repeat (nothing is written until Save), and for photos
/// that fewer pages is a shorter read.
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

/// What a person is told when the stream goes quiet: the connection stopped
/// answering, as opposed to the import being slow.
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
/// carries. Takes a plain byte stream so it can be tested without a socket.
///
/// [silence] is a deadline on the gap between events, restarted by each one. It
/// is an explicit [Timer] and a `listen` because `Stream.timeout` under `await
/// for` never fires: the subscription pauses between events and the timeout's
/// clock does not survive the pause.
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
      // Every event restarts the silence clock, unknown ones included, so the
      // server can add event ids without a client release.
      waitAgain();
      try {
        switch (event.event) {
          case 'heartbeat':
            // The model is still producing; `waitAgain()` above did the work.
            break;
          case 'plan':
            onProgress?.call(ImportPlanned(_planFrom(event.data)));
          case 'stage':
            final stage = _stageFrom(event.data);
            if (stage != null) onProgress?.call(stage);
          case 'error':
            // The status is committed before the work runs, so a later failure
            // arrives here rather than as a 4xx/5xx.
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
      // With `text/event-stream` this future completes when the headers are
      // back; the stream's deadline is the silence rung below.
      response = await _functions.invoke('import-recipe', body: body);
    } on FunctionException catch (e) {
      // A handled failure returns `{error}`; surface its message when present.
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw ImportException(details['error'] as String);
      }
      // The function never answered; something in front of it did. A 504 is the
      // gateway timeout; other statuses carry what the platform said (a relay
      // 546 is the worker at its limits, 0 is never reaching the service).
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

  /// The platform's status and message on one short line. Status 0 is the
  /// client never connecting, so no HTTP status is printed for it.
  static String _platformDetail(int status, Object? details) {
    final head = status == 0 ? 'no response' : 'HTTP $status';
    final said = (details?.toString() ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (said.isEmpty) return head;
    return '$head: ${said.length > 200 ? '${said.substring(0, 200)}…' : said}';
  }

  /// Builds the invoke body: a URL passes through; photos are read and
  /// base64-encoded.
  ///
  /// A page is read through [XFile], not `dart:io`, because on the web the
  /// picker's path is a `blob:` URL. The downscale goes through `compute`,
  /// which is an isolate on a phone and a plain call in the browser, where
  /// `Isolate.run` throws.
  Future<Map<String, Object?>> _bodyFor(ImportSource source) async {
    switch (source) {
      case ImportFromUrl(:final url):
        return {'url': url};
      case ImportFromPhotos(:final imagePaths):
        final images = <String>[];
        for (final path in imagePaths) {
          final raw = await XFile(path).readAsBytes();
          final small = await compute(downscaleForUpload, raw);
          images.add(base64Encode(small));
        }
        return {'images': images};
    }
  }

  @override
  Future<String> commit(CommitPayload payload) => _commit.commit(payload);
}
