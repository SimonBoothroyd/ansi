import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// Guards the *harness*, not the app: if `openTestDb` ever degrades back to
/// plain SQLite tables, repository SQL that PowerSync's views reject would pass
/// CI and fail on the phone again (tech-debt tracker, 2026-08-26).
void main() {
  late PowerSyncDatabase db;
  late Directory dir;

  setUp(() async {
    (db, dir) = await openTestDb();
  });

  tearDown(() => closeTestDb(db, dir));

  test('local tables are views, not tables', () async {
    final rows = await db.getAll(
      "SELECT name, type FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('recipe', 'book', 'book_section', 'ingredient')",
    );
    expect(rows, isEmpty);
    final views = await db.getAll(
      "SELECT name FROM sqlite_master WHERE type = 'view' "
      "AND name IN ('recipe', 'book', 'book_section', 'ingredient')",
    );
    expect(views.map((r) => r['name']), hasLength(4));
  });

  test('INSERT … ON CONFLICT is rejected on a view', () async {
    await expectLater(
      db.execute(
        'INSERT INTO recipe (id, title) VALUES (?, ?) '
        'ON CONFLICT (id) DO UPDATE SET title = excluded.title',
        ['r1', 'Curry'],
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('writes go through the view into the backing ps_data table', () async {
    await db.execute('INSERT INTO recipe (id, title) VALUES (?, ?)', [
      'r1',
      'Curry',
    ]);
    final row = await db.get(
      "SELECT count(*) AS c FROM ps_data__recipe WHERE id = 'r1'",
    );
    expect(row['c'], 1);
  });
}
