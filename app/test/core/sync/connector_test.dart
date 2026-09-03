/// Tests for the PowerSync <-> Supabase connector.
///
/// Covers the payload mapping (jsonb columns decoded from their local TEXT
/// form, PUT always clears `deleted_at`), the full [AnsiConnector.uploadData]
/// drain against a real PowerSync queue with a fake PostgREST layer, the
/// fatal-vs-transient error split (fatal drops are logged, never silent), and
/// that [AnsiConnector.fetchCredentials] declines to sync when signed out.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/sync/connector.dart';
import 'package:ansi/core/sync/dropped_write.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_db.dart';

/// Collects what the connector reports it discarded.
class _RecordingSink implements DroppedWriteSink {
  final writes = <DroppedWrite>[];

  @override
  void dropped(DroppedWrite write) => writes.add(write);
}

class _MockSupabase extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

PostgrestException _err(String code) =>
    PostgrestException(message: 'x', code: code);

/// One PostgREST write as the connector issued it.
class _RecordedCall {
  _RecordedCall(this.table, this.method, this.payload);

  final String table;
  final String method; // 'upsert' | 'update'
  final Map<String, dynamic> payload;
  final Map<String, Object> filters = {};
}

/// A recording stand-in for the PostgREST layer. Set [error] to make every
/// awaited request fail with that exception (after being recorded).
class _FakePostgrest {
  final calls = <_RecordedCall>[];
  PostgrestException? error;
}

class _FakeFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  _FakeFilterBuilder(this._backend, this._call);

  final _FakePostgrest _backend;
  final _RecordedCall _call;

  @override
  PostgrestFilterBuilder<dynamic> eq(String column, Object value) {
    _call.filters[column] = value;
    return this;
  }

  // `await builder` routes through Future.then — resolve or fail here.
  @override
  Future<U> then<U>(
    FutureOr<U> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    final error = _backend.error;
    final result = error == null
        ? Future<dynamic>.value()
        : Future<dynamic>.error(error);
    return result.then(onValue, onError: onError);
  }
}

class _FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _FakeQueryBuilder(this._backend, this._table);

  final _FakePostgrest _backend;
  final String _table;

  @override
  PostgrestFilterBuilder<dynamic> upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    final call = _RecordedCall(
      _table,
      'upsert',
      (values as Map).cast<String, dynamic>(),
    );
    _backend.calls.add(call);
    return _FakeFilterBuilder(_backend, call);
  }

  @override
  PostgrestFilterBuilder<dynamic> update(Map<dynamic, dynamic> values) {
    final call = _RecordedCall(
      _table,
      'update',
      values.cast<String, dynamic>(),
    );
    _backend.calls.add(call);
    return _FakeFilterBuilder(_backend, call);
  }
}

class _FakeSupabase extends Fake implements SupabaseClient {
  _FakeSupabase(this.backend);

  final _FakePostgrest backend;

  @override
  SupabaseQueryBuilder from(String table) => _FakeQueryBuilder(backend, table);
}

CrudEntry _put(String table, String id, Map<String, dynamic> data) =>
    CrudEntry(1, UpdateType.put, table, id, 1, data);

CrudEntry _patch(String table, String id, Map<String, dynamic> data) =>
    CrudEntry(1, UpdateType.patch, table, id, 1, data);

