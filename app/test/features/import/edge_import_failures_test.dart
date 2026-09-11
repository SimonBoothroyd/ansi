/// What the person is told when `import-recipe` does not hand back a payload,
/// and the two deadlines the app holds over the stage stream.
///
/// The import writes nothing until Save, so every one of these is safe to
/// repeat — and the copy has to say which thing went wrong, because the
/// remedies differ: a site that will not serve the page wants the photo door,
/// a model that ran long wants the same button again, and a connection that
/// stopped answering is neither.
library;

import 'dart:async';
import 'dart:convert';

import 'package:ansi/features/import/data/remote_import_repository.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/import_stage.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The commit half is never reached by these tests; the edge repo delegates it.
class _UnusedCommit implements ImportRepository {
  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<String> commit(CommitPayload payload) => throw UnimplementedError();
}

EdgeImportRepository _repo(
  Future<http.Response> Function(http.Request request) respond,
) {
  final functions = FunctionsClient(
    'https://example.test/functions/v1',
    const {},
    httpClient: MockClient(respond),
  );
  addTearDown(functions.dispose);
  return EdgeImportRepository(
    functions: functions,
    commitDelegate: _UnusedCommit(),
  );
}

/// A JSON body the way the edge function answers a failure it caught BEFORE
/// committing to a stream — a malformed body, or the platform in front of it.
Future<http.Response> _json(int status, String error) async => http.Response(
  jsonEncode({'error': error}),
  status,
  headers: const {'content-type': 'application/json'},
);

/// The smallest thing the `result` event can carry and still be a recipe.
const _samplerPayload = <String, Object?>{
  'title': 'Dirty Rice',
  'servings_base': 4,
  'servings_raw': 'Serves 4',
  'yield_raw': null,
  'total_time_seconds': null,
  'cook_time_seconds': null,
  'truncated': false,
  'image_quality': 'ok',
  'parse_warnings': <String>[],
  'groups': <Object?>[
    {
      'name': null,
      'lines': <Object?>[
        {
          'raw': {
            'qty': 1,
            'qty_low': null,
            'qty_high': null,
            'unit': null,
            'unit_mappable': true,
            'ingredient_text': 'long-grain white rice',
            'notes': null,
            'raw_amount': '1 cup',
            'optional': false,
            'confidence': 0.9,
          },
          'band': 'auto',
          'candidates': <Object?>[],
        },
      ],
    },
  ],
  'steps': <Object?>[],
};

