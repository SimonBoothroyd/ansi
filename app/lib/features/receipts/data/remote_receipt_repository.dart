/// [ReceiptImportRepository] over the `import-receipt` edge function.
///
/// The recipe import's client pointed at a different function: same auth, stage
/// stream, downscale and timeout ladder (see
/// `import/data/remote_import_repository.dart`). Only the payload and the
/// failure sentences differ.
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

/// What a person is told when the read outlives the timeout ladder. Says the
/// scan is safe to repeat: nothing is written until Save.
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
/// event carries. Takes a plain byte stream so it can be tested without a
/// socket. [silence] is a deadline on the gap between events, restarted by each
/// one.
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

  /// The pages, downscaled and base64-encoded. [XFile] reads both a phone's
  /// path and a browser's blob URL, and `compute` is a plain call in a browser,
  /// where `Isolate.run` throws.
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