void main() {
  group('isFatalPostgrestError', () {
    test('integrity / access / data errors are fatal (drop the write)', () {
      expect(isFatalPostgrestError(_err('23505')), isTrue); // unique violation
      expect(isFatalPostgrestError(_err('23503')), isTrue); // FK violation
      expect(isFatalPostgrestError(_err('42501')), isTrue); // RLS denied
      expect(isFatalPostgrestError(_err('22P02')), isTrue); // bad input syntax
    });

    test('other / missing codes are treated as retryable', () {
      expect(isFatalPostgrestError(_err('08006')), isFalse); // connection
      expect(isFatalPostgrestError(_err('PGRST301')), isFalse);
      expect(isFatalPostgrestError(_err('')), isFalse);
    });
  });

  group('putPayload', () {
    test('decodes jsonb columns from local TEXT to native JSON', () {
      // The server's jsonb columns (supabase/migrations 0002/0003/0005):
      // sending the local TEXT as-is stores a jsonb *string* upstream, which
      // crashes every reader when the row syncs back down.
      final recipe = putPayload(
        _put('recipe', 'r1', {'title': 'Curry', 'steps': '["one","two"]'}),
      );
      expect(recipe['steps'], ['one', 'two']);
      expect(recipe['title'], 'Curry');
      expect(recipe['id'], 'r1');

      final plan = putPayload(_put('plan_entry', 'p1', {'eaters': '["m1"]'}));
      expect(plan['eaters'], ['m1']);

      final ingredient = putPayload(
        _put('ingredient', 'i1', {
          'macros': '{"kcal":100}',
          'allowed_units': '["g","kg"]',
        }),
      );
      expect(ingredient['macros'], {'kcal': 100});
      // 0012's column was missing from the map until 2026-09-03: every
      // app-created ingredient uploaded its admission list as a jsonb STRING,
      // which `allowed_units ? unit` on the server never matched (pgTAP over
      // smoke-created rows caught it; 0028 repairs the stored rows).
      expect(ingredient['allowed_units'], ['g', 'kg']);
    });

    test('leaves absent / null jsonb columns alone', () {
      final absent = putPayload(_put('ingredient', 'i1', {'status': 'stub'}));
      expect(absent.containsKey('macros'), isFalse);

      final explicitNull = putPayload(
        _put('ingredient', 'i1', {'macros': null}),
      );
      expect(explicitNull['macros'], isNull);
    });

    test('passes non-jsonb tables through untouched', () {
      final payload = putPayload(_put('book', 'b1', {'name': '["not json]'}));
      // A column that merely looks like JSON on a table with no jsonb columns
      // must stay a string.
      expect(payload['name'], '["not json]');
    });

    test('always includes deleted_at: null (a PUT row is live locally)', () {
      // PUT opData omits null columns, and a local DELETE + re-INSERT of the
      // same id reaches the server as tombstone-then-upsert — without the
      // explicit null the tombstone would survive the upsert.
      final payload = putPayload(_put('recipe', 'r1', {'title': 'x'}));
      expect(payload.containsKey('deleted_at'), isTrue);
      expect(payload['deleted_at'], isNull);

      // An explicit local value still wins over the default.
      final tombstoned = putPayload(
        _put('recipe', 'r1', {'deleted_at': '2026-01-01T00:00:00Z'}),
      );
      expect(tombstoned['deleted_at'], '2026-01-01T00:00:00Z');
    });
  });

  group('patchPayload', () {
    test('decodes jsonb columns and adds nothing else', () {
      final payload = patchPayload(
        _patch('recipe', 'r1', {'steps': '["only"]'}),
      );
      expect(payload['steps'], ['only']);
      expect(payload.containsKey('deleted_at'), isFalse);
      expect(payload.containsKey('id'), isFalse);
    });
  });

  group('uploadData', () {
    late PowerSyncDatabase db;
    late Directory dir;
    late _FakePostgrest backend;
    late AnsiConnector connector;
    late _RecordingSink dropped;

    setUp(() async {
      (db, dir) = await openTestDb();
      backend = _FakePostgrest();
      dropped = _RecordingSink();
      connector = AnsiConnector(_FakeSupabase(backend), onDropped: dropped);
    });

    tearDown(() => closeTestDb(db, dir));

    final now = DateTime.utc(2026).toIso8601String();

    Future<void> insertRecipe() => db.execute(
      'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['r1', 'h', 'Curry', 2, '["step one","step two"]', now, now],
    );

    test('PUT upserts with decoded jsonb and deleted_at: null', () async {
      await insertRecipe();
      await connector.uploadData(db);

      final call = backend.calls.single;
      expect(call.table, 'recipe');
      expect(call.method, 'upsert');
      expect(call.payload['id'], 'r1');
      expect(call.payload['steps'], ['step one', 'step two']);
      expect(call.payload.containsKey('deleted_at'), isTrue);
      expect(call.payload['deleted_at'], isNull);

      // The transaction was acknowledged: nothing left to upload.
      expect(await queuedCrudOps(db), isEmpty);
    });

    test('PATCH updates with decoded jsonb, filtered on id', () async {
      await insertRecipe();
      await drainCrudQueue(db);

      await db.execute('UPDATE recipe SET steps = ? WHERE id = ?', [
        '["only"]',
        'r1',
      ]);
      await connector.uploadData(db);

      final call = backend.calls.single;
      expect(call.table, 'recipe');
      expect(call.method, 'update');
      expect(call.payload['steps'], ['only']);
      expect(call.filters, {'id': 'r1'});
      expect(await queuedCrudOps(db), isEmpty);
    });

    test('DELETE maps to a soft-delete update', () async {
      await insertRecipe();
      await drainCrudQueue(db);

      await db.execute('DELETE FROM recipe WHERE id = ?', ['r1']);
      await connector.uploadData(db);

      final call = backend.calls.single;
      expect(call.table, 'recipe');
      expect(call.method, 'update');
      expect(call.payload.keys, ['deleted_at']);
      expect(call.payload['deleted_at'], isA<String>());
      expect(call.filters, {'id': 'r1'});
      expect(await queuedCrudOps(db), isEmpty);
    });

    test('fatal PostgREST error drops the transaction and logs it', () async {
      await insertRecipe();
      backend.error = _err('23505');

      final logs = <String?>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message);
      addTearDown(() => debugPrint = previous);

      await connector.uploadData(db);

      // Dropped: the queue is drained even though the write failed…
      expect(await queuedCrudOps(db), isEmpty);
      // …but the permanent local/server divergence is named, not silent.
      final log = logs.single;
      expect(log, contains('recipe'));
      expect(log, contains('put'));
      expect(log, contains('r1'));
      expect(log, contains('23505'));

      // And — the point of this front — it is reported to something a person
      // can be shown, not only to a console nobody is attached to.
      final report = dropped.writes.single;
      expect(report.table, 'recipe');
      expect(report.op, 'put');
      expect(report.rowId, 'r1');
      expect(report.code, '23505');
    });

    test('transient PostgREST error rethrows and keeps the queue', () async {
      await insertRecipe();
      backend.error = _err('08006');

      await expectLater(
        connector.uploadData(db),
        throwsA(isA<PostgrestException>()),
      );
      expect(await queuedCrudOps(db), isNotEmpty);
    });
  });

  group('fetchCredentials', () {
    late _MockSupabase supabase;
    late _MockAuth auth;

    setUp(() {
      supabase = _MockSupabase();
      auth = _MockAuth();
      when(() => supabase.auth).thenReturn(auth);
    });

    test('returns null when there is no session (signed out)', () async {
      when(() => auth.currentSession).thenReturn(null);
      final creds = await AnsiConnector(supabase).fetchCredentials();
      expect(creds, isNull);
    });
  });
}
