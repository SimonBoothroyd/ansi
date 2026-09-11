/// What the person is told when `import-recipe` does not hand back a payload.
///
/// The import writes nothing until Save, so every one of these is safe to
/// repeat — and the copy has to say which thing went wrong, because the
/// remedies differ: a site that will not serve the page wants the photo door,
/// and a model that ran long wants the same button again.
library;

import 'dart:async';
import 'dart:convert';

import 'package:ansi/features/import/data/remote_import_repository.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The commit half is never reached by these tests; the edge repo delegates it.
class _UnusedCommit implements ImportRepository {
  @override
  Future<ReconciliationPayload> startImport(ImportSource source) =>
      throw UnimplementedError();

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

/// A JSON body the way the edge function answers a handled failure.
Future<http.Response> _json(int status, String error) async => http.Response(
  jsonEncode({'error': error}),
  status,
  headers: const {'content-type': 'application/json'},
);

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
/// is cut off with a gateway 504 whatever it is still doing.
/// https://supabase.com/docs/guides/functions/limits
const _platformIdleTimeout = Duration(seconds: 150);

void main() {
  test('the client deadline sits ABOVE the platform cut-off, so the client '
      'never abandons a request the server would still answer', () {
    expect(edgeInvokeTimeout, greaterThan(_platformIdleTimeout));
  });

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

  test('past the whole ladder the copy says what was being waited on, that '
      'nothing was saved, and — for photos — what reads faster', () {
    final photos = importTimeoutMessage(
      const ImportFromPhotos(['/tmp/page-1.jpg']),
    );
    expect(photos, contains('still reading those photos'));
    expect(photos, contains('nothing was saved'));
    expect(photos, contains('safe to try again'));
    expect(photos, contains('fewer pages'));

    final link = importTimeoutMessage(const ImportFromUrl('https://x/y'));
    expect(link, contains('still reading that page'));
    expect(link, contains('nothing was saved'));
    expect(link, contains('safe to try again'));
  });

  test('a hung request is cut off by the client deadline', () {
    final hung = _repo((_) => Completer<http.Response>().future);
    // What this pins is that `startImport` HAS a deadline: `functions.invoke`
    // carries none of its own, so without one a hung request waits forever.
    fakeAsync((async) {
      Object? raised;
      unawaited(
        hung
            .startImport(const ImportFromUrl('https://x/y'))
            .then((_) {}, onError: (Object e) => raised = e),
      );
      async.elapse(const Duration(seconds: 179));
      expect(raised, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(raised, isA<ImportException>());
    });
  });
}
