import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/cook_plan/data/cook_plan_repository_impl.dart';
import 'package:mise/features/planning/data/planning_repository_impl.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// Inserts a recipe with shelf-life columns the cook plan reads.
Future<void> _insertRecipe(
  PowerSyncDatabase db,
  String id,
  String title, {
  double servings = 2,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final freezableFlag = freezable ? 1 : 0;
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, '
    'keeps_for_days, freezable, freezer_days, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      'h',
      title,
      servings,
      keepsForDays,
      freezableFlag,
      freezerDays,
      now,
      now,
    ],
  );
}

final _week = DateTime.utc(2026, 8, 24);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteCookPlanRepository repo;
  late SqlitePlanningRepository planning;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteCookPlanRepository(db);
    planning = SqlitePlanningRepository(db);
  });

  tearDown(() => closeTestDb(db, dir));

  test('an unplanned week derives an empty cook plan', () async {
    expect((await repo.watchCookPlan(_week).first).isEmpty, isTrue);
  });

  test('groups meals by recipe and splits past the fridge window', () async {
    await _insertRecipe(db, 'curry', 'Chicken Curry', keepsForDays: 3);
    // Mon + Sat of the same recipe, keeps 3 → two cook sessions.
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a', 'b'],
    );
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 5,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a', 'b'],
    );

    final plan = await repo.watchCookPlan(_week).first;
    final curry = plan.recipes.single;
    expect(curry.title, 'Chicken Curry');
    expect(curry.isSplit, isTrue);
    expect(curry.sessions.map((s) => s.cookDay), [0, 5]);
    expect(curry.totalPortions, 4);
  });

  test('a freezable far meal merges into one frozen session', () async {
    await _insertRecipe(
      db,
      'ragu',
      'House Ragù',
      keepsForDays: 3,
      freezable: true,
    );
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 1, // Tue
      mealSlot: 'Dinner',
      recipeId: 'ragu',
      eaterIds: ['a', 'b'],
    );
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 5, // Sat
      mealSlot: 'Dinner',
      recipeId: 'ragu',
      eaterIds: ['a', 'b'],
    );

    final plan = await repo.watchCookPlan(_week).first;
    final ragu = plan.recipes.single;
    expect(ragu.isSplit, isFalse);
    expect(ragu.usesFreezer, isTrue);
    expect(ragu.sessions.single.frozenDays, [5]);
  });

  test('a portions override drives the batch size', () async {
    await _insertRecipe(db, 'r', 'Soup', keepsForDays: 4);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'r',
      eaterIds: ['a'],
      portions: 6, // override the single eater
    );
    final session =
        (await repo.watchCookPlan(_week).first).recipes.single.sessions.single;
    expect(session.totalPortions, 6);
    expect(session.scaleFactor, 3);
  });

  test('a meal whose recipe was deleted is left out of the plan', () async {
    await _insertRecipe(db, 'gone', 'Ghost', keepsForDays: 3);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'gone',
      eaterIds: ['a'],
    );
    await db.execute('UPDATE recipe SET deleted_at = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      'gone',
    ]);
    expect((await repo.watchCookPlan(_week).first).isEmpty, isTrue);
  });

  test('watchCookPlan re-derives when a recipe shelf life changes', () async {
    await _insertRecipe(db, 'curry', 'Curry', keepsForDays: 6);
    for (final day in [0, 5]) {
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: day,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: ['a'],
      );
    }

    final stream = StreamIterator(repo.watchCookPlan(_week));
    addTearDown(stream.cancel);

    // keeps 6 → Mon+Sat (gap 5) is one batch.
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.recipes.single.isSplit, isFalse);

    // Tighten the shelf life; the watch re-fires and the plan now splits.
    await db.execute('UPDATE recipe SET keeps_for_days = ? WHERE id = ?', [
      3,
      'curry',
    ]);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.recipes.single.isSplit, isTrue);
    expect(stream.current.recipes.single.sessions, hasLength(2));
  });
}
