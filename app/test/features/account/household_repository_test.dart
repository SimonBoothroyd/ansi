/// The first reader of the `household` table: the household's week shape.
///
/// Over the real schema, because `household` is a PowerSync view like every
/// other local table and this is the only query the app runs against it.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _insertHousehold(
  PowerSyncDatabase db,
  String id, {
  int? weekStartsOn,
}) async {
  const now = '2026-01-01T00:00:00Z';
  await db.execute(
    'INSERT INTO household (id, name, week_starts_on, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [id, 'Ours', weekStartsOn, now, now],
  );
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late List<(String, int)> flips;
  late SqliteHouseholdRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    flips = [];
    repo = SqliteHouseholdRepository(
      db,
      householdId: 'h',
      flipWeekStart: (householdId, startsOn) async =>
          flips.add((householdId, startsOn)),
    );
  });

  tearDown(() => closeTestDb(db, dir));

  test('a household with no row yet starts its week on Monday', () async {
    expect(await repo.watchWeekShape().first, WeekShape.monday);
  });

  test('a row that says nothing starts its week on Monday', () async {
    await _insertHousehold(db, 'h');
    expect(await repo.watchWeekShape().first, WeekShape.monday);
  });

  test('the stored ISO weekday is the shape', () async {
    await _insertHousehold(db, 'h', weekStartsOn: DateTime.sunday);
    expect(await repo.watchWeekShape().first, WeekShape.sunday);
  });

  test('every ISO weekday reads back as itself', () async {
    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      await db.execute('DELETE FROM household WHERE id = ?', ['h']);
      await _insertHousehold(db, 'h', weekStartsOn: day);
      expect((await repo.watchWeekShape().first).startsOn, day);
    }
  });

  test('a value outside 1..7 falls back rather than throwing', () async {
    // The column's own check refuses it, so this is a row no server wrote —
    // a corrupted download or a future convention. Monday is the honest
    // reading of "nobody said"; crashing the Week screen is not.
    await _insertHousehold(db, 'h', weekStartsOn: 0);
    expect(await repo.watchWeekShape().first, WeekShape.monday);
  });

  test('another household in the same database is not read', () async {
    await _insertHousehold(db, 'other', weekStartsOn: DateTime.sunday);
    expect(await repo.watchWeekShape().first, WeekShape.monday);
  });

  test('a retired household row reads as nobody said', () async {
    await _insertHousehold(db, 'h', weekStartsOn: DateTime.sunday);
    await db.execute(
      "UPDATE household SET deleted_at = '2026-01-02T00:00:00Z' WHERE id = ?",
      ['h'],
    );
    expect(await repo.watchWeekShape().first, WeekShape.monday);
  });

  test('the watch re-fires when the column changes', () async {
    await _insertHousehold(db, 'h');
    final stream = StreamIterator(repo.watchWeekShape());
    addTearDown(stream.cancel);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current, WeekShape.monday);

    // The flip lands as a synced UPDATE, not as a local write, so the shape
    // every surface reads has to move off the row arriving.
    await db.execute('UPDATE household SET week_starts_on = ? WHERE id = ?', [
      DateTime.sunday,
      'h',
    ]);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current, WeekShape.sunday);
  });

  test('setWeekStart asks the server and writes nothing locally', () async {
    await _insertHousehold(db, 'h');
    await repo.setWeekStart(DateTime.sunday);

    expect(flips, [('h', DateTime.sunday)]);
    // The column still says Monday: the flip re-homes every week of the
    // household in one server transaction, and the new value arrives by sync.
    // A device that wrote it itself would be reading its own rows under a key
    // they do not carry.
    final row = await db.get(
      'SELECT week_starts_on FROM household WHERE id = ?',
      ['h'],
    );
    expect(row['week_starts_on'], isNull);
    expect(await repo.watchWeekShape().first, WeekShape.monday);
  });
}
