/// Reading a `text/event-stream` body.
///
/// `import-recipe` narrates its stages as Server-Sent Events (import spec
/// §4.7), so the phone has to decode them as they arrive — the whole point is
/// that the first stage lands long before the last one. This is the parser, not
/// the protocol: what the events MEAN lives in `remote_import_repository.dart`.
///
/// It implements the parts of the SSE grammar the function actually sends —
/// `event:` and `data:` fields, one frame per blank line, `:` comment lines
/// ignored (that is what a heartbeat is) — and deliberately not `id:`/`retry:`
/// or reconnection, because a reconnect would re-run a billed model call.
library;

import 'dart:convert';

/// One decoded frame. [data] is the joined `data:` lines, still text.
class SseEvent {
  const SseEvent(this.event, this.data);

  /// The `event:` field, or `message` when the frame did not name one.
  final String event;

  /// The frame's payload, with multi-line `data:` fields rejoined by newlines.
  final String data;

  @override
  String toString() => 'SseEvent($event, ${data.length} chars)';
}

/// Decodes [bytes] into events as they arrive.
///
/// A frame is emitted on its terminating blank line, and — because a server
/// that closes cleanly after its last frame is well within its rights — any
/// trailing frame is emitted when the stream ends.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  var data = <String>[];
  var started = false;

  final lines = bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  await for (final line in lines) {
    if (line.isEmpty) {
      if (started) {
        yield SseEvent(event, data.join('\n'));
        event = 'message';
        data = <String>[];
        started = false;
      }
      continue;
    }
    // A comment line — the shape a keep-alive takes. Never a frame of its own.
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
        started = true;
      case 'data':
        data.add(value);
        started = true;
      default:
      // `id`, `retry`, and anything else this client has no use for.
    }
  }
  if (started) yield SseEvent(event, data.join('\n'));
}
