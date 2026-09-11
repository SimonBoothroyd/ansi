/// The `text/event-stream` parser the import stream is read through.
///
/// The point of these is the SPLITTING: bytes arrive in whatever chunks the
/// socket hands over, and an event must surface the moment its frame is
/// complete — not when the response ends, which for an import is a minute
/// later.
library;

import 'dart:async';
import 'dart:convert';

import 'package:ansi/features/import/data/sse.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> _chunks(List<String> parts) =>
    Stream.fromIterable(parts.map(utf8.encode));

Future<List<SseEvent>> _events(List<String> parts) =>
    decodeSse(_chunks(parts)).toList();

void main() {
  test(
    'frames split on the blank line, keeping their event name and data',
    () async {
      // Two frames in ONE chunk: the split is the blank line, not the packet.
      const twoFrames =
          'event: plan\ndata: {"stages":["received"]}\n\n'
          'event: stage\ndata: {"stage":"received","elapsed_ms":12}\n\n';
      final events = await _events([twoFrames]);
      expect(events.map((e) => e.event), ['plan', 'stage']);
      expect(events[0].data, '{"stages":["received"]}');
      expect(jsonDecode(events[1].data), {
        'stage': 'received',
        'elapsed_ms': 12,
      });
    },
  );

  test('a frame split across chunks — mid-field, mid-line — still arrives '
      'whole', () async {
    final events = await _events([
      'event: sta',
      'ge\ndata: {"stage":"sani',
      'tised","elapsed_ms":4100}',
      '\n\n',
    ]);
    expect(events.length, 1);
    expect(events.single.event, 'stage');
    final decoded = jsonDecode(events.single.data) as Map<String, Object?>;
    expect(decoded['stage'], 'sanitised');
  });

  test('an event surfaces as soon as its frame closes, not when the response '
      'ends', () async {
    // The whole reason for streaming: a stage that landed at five seconds must
    // not wait for a payload that arrives a minute later.
    final seen = <String>[];
    final controller = StreamController<List<int>>();
    final done = decodeSse(controller.stream).forEach((e) => seen.add(e.event));

    controller.add(utf8.encode('event: stage\ndata: {}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['stage'], reason: 'the first frame should be out already');

    controller.add(utf8.encode('event: result\ndata: {}\n\n'));
    await controller.close();
    await done;
    expect(seen, ['stage', 'result']);
  });

  test('a comment line is a heartbeat, never an event of its own', () async {
    final events = await _events([
      ': keep-alive\n\nevent: stage\ndata: {}\n\n: another\n\n',
    ]);
    expect(events.map((e) => e.event), ['stage']);
  });

  test('a last frame with no trailing blank line is not dropped', () async {
    final events = await _events([
      'event: result\ndata: {"title":"Dirty Rice"}',
    ]);
    expect(events.single.event, 'result');
    final decoded = jsonDecode(events.single.data) as Map<String, Object?>;
    expect(decoded['title'], 'Dirty Rice');
  });

  test('multiple data lines rejoin with newlines, and one leading space after '
      'the colon is the separator, not content', () async {
    final events = await _events(['event: note\ndata: one\ndata:  two\n\n']);
    expect(events.single.data, 'one\n two');
  });

  test(
    r'a frame with no event field is a `message`, and \r\n line ends work',
    () async {
      final events = await _events(['data: {"x":1}\r\n\r\n']);
      expect(events.single.event, 'message');
      expect(events.single.data, '{"x":1}');
    },
  );

  test('fields this client has no use for are ignored rather than mistaken '
      'for data', () async {
    final events = await _events([
      'id: 7\nretry: 3000\nevent: stage\ndata: {}\n\n',
    ]);
    expect(events.single.event, 'stage');
    expect(events.single.data, '{}');
  });
}
