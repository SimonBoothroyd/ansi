/// Two phones make the row for one natural key offline, under two ids: the
/// second upload is written onto the first's row instead of being dropped,
/// and both phones converge on that one row ([naturalKeysByTable]).
///
/// The server is a second real database behind [UploadTarget], holding the
/// server's unique keys (every row, live or not, as the migrations do) and
/// the foreign key to `week_plan`. "The next sync" is PowerSync's own: once
/// the queue is empty, the core drops every local row no bucket holds
/// (`sync_local` past the write checkpoint), and the server's rows come down.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/sync/connector.dart';
import 'package:ansi/core/sync/dropped_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../helpers/test_db.dart';

class _RecordingSink implements DroppedWriteSink {
  final writes = <DroppedWrite>[];

  @override
  void dropped(DroppedWrite write) => writes.add(write);
}

/// The server, as far as these tables go: an upsert by id under the unique
/// keys and the `week_plan` foreign key the migrations declare.
class _Server implements UploadTarget {
  _Server(this.db);

  final PowerSyncDatabase db;

  static const _synced = [
    'week_plan',
    'plan_entry',
    'week_recipe_line_override',
  ];

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    required bool ignoreDuplicates,
  }) async {
    final id = row['id'] as String;
    final there = await db.getOptional('SELECT id FROM $table WHERE id = ?', [
      id,
    ]);
    if (there != null && ignoreDuplicates) return;
    await _check(table, row, id);
    await _write(db, table, id, row);
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, dynamic> values,
  ) async {
    final there = await db.getOptional('SELECT * FROM $table WHERE id = ?', [
      id,
    ]);
    if (there == null) return; // PostgREST: no row matched, no error
    await _check(table, {...there, ...values}, id);
    await _write(db, table, id, values);
  }

  @override
  Future<String?> idWhere(String table, Map<String, Object> key) async {
    final row = await db.getOptional(
      'SELECT id FROM $table WHERE '
      '${key.keys.map((c) => '$c = ?').join(' AND ')} LIMIT 1',
      key.values.toList(),
    );
    return row?['id'] as String?;
  }

  Future<void> _check(String table, Map<String, dynamic> row, String id) async {
    final parent = row['week_plan_id'];
    if (parent is String &&
        await db.getOptional('SELECT id FROM week_plan WHERE id = ?', [
              parent,
            ]) ==
            null) {
      throw const PostgrestException(message: 'fk', code: '23503');
    }
    final key = naturalKeysByTable[table];
    if (key == null || key.any((c) => row[c] == null)) return;
    final holder = await idWhere(table, {
      for (final c in key) c: row[c] as Object,
    });
    if (holder != null && holder != id) {
      throw PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
    }
  }

  /// Every row this server holds, by table.
  Future<Map<String, List<Map<String, Object?>>>> rows() async => {
    for (final t in _synced)
      t: [
        for (final r in await db.getAll('SELECT * FROM $t')) {...r},
      ],
  };
}

/// Writes [data] as row [id] of [table]: an UPDATE when it is there, else an
/// INSERT (local tables are views: never an UPSERT).
Future<void> _write(
  PowerSyncDatabase db,
  String table,
  String id,
  Map<String, dynamic> data,
) async {
  final columns = [
    for (final k in data.keys)
      if (k != 'id') k,
  ];
  Object? sql(Object? v) => v is List || v is Map ? jsonEncode(v) : v;
  final there = await db.getOptional('SELECT id FROM $table WHERE id = ?', [
    id,
  ]);
  if (there != null) {
    if (columns.isEmpty) return;
    await db.execute(
      'UPDATE $table SET ${columns.map((c) => '$c = ?').join(', ')} '
      'WHERE id = ?',
      [for (final c in columns) sql(data[c]), id],
    );
  } else {
    await db.execute(
      'INSERT INTO $table (id, ${columns.join(', ')}) '
      'VALUES (?, ${List.filled(columns.length, '?').join(', ')})',
      [id, for (final c in columns) sql(data[c])],
    );
  }
}

/// Uploads [phone]'s whole queue through [connector].
Future<void> _uploadAll(
  PowerSyncDatabase phone,
  AnsiConnector connector,
) async {
  while ((await queuedCrudOps(phone)).isNotEmpty) {
    await connector.uploadData(phone);
  }
}

