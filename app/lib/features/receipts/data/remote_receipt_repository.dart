/// [ReceiptImportRepository] over the real `import-receipt` edge function.
///
/// It is the recipe import's own client, pointed at a different function: the
/// same auth (the signed-in user's token, whose `household_id` claim scopes
/// matching), the same `text/event-stream` stage narration, the same
/// downscale-before-upload, and the same timeout ladder — which is one ladder
/// and not two, because the pipeline behind both is the same two model calls
/// over the same platform (`import/data/remote_import_repository.dart`
/// documents the arithmetic in full).
///
/// What differs is only what comes back, and the four sentences a failure
/// carries: a person who photographed a receipt should not be told the
/// service could not read a *recipe*.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../import/data/remote_import_repository.dart';
import '../../import/data/sse.dart';
import '../domain/receipt_payload.dart';
import '../domain/receipt_repository.dart';
import '../domain/receipt_stage.dart';

/// What a person is told when the read outlives the whole ladder. It names
/// the one remedy that actually shortens the wait, and says the scan is safe
/// to repeat — nothing is written until Save.
String receiptTimeoutMessage() =>
    'still reading that receipt after ${edgeInvokeTimeout.inMinutes} minutes '
    '— nothing was saved, so it is safe to try again (fewer photos at a time '
    'reads faster)';

String receiptSilenceMessage() =>
    'the receipt reader stopped answering part way through (nothing for '
    '${edgeSilenceTimeout.inSeconds} seconds) — nothing was saved, so it is '
    'safe to try again';

String receiptIncompleteMessage() =>
    'the receipt reader stopped before it finished — nothing was saved, so '
    'it is safe to try again';

String receiptUnreadableMessage() =>
    'the receipt reader returned something this app could not read — nothing '
    'was saved, so it is safe to try again';

/// Consumes the function's stage stream and returns the payload its `result`
/// event carries.
///
/// Separate from the HTTP call for the reason the recipe client's reader is:
/// this is the half with the rules in it, and it takes a plain byte stream so
/// those rules are testable without a socket. [silence] is the SILENCE rung —
/// a deadline on the GAP between events, restarted by every one of them,
/// never on the read's length.
Future<ReceiptPayload> readReceiptStream(
  Stream<List<int>> bytes, {
  void Function(ReceiptProgress)? onProgress,
  Duration silence = edgeSilenceTimeout,
}) {
  final result = Completer<ReceiptPayload>();
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
        () => result.completeError(ImportException(receiptSilenceMessage())),
      ),
    );
  }

  events = decodeSse(bytes).listen(
    (event) {
      // EVERY frame restarts the clock, known or not — which is what lets the
      // server add an event id without shipping a client first.
      waitAgain();
      try {
        switch (event.event) {
          case 'heartbeat':
            break;
          case 'plan':
            onProgress?.call(ReceiptPlanned(_planFrom(event.data)));
          case 'stage':
            final stage = _stageFrom(event.data);
            if (stage != null) onProgress?.call(stage);
          case 'error':
            // The HTTP status is committed before the work runs, so a failure
            // past the first byte arrives here rather than as a 4xx.
            throw ImportException(_errorFrom(event.data));
          case 'result':
            settle(
              () => result.complete(
                ReceiptPayload.fromJson(_objectFrom(event.data)),
              ),
            );
        }
      } on ImportException catch (e) {
        settle(() => result.completeError(e));
      } on Object {
        settle(
          () =>
              result.completeError(ImportException(receiptUnreadableMessage())),
        );
      }
    },
    onError: (Object e, StackTrace stack) =>
        settle(() => result.completeError(e, stack)),
    onDone: () => settle(
      () => result.completeError(ImportException(receiptIncompleteMessage())),
    ),
    cancelOnError: true,
  );
  waitAgain();
  return result.future;
}

List<ReceiptStage> _planFrom(String data) {
  final stages = _objectFrom(data)['stages'];
  if (stages is! List) return const [];
  return [
    for (final id in stages)
      if (id is String)
        if (ReceiptStage.byId(id) case final stage?) stage,
  ];
}

ReceiptStageDone? _stageFrom(String data) {
  final json = _objectFrom(data);
  final stage = json['stage'] is String
      ? ReceiptStage.byId(json['stage']! as String)
      : null;
  if (stage == null) return null;
  final ms = json['elapsed_ms'];
  return ReceiptStageDone(
    stage,
    Duration(milliseconds: ms is num ? ms.round() : 0),
  );
}

String _errorFrom(String data) {
  final error = _objectFrom(data)['error'];
  return error is String && error.isNotEmpty
      ? error
      : 'the receipt reader could not process this receipt';
}

Map<String, Object?> _objectFrom(String data) {
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    throw ImportException(receiptUnreadableMessage());
  }
  if (decoded is! Map) throw ImportException(receiptUnreadableMessage());
  return Map<String, Object?>.from(decoded);
}

class EdgeReceiptRepository implements ReceiptImportRepository {
  const EdgeReceiptRepository({required FunctionsClient functions})
    : _functions = functions;

  final FunctionsClient _functions;

  @override
  Future<ReceiptPayload> readReceipt(
    ReceiptPhotos photos, {
    void Function(ReceiptProgress)? onProgress,
  }) async {
    final body = await _bodyFor(photos);
    try {
      return await _stream(body, onProgress).timeout(edgeInvokeTimeout);
    } on TimeoutException {
      throw ImportException(receiptTimeoutMessage());
    }
  }

  Future<ReceiptPayload> _stream(
    Map<String, Object?> body,
    void Function(ReceiptProgress)? onProgress,
  ) async {
    final FunctionResponse response;
    try {
      response = await _functions.invoke('import-receipt', body: body);
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw ImportException(details['error'] as String);
      }
      final detail = _platformDetail(e.status, details);
      throw ImportException(switch (e.status) {
        504 || 408 =>
          'the receipt reader was still working when it ran out of time '
              '($detail) — nothing was saved, so it is safe to try again',
        0 =>
          'the receipt reader could not be reached ($detail) — nothing was '
              'saved, so it is safe to try again',
        _ => 'the receipt reader could not process this receipt ($detail)',
      });
    }
    final data = response.data;
    if (data is! Stream<List<int>>) {
      throw ImportException(receiptUnreadableMessage());
    }
    return readReceiptStream(data, onProgress: onProgress);
  }

  static String _platformDetail(int status, Object? details) {
    final head = status == 0 ? 'no response' : 'HTTP $status';
    final said = (details?.toString() ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (said.isEmpty) return head;
    return '$head: ${said.length > 200 ? '${said.substring(0, 200)}…' : said}';
  }

  /// The pages, downscaled and base64-encoded — the recipe import's own two
  /// platform facts, for the same two reasons: [XFile] reads both a phone's
  /// path and a browser's blob URL, and `compute` is a background isolate
  /// where there are isolates and a plain call in a tab, where `Isolate.run`
  /// throws.
  Future<Map<String, Object?>> _bodyFor(ReceiptPhotos photos) async {
    final images = <String>[];
    for (final path in photos.imagePaths) {
      final raw = await XFile(path).readAsBytes();
      final small = await compute(downscaleForUpload, raw);
      images.add(base64Encode(small));
    }
    return {'images': images};
  }
}
