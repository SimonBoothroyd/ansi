import 'dart:io';

import 'package:ansi/features/cook_plan/data/leftover_repository_impl.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/leftover_rows.dart';
import '../../helpers/test_db.dart';

final _week = DateTime(2026, 8, 24);
final _wednesday = DateTime(2026, 8, 26);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteLeftoverRepository repo;
  late SqlitePlanningRepository planning;

  Future<List<Leftover>> shelves({DateTime? today}) => repo
      .watchHouseholdLeftovers(weekStart: _week, today: today ?? _wednesday)
      .first;

  Future<Map<String, Object?>> stored(String id) async =>
      db.get('SELECT * FROM leftover WHERE id = ?', [id]);

  /// A curry for Ada (1) and Jun (¾) on [day]; Jun ticks it, so Ada's 1 is
  /// left.
  Future<String> cookedCurry(int day) async {
    final id = await planning.addEntry(
      weekStart: _week,
      dayOfWeek: day,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: const ['a', 'b'],
    );
    await planning.setMealEaten(
      id,
      memberId: 'b',
      eatenAt: DateTime.utc(2026, 8, 24 + day, 19),
    );
    return id;
  }

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteLeftoverRepository(db, householdId: 'h');
    planning = SqlitePlanningRepository(db, householdId: 'h');
    await db.execute(
      'INSERT INTO recipe (id, household_id, title, servings_base, '
      'keeps_for_days, freezable, freezer_days, created_at, updated_at) '
      "VALUES ('curry', 'h', 'Curry', 2, 3, 1, 90, '2026-01-01', "
      "'2026-01-01')",
    );
    await db.execute(
      'INSERT INTO household_member (id, household_id, display_name, '
      'sort_order, portion_factor, created_at, updated_at) VALUES '
      "('a', 'h', 'Ada', 0, 1, '2026-01-01', '2026-01-01'), "
      "('b', 'h', 'Jun', 1, 0.75, '2026-01-01', '2026-01-01')",
    );
  });

  tearDown(() => closeTestDb(db, dir));

  test(
    'a cooked batch reads as a fridge row, dated by its fridge life',
    () async {
      final mon = await cookedCurry(0);
      final left = (await shelves()).single;
      expect(left.isStored, isFalse);
      expect(left.batch, mon);
      expect(left.place, LeftoverPlace.fridge);
      expect(left.portions, 1);
      expect(left.goodUntil, DateTime(2026, 8, 27));
    },
  );

  test('a first touch on a derived row stores it, naming its batch', () async {
    final mon = await cookedCurry(0);
    await repo.setLeftoverPortions((await shelves()).single, 3);
    final left = (await shelves()).single;
    expect(left.isStored, isTrue);
    expect(left.batch, mon);
    expect(left.portions, 3);
    // A second write finds the stored row rather than storing another.
    await repo.setLeftoverPortions((await shelves()).single, 2);
    final rows = await db.getAll('SELECT id, portions FROM leftover');
    expect(rows.single['portions'], 2);
  });

  test(
    'a write about a derived row a second phone stored reuses that row',
    () async {
      final mon = await cookedCurry(0);
      final derived = (await shelves()).single;
      await insertLeftover(
        db,
        id: 'lo1',
        place: 'fridge',
        recipeId: 'curry',
        portions: 1,
        batch: mon,
      );
      await repo.markLeftoversGone([derived]);
      expect((await db.getAll('SELECT id FROM leftover')).single['id'], 'lo1');
      expect((await stored('lo1'))['gone_at'], isNotNull);
    },
  );

  test(
    'the stepper stores what it shows plus the meals planned from the row',
    () async {
      await insertLeftover(db, id: 'lo1', recipeId: 'curry', portions: 4);
      // Ada's 1 on next Tuesday comes from the freezer.
      await planning.addEntry(
        weekStart: _week.add(const Duration(days: 7)),
        dayOfWeek: 1,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: const ['a'],
        fromLeftover: 'lo1',
      );
      final left = (await shelves()).single;
      expect(left.portions, 3);
      expect(left.planned, 1, reason: 'still to come, so spoken for');

      await repo.setLeftoverPortions(left, 2);
      expect((await stored('lo1'))['portions'], 3);
      expect((await shelves()).single.portions, 2);

      // Once its day is behind us the meal is eaten, no longer planned.
      expect((await shelves(today: DateTime(2026, 9, 2))).single.planned, 0);
    },
  );

  test('Freeze moves a row to the freezer, dated by the day given', () async {
    await cookedCurry(0);
    await repo.freezeLeftover((await shelves()).single, since: _wednesday);
    final left = (await shelves()).single;
    expect(left.place, LeftoverPlace.freezer);
    expect(left.since, _wednesday);
    expect(left.goodUntil, DateTime(2026, 11, 24));
    expect(left.portions, 1);
  });

  test(
    'Gone hides each row named, derived or stored, and stays gone',
    () async {
      await cookedCurry(0);
      await insertLeftover(db, id: 'lo1', label: 'Soup from Mum');
      expect(await shelves(), hasLength(2));
      await repo.markLeftoversGone(await shelves());
      expect(await shelves(), isEmpty);
      expect(
        (await db.getAll(
          'SELECT gone_at FROM leftover',
        )).every((r) => r['gone_at'] != null),
        isTrue,
      );
    },
  );

  test(
    'Add stores a recipe or words, in either place, dated as said',
    () async {
      await repo.addLeftover(
        place: LeftoverPlace.freezer,
        portions: 4,
        since: DateTime(2026, 8, 12),
        label: '  Chili from Jo ',
      );
      await repo.addLeftover(
        place: LeftoverPlace.fridge,
        portions: 2,
        since: DateTime(2026, 8, 25),
        recipeId: 'curry',
      );
      final [curry, chili] = await shelves();
      expect(
        (curry.title, curry.place, curry.portions),
        ('Curry', LeftoverPlace.fridge, 2),
      );
      expect(curry.goodUntil, DateTime(2026, 8, 28));
      expect(curry.batch, isNull);
      expect(
        (chili.title, chili.place, chili.since),
        ('Chili from Jo', LeftoverPlace.freezer, DateTime(2026, 8, 12)),
      );
      expect(chili.goodUntil, isNull);
    },
  );

  test('the places map every stored row, gone or not', () async {
    await insertLeftover(db, id: 'lo1', recipeId: 'curry');
    await insertLeftover(db, id: 'lo2', place: 'fridge', label: 'Rice');
    await db.execute(
      "UPDATE leftover SET gone_at = '2026-08-25' WHERE id = 'lo2'",
    );
    expect(await repo.watchLeftoverPlaces().first, {
      'lo1': LeftoverPlace.freezer,
      'lo2': LeftoverPlace.fridge,
    });
  });
}