/// The next sync on [phone], its queue empty: PowerSync drops every local row
/// no bucket holds, then the server's rows come down.
Future<void> _nextSync(PowerSyncDatabase phone, _Server server) async {
  expect(await queuedCrudOps(phone), isEmpty);
  await phone.execute(
    r"UPDATE ps_buckets SET target_op = 0 WHERE name = '$local'",
  );
  await phone.execute(
    "INSERT INTO powersync_operations(op, data) VALUES ('sync_local', '')",
  );
  for (final MapEntry(key: table, value: rows)
      in (await server.rows()).entries) {
    for (final r in rows) {
      await _write(phone, table, r['id']! as String, r);
    }
  }
  await drainCrudQueue(phone);
}

const _now = '2026-11-14T09:00:00Z';
const _later = '2026-11-14T09:05:00Z';

Future<void> _week(PowerSyncDatabase db, String id) => db.execute(
  'INSERT INTO week_plan (id, household_id, week_start_date, created_at, '
  "updated_at) VALUES (?, 'h', '2026-11-09', ?, ?)",
  [id, _now, _now],
);

Future<void> _override(
  PowerSyncDatabase db,
  String id, {
  required String week,
  required String action,
  double? quantity,
  String at = _now,
  String? line = 'l1',
}) => db.execute(
  'INSERT INTO week_recipe_line_override (id, household_id, week_plan_id, '
  'recipe_id, recipe_line_item_id, action, quantity, created_at, updated_at) '
  "VALUES (?, 'h', ?, 'r1', ?, ?, ?, ?, ?)",
  [id, week, line, action, quantity, at, at],
);

Future<void> _meal(PowerSyncDatabase db, String id, String week) => db.execute(
  'INSERT INTO plan_entry (id, household_id, week_plan_id, day_of_week, '
  "meal_slot, recipe_id, eaters, sort_order, created_at, updated_at) VALUES "
  "(?, 'h', ?, 5, 'Breakfast', 'r1', '[]', 0, ?, ?)",
  [id, week, _now, _now],
);