/// One SSE frame, the way the function writes it.
String _frame(String event, Object data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

/// [frames] as the bytes a socket would deliver them in.
Stream<List<int>> _bytes(Iterable<String> frames) =>
    Stream.fromIterable(frames.map(utf8.encode));

/// A 200 `text/event-stream` response carrying [frames].
Future<http.StreamedResponse> _stream(
  Iterable<String> frames, {
  Stream<List<int>>? body,
}) async => http.StreamedResponse(
  body ?? Stream.fromIterable(frames.map(utf8.encode)),
  200,
  headers: const {'content-type': 'text/event-stream'},
);

/// An edge repo whose function answers with a live byte stream.
EdgeImportRepository _streaming(
  Future<http.StreamedResponse> Function(http.BaseRequest request) respond,
) {
  final functions = FunctionsClient(
    'https://example.test/functions/v1',
    const {},
    httpClient: MockClient.streaming((request, bodyStream) => respond(request)),
  );
  addTearDown(functions.dispose);
  return EdgeImportRepository(
    functions: functions,
    commitDelegate: _UnusedCommit(),
  );
}

Future<String> _messageFor(EdgeImportRepository repo) async {
  try {
    await repo.startImport(
      const ImportFromUrl('https://example.test/dirty-rice'),
    );
  } on ImportException catch (e) {
    return e.message;
  }
  fail('startImport was expected to fail');
}

/// Supabase's request idle timeout: a function that has sent nothing by then
/// is cut off with a gateway 504 whatever it is still doing. It bounds one GAP.
/// https://supabase.com/docs/guides/functions/limits
const _platformIdleTimeout = Duration(seconds: 150);

/// Supabase's wall-clock limit for one invocation, from the same page. With
/// heartbeats this — not the idle timeout — is the ceiling the whole pipeline
/// has to fit inside.
const _platformWallClock = Duration(seconds: 400);

void main() {
  // The server budgets, mirrored: there is no way to import a Deno constant,
  // and the server half of this arithmetic is
  // `supabase/functions/_shared/timeouts.test.ts`.
  const heartbeat = Duration(seconds: 10); // index.ts HEARTBEAT_INTERVAL_MS
  const modelIdle = Duration(seconds: 20); // http.ts DEFAULT_IDLE_TIMEOUT_MS
  const intakeDeadline = Duration(seconds: 25); // jsonld.ts FETCH_TOTAL_TIMEOUT
  const transcribeDeadline = Duration(seconds: 60); // claude.ts TRANSCRIBE_…
  const sanitiseDeadline = Duration(seconds: 120); // claude.ts SANITIZE_…

  test('the SILENCE rung sits above the widest gap the stream can have, so a '
      'slow model call is never mistaken for a dead connection', () {
    // A model call that is PRODUCING is no longer one of the gaps: it
    // heartbeats while it runs, so the worst it can be quiet for is one
    // interval (too soon to beat) plus one idle window.
    expect(edgeSilenceTimeout, greaterThan(heartbeat + modelIdle));
    // Intake has nothing to say until the page is in hand.
    expect(edgeSilenceTimeout, greaterThan(intakeDeadline));
    // And the honest worst case, which heartbeats cannot cover: a model call
    // that never produces has nothing to beat ABOUT, so three stalled attempts
    // and the ~4s of backoff between them are one gap. The server half of this
    // is `timeouts.test.ts`; both have to hold or the app gives up on a server
    // that is still trying.
    const stalled = Duration(seconds: 20 * 3 + 4);
    expect(edgeSilenceTimeout, greaterThan(stalled));
  });

  test('the SILENCE rung sits below the platform cut-off, so the app is what '
      'gives up — with a sentence — rather than a gateway', () {
    expect(edgeSilenceTimeout, lessThan(_platformIdleTimeout));
  });

  test('the TOTAL rung sits above the pipeline worst case, so a photo import '
      'is never abandoned while the server is still working', () {
    // Photos are two model calls back to back, plus matching and cold start —
    // and the pair now costs MORE than the platform's idle timeout, which is
    // exactly what the heartbeats bought. The rung that has to hold it is this
    // one and the platform's wall clock, not the idle cut-off.
    final photoWorstCase =
        transcribeDeadline + sanitiseDeadline + const Duration(seconds: 15);
    expect(photoWorstCase, greaterThan(_platformIdleTimeout));
    expect(edgeInvokeTimeout, greaterThan(photoWorstCase));
    expect(photoWorstCase, lessThan(_platformWallClock));
    // And above silence, or the total rung could never be the one that fires.
    expect(edgeInvokeTimeout, greaterThan(edgeSilenceTimeout));
  });

  test('the stage stream reports the plan and each stage, then hands over the '
      'payload', () async {
    final repo = _streaming(
      (_) => _stream([
        _frame('plan', {
          'stages': ['received', 'fetched', 'sanitised', 'matched'],
        }),
        _frame('stage', {'stage': 'received', 'elapsed_ms': 40}),
        _frame('stage', {'stage': 'fetched', 'elapsed_ms': 900}),
        // An id from a newer server: reported to nobody rather than crashing.
        _frame('stage', {'stage': 'embedded', 'elapsed_ms': 1000}),
        _frame('stage', {'stage': 'sanitised', 'elapsed_ms': 21000}),
        _frame('stage', {'stage': 'matched', 'elapsed_ms': 21400}),
        _frame('result', _samplerPayload),
      ]),
    );
    final progress = <ImportProgress>[];
    final payload = await repo.startImport(
      const ImportFromUrl('https://example.test/x'),
      onProgress: progress.add,
    );

    expect(payload.title, 'Dirty Rice');
    expect((progress.first as ImportPlanned).stages, [
      ImportStage.received,
      ImportStage.fetched,
      ImportStage.sanitised,
      ImportStage.matched,
    ]);
    final stages = progress.whereType<ImportStageDone>().toList();
    expect(stages.map((s) => s.stage), [
      ImportStage.received,
      ImportStage.fetched,
      ImportStage.sanitised,
      ImportStage.matched,
    ]);
    expect(stages[2].elapsed, const Duration(milliseconds: 21000));
  });

  test('a HEARTBEAT is read and shown to nobody — and an event id this build '
      'has never seen is ignored the same way', () async {
    final progress = <ImportProgress>[];
    final payload = await readImportStream(
      _bytes([
        _frame('plan', {
          'stages': ['received', 'transcribed', 'sanitised', 'matched'],
        }),
        _frame('stage', {'stage': 'received', 'elapsed_ms': 40}),
        _frame('heartbeat', {'elapsed_ms': 10400}),
        _frame('stage', {'stage': 'transcribed', 'elapsed_ms': 12000}),
        _frame('heartbeat', {'elapsed_ms': 22000}),
        _frame('heartbeat', {'elapsed_ms': 32000}),
        // An event id from a server newer than this build: same treatment.
        _frame('weather', {'outlook': 'fine'}),
        _frame('stage', {'stage': 'sanitised', 'elapsed_ms': 49000}),
        _frame('stage', {'stage': 'matched', 'elapsed_ms': 49400}),
        _frame('result', _samplerPayload),
      ]),
      onProgress: progress.add,
    );
    expect(payload.title, 'Dirty Rice');
    // Exactly the four stages and the plan — the heartbeats added no rows.
    expect(progress.whereType<ImportStageDone>(), hasLength(4));
    expect(progress, hasLength(5));
  });

  test('HEARTBEATS feed the silence rung, so a model call that outruns it is '
      'not mistaken for a dead connection', () async {
    // The rung the heartbeats buy, driven at a short budget: the run lasts far
    // longer than the silence deadline and never trips it, because the server
    // keeps saying it is working. The 90s itself is arithmetic, checked above.
    const gap = Duration(milliseconds: 120);
    final frames = StreamController<List<int>>();
    final read = readImportStream(frames.stream, silence: gap);

    frames.add(
      utf8.encode(_frame('stage', {'stage': 'received', 'elapsed_ms': 1})),
    );
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(gap ~/ 2);
      frames.add(utf8.encode(_frame('heartbeat', {'elapsed_ms': i * 60})));
    }
    frames.add(utf8.encode(_frame('result', _samplerPayload)));
    expect((await read).title, 'Dirty Rice');
    await frames.close();
  });

  test('a failure past the first byte is an ERROR EVENT carrying the same '
      'sentence the status path used to carry', () async {
    // The status is committed before the work runs, so the 504 wording has to
    // survive as an event or the person loses the only remedy they had.
    final progress = <ImportProgress>[];
    await expectLater(
      readImportStream(
        _bytes([
          _frame('plan', {
            'stages': ['received', 'fetched'],
          }),
          _frame('stage', {'stage': 'received', 'elapsed_ms': 10}),
          _frame('error', {
            'error':
                'the model took too long to read this recipe — nothing has '
                'been saved, so it is safe to try again',
          }),
        ]),
        onProgress: progress.add,
      ),
      throwsA(
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          allOf(contains('took too long'), contains('safe to try again')),
        ),
      ),
    );
    // The stages that DID land still reached the screen.
    expect(progress.whereType<ImportStageDone>(), hasLength(1));
  });

  test('an error event with nothing in it still says something', () async {
    await expectLater(
      readImportStream(_bytes([_frame('error', <String, Object?>{})])),
      throwsA(isA<ImportException>()),
    );
  });

  test('a stream that ends without a recipe says so, instead of leaving a '
      'blank review screen', () async {
    await expectLater(
      readImportStream(
        _bytes([
          _frame('plan', {
            'stages': ['received'],
          }),
          _frame('stage', {'stage': 'received', 'elapsed_ms': 10}),
        ]),
      ),
      throwsA(
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('stopped before it finished'),
            contains('safe to try again'),
          ),
        ),
      ),
    );
  });

  test('a frame that is not JSON is a broken stream, not an empty recipe', () {
    expect(
      readImportStream(_bytes(['event: result\ndata: <html>\n\n'])),
      throwsA(isA<ImportException>()),
    );
  });

  test('a stream that goes QUIET is given up on at the silence rung — a gap '
      'is what is bounded, never how long the whole import runs', () async {
    // Driven at a short budget rather than the real 90s one: what is under
    // test is that the deadline measures the GAP and that an arriving event
    // restarts it. The 90s itself is arithmetic, checked above.
    const gap = Duration(milliseconds: 120);
    final frames = StreamController<List<int>>();
    final read = readImportStream(frames.stream, silence: gap);

    // Two events, each arriving inside the budget but well past it in total.
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(gap ~/ 2);
      frames.add(
        utf8.encode(_frame('stage', {'stage': 'received', 'elapsed_ms': 1})),
      );
    }
    // …then nothing, ever. The import is not slow; the connection is gone.
    await expectLater(
      read,
      throwsA(
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          allOf(contains('stopped answering'), contains('safe to try again')),
        ),
      ),
    );
    await frames.close();
  });

  // --- Failures the function answers with a plain STATUS ---------------------
  //
  // Everything the pipeline can reject before it commits to a stream, plus
  // whatever the platform in front of it says. These keep their statuses: a
  // request that never started has promised nothing yet.

  test('the function’s own message is what the person reads — a blocked site '
      'stays distinguishable from a slow model', () async {
    final blocked = _repo(
      (_) => _json(
        422,
        'that site blocked the fetch (HTTP 403) — try the photo import instead',
      ),
    );
    expect(await _messageFor(blocked), contains('try the photo import'));

    final slow = _repo(
      (_) => _json(
        504,
        'the model took too long to read this recipe — nothing has been '
        'saved, so it is safe to try again',
      ),
    );
    final message = await _messageFor(slow);
    expect(message, contains('the model took too long'));
    expect(message, contains('safe to try again'));
  });

  test('a gateway 504 with no JSON body still says it ran out of time, not '
      'that the recipe was rejected', () async {
    final gateway = _repo(
      (_) async => http.Response('<html>Gateway Timeout</html>', 504),
    );
    final message = await _messageFor(gateway);
    expect(message, contains('ran out of time'));
    expect(message, contains('safe to try again'));
  });

  test('a relay error says its status and what the platform said — the worker '
      'limit is not the same failure as a rejection', () async {
    // 546 is the edge platform's own "this worker hit its limits", handed
    // back with `x-relay-error` rather than through the function.
    final relay = _repo(
      (_) async => http.Response(
        'WORKER_LIMIT: memory limit reached\n  during the vision tier',
        546,
        headers: const {'x-relay-error': 'true'},
      ),
    );
    final message = await _messageFor(relay);
    expect(message, contains('HTTP 546'));
    expect(message, contains('WORKER_LIMIT: memory limit reached'));
    // One line: a toast cannot show the platform's own line breaks.
    expect(message, isNot(contains('\n')));
  });

  test('a request that never reached the service says so, and carries the '
      'error the socket raised', () async {
    final offline = _repo(
      (_) async => throw http.ClientException('Failed host lookup'),
    );
    final message = await _messageFor(offline);
    // No HTTP status exists for a request that was never answered, so none is
    // invented — and the socket's own words are what tell this apart from a
    // service that answered badly.
    expect(message, contains('could not be reached'));
    expect(message, contains('no response'));
    expect(message, isNot(contains('HTTP')));
    expect(message, contains('Failed host lookup'));
  });

  test('a platform page is trimmed to something a toast can hold', () async {
    final shouty = _repo((_) async => http.Response('x' * 900, 500));
    final message = await _messageFor(shouty);
    expect(message, contains('HTTP 500'));
    expect(message, contains('…'));
    expect(message.length, lessThan(320));
  });

  test('a request that never even answers its headers is cut off by the total '
      'deadline', () {
    final hung = _repo((_) => Completer<http.Response>().future);
    // What this pins is that `startImport` HAS a deadline: `functions.invoke`
    // carries none of its own, so without one a hung request waits forever.
    // Nothing has streamed, so the silence rung has nothing to measure.
    fakeAsync((async) {
      Object? raised;
      unawaited(
        hung
            .startImport(const ImportFromUrl('https://x/y'))
            .then((_) {}, onError: (Object e) => raised = e),
      );
      async.elapse(edgeInvokeTimeout - const Duration(seconds: 1));
      expect(raised, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(
        raised,
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          contains('still reading that page'),
        ),
      );
    });
  });
}
