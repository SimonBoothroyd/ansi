/// The `read-label` edge function, as the ingredient form's reader.
///
/// One photo up, one JSON reading back — no stream, no stages, because a label
/// is one image and one model call. The photo goes through the same
/// [downscaleForUpload] the two import doors use, so one cap answers the same
/// way at every door.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../import/data/remote_import_repository.dart';
import '../domain/label_read_repository.dart';
import '../domain/label_reading.dart';

/// How long the app waits for the whole read.
///
/// The server's own budget for its one model call is `LABEL_DEADLINE_MS`
/// (60 s, `_shared/adapters/claude_label.ts`), and this door sends no
/// heartbeat: it has to answer inside the platform's 150 s idle cut-off or the
/// gateway ends it. This rung sits above the server's worst case and below
/// that cut-off, so the app gives up with a sentence rather than on a gateway
/// error.
const labelReadTimeout = Duration(seconds: 120);

/// What a person is told when the read outlives [labelReadTimeout].
String labelTimeoutMessage() =>
    'the label reader was still working when it ran out of time — nothing '
    'was saved, so it is safe to try again';

/// What a person is told when the answer is not a reading.
String labelUnreadableMessage() =>
    'the label reader sent something we could not read — nothing was saved, '
    'so it is safe to try again';

class EdgeLabelRepository implements LabelReadRepository {
  const EdgeLabelRepository({required FunctionsClient functions})
    : _functions = functions;

  final FunctionsClient _functions;

  @override
  Future<LabelReading> readLabel(String photoPath) async {
    // `XFile` reads both a phone's path and a browser's blob URL, and
    // `compute` is a plain call in a browser, where `Isolate.run` throws.
    final raw = await XFile(photoPath).readAsBytes();
    final small = await compute(downscaleForUpload, raw);
    final body = <String, Object?>{
      'images': [base64Encode(small)],
    };
    try {
      return await _read(body).timeout(labelReadTimeout);
    } on TimeoutException {
      throw ImportException(labelTimeoutMessage());
    }
  }

  Future<LabelReading> _read(Map<String, Object?> body) async {
    final FunctionResponse response;
    try {
      response = await _functions.invoke('read-label', body: body);
    } on FunctionException catch (e) {
      final details = e.details;
      // The server's own sentence wins: it knows what went wrong with THIS
      // photo, and it was written for a person.
      if (details is Map && details['error'] is String) {
        throw ImportException(details['error'] as String);
      }
      final detail = _platformDetail(e.status, details);
      throw ImportException(switch (e.status) {
        504 || 408 =>
          'the label reader was still working when it ran out of time '
              '($detail) — nothing was saved, so it is safe to try again',
        0 =>
          'the label reader could not be reached ($detail) — nothing was '
              'saved, so it is safe to try again',
        _ => 'the label reader could not read this photo ($detail)',
      });
    }
    final data = response.data;
    if (data is! Map) throw ImportException(labelUnreadableMessage());
    return LabelReading.fromJson(Map<String, Object?>.from(data));
  }

  static String _platformDetail(int status, Object? details) {
    final head = status == 0 ? 'no response' : 'HTTP $status';
    final said = (details?.toString() ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (said.isEmpty) return head;
    return '$head: ${said.length > 200 ? '${said.substring(0, 200)}…' : said}';
  }
}
