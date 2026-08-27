import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/planning/data/planning_repository_impl.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// Inserts a bare recipe row (the planner only reads id/title for entries).
Future<void> _insertRecipe(
  PowerSyncDatabase db,
  String id,
  String title,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, created_at, '
    'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [id, 'h', title, 2, now, now],
  );
}

Future<void> _insertMember(
  PowerSyncDatabase db,
  String id,
  String name,
  int sortOrder,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    'INSERT INTO household_member (id, household_id, display_name, sort_order, '
    'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [id, 'h', name, sortOrder, now, now],
  );
}

/// The Monday of the active test week and the one before it.
final _thisWeek = DateTime.utc(2026, 8, 24);
final _lastWeek = DateTime.utc(2026, 8, 17);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqlitePlanningRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqlitePlanningRepository(db);
  });

  tearDown(() => closeTestDb(db, dir));

  group('members', () {
    test('reads the synced household members in display order', () async {
      // Members are server-owned (onboarding); the app reads them. Seed the
      // synced table directly, as sync would.
      await _insertMember(db, 'm2', 'Jun', 1);
      await _insertMember(db, 'm1', 'Ada', 0);
      final members = await repo.members();
      expect(members.map((m) => m.displayName), ['Ada', 'Jun']);
    });
  });

  group('weeks and entries', () {
    test('watchWeek is null until the first meal is planned', () async {
      expect(await repo.watchWeek(_thisWeek).first, isNull);
    });

    test('addEntry creates the week lazily and appears in watchWeek', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 3, // Thursday
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: ['m1', 'm2'],
      );

      final week = await repo.watchWeek(_thisWeek).first;
      expect(week, isNotNull);
      expect(week!.weekStart, _thisWeek);
      final entry = week.entries.single;
      expect(entry.recipeTitle, 'Curry');
      expect(entry.dayOfWeek, 3);
      expect(entry.mealSlot, 'Dinner');
      expect(entry.eaterIds, ['m1', 'm2']);
      // No override given → portions tracks the eater count.
      expect(entry.portions, isNull);
      expect(entry.portionsOrDefault, 2);

      // Exactly one week_plan row was created for the Monday key.
      final weeks = await db.getAll('SELECT week_start_date FROM week_plan');
      expect(weeks, hasLength(1));
      expect(weeks.single['week_start_date'], '2026-08-24');
    });

    test('addEntry stores a portions override', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: ['m1', 'm2'],
        portions: 5,
      );
      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.portions, 5);
      expect(entry.portionsOrDefault, 5);
    });

    test(
      'any day in the week resolves to the same Monday-keyed week',
      () async {
        await _insertRecipe(db, 'r1', 'Curry');
        // Add addressing the week by a Saturday; read it back by its Monday.
        await repo.addEntry(
          weekStart: DateTime.utc(2026, 8, 29),
          dayOfWeek: 5,
          mealSlot: 'Lunch',
          recipeId: 'r1',
          eaterIds: const [],
        );
        final week = await repo.watchWeek(_thisWeek).first;
        expect(week?.entries, hasLength(1));
      },
    );

    test('a deleted recipe reads back with a null title', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: const [],
      );
      await db.execute('UPDATE recipe SET deleted_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        'r1',
      ]);
      final week = await repo.watchWeek(_thisWeek).first;
      expect(week!.entries.single.recipeTitle, isNull);
    });

    test('watchWeek re-fires on add, setEaters, and remove', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      final stream = StreamIterator(repo.watchWeek(_thisWeek));
      addTearDown(stream.cancel);

      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isNull); // empty week

      final id = await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: ['m1'],
      );
      expect(await stream.moveNext(), isTrue);
      expect(stream.current!.entries.single.eaterIds, ['m1']);

      await repo.setEaters(id, ['m1', 'm2']);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current!.entries.single.eaterIds, ['m1', 'm2']);

      await repo.removeEntry(id);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current!.entries, isEmpty);
    });
  });

  group('copy last week', () {
    test(
      'mostRecentWeekBefore returns the latest earlier week with meals',
      () async {
        await _insertRecipe(db, 'r1', 'Curry');
        // An even earlier empty week must be skipped in favour of a later one
        // with meals; the current week is not "before" itself.
        await repo.addEntry(
          weekStart: _lastWeek,
          dayOfWeek: 1,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          eaterIds: const ['m1'],
        );
        final source = await repo.mostRecentWeekBefore(_thisWeek);
        expect(source, isNotNull);
        expect(source!.weekStart, _lastWeek);
        expect(source.entries, hasLength(1));
      },
    );

    test('copyLastWeek clones every meal into the current week', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      await _insertRecipe(db, 'r2', 'Ragu');
      await repo.addEntry(
        weekStart: _lastWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: const ['m1', 'm2'],
      );
      await repo.addEntry(
        weekStart: _lastWeek,
        dayOfWeek: 5,
        mealSlot: 'Lunch',
        recipeId: 'r2',
        eaterIds: const ['m1'],
      );

      final copied = await repo.copyLastWeek(_thisWeek);
      expect(copied, 2);

      final week = await repo.watchWeek(_thisWeek).first;
      expect(week!.entries, hasLength(2));
      expect(week.entries.map((e) => e.recipeTitle).toSet(), {'Curry', 'Ragu'});
      // Eaters and slots survive the copy.
      final dinner = week.entries.firstWhere((e) => e.mealSlot == 'Dinner');
      expect(dinner.eaterIds, ['m1', 'm2']);
    });

    test('copyLastWeek is a no-op with no earlier week', () async {
      expect(await repo.copyLastWeek(_thisWeek), 0);
      expect(await repo.watchWeek(_thisWeek).first, isNull);
    });
  });
}