void main() {
  late PowerSyncDatabase serverDb, phoneA, phoneB;
  late Directory dirS, dirA, dirB;
  late _Server server;
  late _RecordingSink droppedA, droppedB;
  late AnsiConnector connectorA, connectorB;

  setUp(() async {
    (serverDb, dirS) = await openTestDb();
    (phoneA, dirA) = await openTestDb();
    (phoneB, dirB) = await openTestDb();
    server = _Server(serverDb);
    droppedA = _RecordingSink();
    droppedB = _RecordingSink();
    connectorA = AnsiConnector.withTarget(server, onDropped: droppedA);
    connectorB = AnsiConnector.withTarget(server, onDropped: droppedB);
  });

  tearDown(() async {
    await closeTestDb(serverDb, dirS);
    await closeTestDb(phoneA, dirA);
    await closeTestDb(phoneB, dirB);
  });

  /// The week, on the server and synced to both phones.
  Future<void> sharedWeek() async {
    await _week(serverDb, 'w');
    await _nextSync(phoneA, server);
    await _nextSync(phoneB, server);
  }

  Future<List<Map<String, Object?>>> overrides(PowerSyncDatabase db) async => [
    for (final r in await db.getAll(
      'SELECT id, action, quantity, deleted_at FROM week_recipe_line_override '
      'ORDER BY id',
    ))
      {...r},
  ];

  test('two phones override one line offline: the second is written onto '
      'the first’s row, and both converge on it', () async {
    await sharedWeek();
    // Offline, each phone makes the override under its own id.
    await _override(phoneA, 'oa', week: 'w', action: 'exclude');
    await _override(
      phoneB,
      'ob',
      week: 'w',
      action: 'replace',
      quantity: 3,
      at: _later,
    );

    await _uploadAll(phoneA, connectorA);
    await _uploadAll(phoneB, connectorB);

    // Nothing dropped: the last writer won on the row that holds the key.
    expect(droppedB.writes, isEmpty);
    final expected = [
      {'id': 'oa', 'action': 'replace', 'quantity': 3.0, 'deleted_at': null},
    ];
    expect(await overrides(serverDb), expected);

    // The next sync: B's orphan goes, A's row comes down; both read the same.
    await _nextSync(phoneA, server);
    await _nextSync(phoneB, server);
    expect(await overrides(phoneA), expected);
    expect(await overrides(phoneB), expected);
  });

  test('a write queued behind the merge goes to the winner too', () async {
    await sharedWeek();
    await _override(phoneA, 'oa', week: 'w', action: 'exclude');
    await _override(phoneB, 'ob', week: 'w', action: 'replace', quantity: 3);
    // Phone B edits its row again before it has uploaded.
    await phoneB.execute(
      'UPDATE week_recipe_line_override SET quantity = 4 WHERE id = ?',
      ['ob'],
    );
    await _uploadAll(phoneA, connectorA);
    await _uploadAll(phoneB, connectorB);
    expect((await overrides(serverDb)).single, {
      'id': 'oa',
      'action': 'replace',
      'quantity': 4.0,
      'deleted_at': null,
    });
  });

  test('an override taken back and made again under a new id revives the '
      'row the server keeps', () async {
    await sharedWeek();
    await _override(phoneA, 'o1', week: 'w', action: 'exclude');
    await phoneA.execute(
      'UPDATE week_recipe_line_override SET deleted_at = ? WHERE id = ?',
      [_now, 'o1'],
    );
    await _uploadAll(phoneA, connectorA);
    await _nextSync(phoneA, server);
    // The editor writes a fresh id for a line with no live row.
    await _override(phoneA, 'o2', week: 'w', action: 'exclude', at: _later);
    await _uploadAll(phoneA, connectorA);

    expect(droppedA.writes, isEmpty);
    expect(await overrides(serverDb), [
      {'id': 'o1', 'action': 'exclude', 'quantity': null, 'deleted_at': null},
    ]);
  });

  test(
    'an added line (no recipe line) never merges: NULLs are distinct',
    () async {
      await sharedWeek();
      await _override(phoneA, 'aa', week: 'w', action: 'add', line: null);
      await _override(phoneB, 'ab', week: 'w', action: 'add', line: null);
      await _uploadAll(phoneA, connectorA);
      await _uploadAll(phoneB, connectorB);
      expect(
        [for (final r in await overrides(serverDb)) r['id']],
        ['aa', 'ab'],
      );
    },
  );

  test('two phones make the same week offline: the second’s week merges, '
      'its meals land in the first’s, and both converge', () async {
    await _week(phoneA, 'wa');
    await _meal(phoneA, 'ea', 'wa');
    await _week(phoneB, 'wb');
    await _meal(phoneB, 'eb', 'wb');
    await _override(phoneB, 'ob', week: 'wb', action: 'exclude');

    await _uploadAll(phoneA, connectorA);
    await _uploadAll(phoneB, connectorB);

    expect(droppedB.writes, isEmpty);
    final weeks = await serverDb.getAll('SELECT id FROM week_plan');
    expect([for (final r in weeks) r['id']], ['wa']);
    final meals = await serverDb.getAll(
      'SELECT id, week_plan_id FROM plan_entry ORDER BY id',
    );
    expect(
      [for (final r in meals) (r['id'], r['week_plan_id'])],
      [('ea', 'wa'), ('eb', 'wa')],
    );

    await _nextSync(phoneB, server);
    expect(
      [
        for (final r in await phoneB.getAll('SELECT id FROM week_plan'))
          r['id'],
      ],
      ['wa'],
    );
    expect(
      [
        for (final r in await phoneB.getAll(
          'SELECT week_plan_id FROM plan_entry ORDER BY id',
        ))
          r['week_plan_id'],
      ],
      ['wa', 'wa'],
    );
    expect((await overrides(phoneB)).single['id'], 'ob');
  });

  test('a meal uploaded after a restart, under a week that lost its key, '
      'finds the winner by the week’s date', () async {
    await _week(serverDb, 'wa');
    await _week(phoneB, 'wb');
    await _uploadAll(phoneB, connectorB);
    // A new session: nothing remembered from the merge.
    await _meal(phoneB, 'eb', 'wb');
    await _uploadAll(
      phoneB,
      AnsiConnector.withTarget(server, onDropped: droppedB),
    );
    expect(droppedB.writes, isEmpty);
    final meal = await serverDb.get(
      "SELECT week_plan_id FROM plan_entry WHERE id = 'eb'",
    );
    expect(meal['week_plan_id'], 'wa');
  });

  test('a change already dropped is gone from the phone after the next '
      'sync, and editing the line again uploads', () async {
    await sharedWeek();
    await _override(serverDb, 'oa', week: 'w', action: 'exclude');
    await _nextSync(phoneB, server);
    // An older build dropped B's own override for the line; the phone kept
    // its orphan until the next sync.
    await _override(phoneB, 'ob', week: 'w', action: 'replace', quantity: 3);
    await drainCrudQueue(phoneB);
    await _nextSync(phoneB, server);
    expect([for (final r in await overrides(phoneB)) r['id']], ['oa']);

    // Saved again from the recipe in its week: it edits the row there.
    await phoneB.execute(
      'UPDATE week_recipe_line_override SET action = ?, quantity = ? '
      'WHERE id = ?',
      ['replace', 3, 'oa'],
    );
    await _uploadAll(phoneB, connectorB);
    expect((await overrides(serverDb)).single['quantity'], 3.0);
  });
}
