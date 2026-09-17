import 'dart:async';
import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_repository_impl.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Gives [id] a stated yield ("makes 1 cup") — the fact that turns a component
/// line's printed amount into batches (step 8.6 / D2).
Future<void> _setYield(
  PowerSyncDatabase db,
  String id,
  double qty,
  Unit unit,
) => db.execute(
  'UPDATE recipe SET yield_qty = ?, yield_unit = ? WHERE id = ?',
  [qty, unit.id, id],
);

/// Adds a component line ("¼ cup of [subRecipeId]") to [recipeId], creating
/// its group. Written with plain INSERTs because PowerSync's local tables are
/// VIEWS — no UPSERT anywhere.
Future<void> _addComponentLine(
  PowerSyncDatabase db,
  String recipeId,
  String subRecipeId, {
  double? quantity = 0.25,
  Unit unit = cup,
  String suffix = '',
  bool optional = false,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final groupId = 'g-$recipeId$suffix';
  await db.execute(
    'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
    'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [groupId, 'h', recipeId, 0, now, now],
  );
  await db.execute(
    'INSERT INTO recipe_line_item (id, household_id, group_id, sub_recipe_id, '
    'quantity, unit, optional, sort_order, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'li-$recipeId-$subRecipeId$suffix',
      'h',
      groupId,
      subRecipeId,
      quantity,
      unit.id,
      if (optional) 1 else 0,
      0,
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
    planning = SqlitePlanningRepository(db, householdId: 'h');
  });

  tearDown(() => closeTestDb(db, dir));

  test('an unplanned week derives an empty cook plan', () async {
    expect((await repo.watchCookPlan(_week).first).isEmpty, isTrue);
  });

  // A-D4, the half of the ruling that lives here: nothing about a protein bar
  // is cooked, so it opens no session and joins no batch. (The other half —
  // that the SHOPPING list does include it — is pinned in
  // `shopping_repository_test.dart`.)
  group('a planned INGREDIENT meal', () {
    setUp(() async {
      await db.execute(
        'INSERT INTO ingredient (id, household_id, canonical_name, '
        'default_unit, match_text, status, created_at, updated_at) '
        "VALUES ('bar', 'h', 'Protein bar', 'g', 'protein bar', 'complete', "
        "'2026-01-01', '2026-01-01')",
      );
    });

    test('opens no cook session at all', () async {
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a', 'b'],
        quantity: 60,
        unit: g,
      );
      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.isEmpty, isTrue);
      expect(plan.recipes, isEmpty);
    });

    test('it does not disturb the dishes planned beside it', () async {
      await _insertRecipe(db, 'ragu', 'House Ragù');
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'ragu',
        eaterIds: const ['a', 'b'],
      );
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a', 'b'],
        quantity: 60,
        unit: g,
      );
      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.recipes.map((r) => r.title), ['House Ragù']);
      // The snack's demand is NOT folded into the dish's batch.
      expect(plan.recipes.single.totalPortions, 2);
    });
  });

  // The same ruling, one kind over: nothing about an office lunch is cooked
  // either, and the shopping list does not buy it — which is pinned in
  // `shopping_repository_test.dart`.
  group('a planned meal eaten OUT', () {
    test('opens no cook session at all', () async {
      await planning.addOutEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Lunch',
        label: 'Office lunch',
        eaterIds: const ['a', 'b'],
      );
      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.isEmpty, isTrue);
      expect(plan.recipes, isEmpty);
    });

    test('it does not disturb the dishes planned beside it', () async {
      await _insertRecipe(db, 'ragu', 'House Ragù');
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'ragu',
        eaterIds: const ['a', 'b'],
      );
      await planning.addOutEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Lunch',
        label: 'Office lunch',
        eaterIds: const ['a', 'b'],
      );
      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.recipes.map((r) => r.title), ['House Ragù']);
      // Its eaters are NOT folded into the dish's batch.
      expect(plan.recipes.single.totalPortions, 2);
    });
  });

  test('every shelf-life column reaches the plan — the clustering itself is '
      "cook_plan_test's subject, not SQL's", () async {
    await _insertRecipe(
      db,
      'ragu',
      'House Ragù',
      servings: 3,
      keepsForDays: 3,
      freezable: true,
      freezerDays: 30,
    );
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 1,
      mealSlot: 'Dinner',
      recipeId: 'ragu',
      eaterIds: ['a', 'b'],
    );

    final ragu = (await repo.watchCookPlan(_week).first).recipes.single;
    expect(ragu.recipeId, 'ragu');
    expect(ragu.title, 'House Ragù');
    expect(ragu.servingsBase, 3);
    expect(ragu.keepsForDays, 3);
    expect(ragu.freezable, isTrue);
    expect(ragu.freezerDays, 30);
    // A recipe with no shelf life reads as unknown, not as zero — the
    // difference between "never split" and "split every day".
    await _insertRecipe(db, 'soup', 'Soup');
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 2,
      mealSlot: 'Dinner',
      recipeId: 'soup',
      eaterIds: ['a'],
    );
    final soup = (await repo.watchCookPlan(_week).first).recipes.firstWhere(
      (r) => r.recipeId == 'soup',
    );
    expect(soup.keepsForDays, isNull);
    expect(soup.freezable, isFalse);
    expect(soup.freezerDays, isNull);
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

  test('a member’s portion factor drives the demand, the override still wins, '
      'and a factor change re-derives the plan', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final (id, name, order, factor) in [
      ('a', 'Ada', 0, 1.0),
      ('b', 'Jun', 1, 0.75),
    ]) {
      await db.execute(
        'INSERT INTO household_member (id, household_id, display_name, '
        'sort_order, portion_factor, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, 'h', name, order, factor, now, now],
      );
    }
    await _insertRecipe(db, 'r', 'Soup', servings: 4, keepsForDays: 4);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'r',
      eaterIds: ['a', 'b'],
    );
    final stream = StreamIterator(repo.watchCookPlan(_week));
    expect(await stream.moveNext(), isTrue);
    var session = stream.current.recipes.single.sessions.single;
    // 1 + ¾ of a serves-4 recipe — fractional, and not rounded up.
    expect(session.totalPortions, 1.75);
    expect(session.scaleFactor, 0.4375);

    // The factor is part of the derivation, so moving it re-fires the watch.
    await planning.setPortionFactor('b', 1.5);
    expect(await stream.moveNext(), isTrue);
    session = stream.current.recipes.single.sessions.single;
    expect(session.totalPortions, 2.5);

    // The whole-number override still wins over the eaters' factors.
    final entryId = (await planning.watchWeek(_week).first)!.entries.single.id;
    await planning.setPortions(entryId, 3);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.recipes.single.sessions.single.totalPortions, 3);
    await stream.cancel();
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

  group('nested recipes', () {
    Future<void> planSliders({
      int day = 5,
      List<String> eaters = const ['a'],
    }) => planning.addEntry(
      weekStart: _week,
      dayOfWeek: day,
      mealSlot: 'Dinner',
      recipeId: 'sliders',
      eaterIds: eaters,
    );

    test(
      'planning a parent derives the component session, in batches',
      () async {
        await _insertRecipe(db, 'sliders', 'Sausage Sliders', servings: 1);
        await _insertRecipe(
          db,
          'aioli',
          'Romesco Aioli',
          servings: 4,
          keepsForDays: 5,
        );
        await _setYield(db, 'aioli', 1, cup);
        await _addComponentLine(db, 'sliders', 'aioli');
        await planSliders();

        final plan = await repo.watchCookPlan(_week).first;
        final derived = plan.recipes.firstWhere((r) => r.recipeId == 'aioli');
        final session = derived.sessions.single;
        expect(session.isComponent, isTrue);
        expect(session.batchesToCook, closeTo(0.25, 1e-12));
        expect(session.cookDay, 5);
        expect(session.demandedBy, ['Sausage Sliders']);
        expect(plan.gaps, isEmpty);
      },
    );

    test('no yield ⇒ a named gap on the plan, and no session at all', () async {
      await _insertRecipe(db, 'sliders', 'Sausage Sliders', servings: 1);
      await _insertRecipe(db, 'aioli', 'Romesco Aioli', servings: 4);
      await _addComponentLine(db, 'sliders', 'aioli');
      await planSliders();

      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.recipes.any((r) => r.recipeId == 'aioli'), isFalse);
      final gap = plan.gaps.single;
      expect(gap.title, 'Romesco Aioli');
      expect(gap.reason, const ComponentYieldMissing());
      expect(gap.demandedBy.single.title, 'Sausage Sliders');
      expect(plan.unresolvedComponentsByParent, {'sliders': 1});
    });

    test(
      'setting the yield re-fires the watch and the gap becomes a session',
      () async {
        await _insertRecipe(db, 'sliders', 'Sausage Sliders', servings: 1);
        await _insertRecipe(
          db,
          'aioli',
          'Romesco Aioli',
          servings: 4,
          keepsForDays: 5,
        );
        await _addComponentLine(db, 'sliders', 'aioli');
        await planSliders();

        final stream = StreamIterator(repo.watchCookPlan(_week));
        addTearDown(stream.cancel);
        expect(await stream.moveNext(), isTrue);
        expect(stream.current.gaps, hasLength(1));

        await _setYield(db, 'aioli', 1, cup);
        expect(await stream.moveNext(), isTrue);
        expect(stream.current.gaps, isEmpty);
        expect(
          stream.current.recipes
              .firstWhere((r) => r.recipeId == 'aioli')
              .sessions
              .single
              .batchesToCook,
          closeTo(0.25, 1e-12),
        );
      },
    );

    test('adding a component line re-fires the watch — the line-item tables '
        'are watch triggers too', () async {
      await _insertRecipe(db, 'sliders', 'Sausage Sliders', servings: 1);
      await _insertRecipe(
        db,
        'aioli',
        'Romesco Aioli',
        servings: 4,
        keepsForDays: 5,
      );
      await _setYield(db, 'aioli', 1, cup);
      await planSliders();

      final stream = StreamIterator(repo.watchCookPlan(_week));
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.recipes, hasLength(1));

      await _addComponentLine(db, 'sliders', 'aioli');
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.recipes, hasLength(2));
    });

    test('a deleted target derives nothing and flags nothing', () async {
      await _insertRecipe(db, 'sliders', 'Sausage Sliders', servings: 1);
      await _insertRecipe(db, 'aioli', 'Romesco Aioli', servings: 4);
      await _setYield(db, 'aioli', 1, cup);
      await _addComponentLine(db, 'sliders', 'aioli');
      await planSliders();
      await db.execute('UPDATE recipe SET deleted_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        'aioli',
      ]);

      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.recipes, hasLength(1));
      expect(plan.gaps, isEmpty);
    });
  });

  test('an optional line does not change the cook plan: a batch is a batch '
      'whether the lime comes', () async {
    await _insertRecipe(db, 'curry', 'Chicken Curry', keepsForDays: 3);
    await _insertRecipe(db, 'plain', 'Plain Curry', keepsForDays: 3);
    // One ordinary and one optional ingredient line on the first recipe only;
    // the second has no lines at all. Plain INSERTs — the tables are views.
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['g-curry', 'h', 'curry', 0, now, now],
    );
    for (final (id, optional) in [('li-onion', 0), ('li-lime', 1)]) {
      await db.execute(
        'INSERT INTO recipe_line_item (id, household_id, group_id, '
        'ingredient_id, quantity, unit, optional, sort_order, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, 'h', 'g-curry', 'ing-$id', 1, pieces.id, optional, 0, now, now],
      );
    }
    for (final recipeId in ['curry', 'plain']) {
      for (final day in [0, 5]) {
        await planning.addEntry(
          weekStart: _week,
          dayOfWeek: day,
          mealSlot: 'Dinner',
          recipeId: recipeId,
          eaterIds: ['a', 'b'],
        );
      }
    }

    final plan = await repo.watchCookPlan(_week).first;
    final byTitle = {for (final r in plan.recipes) r.title: r};
    final curry = byTitle['Chicken Curry']!;
    final plain = byTitle['Plain Curry']!;
    expect(curry.sessions.map((s) => s.cookDay), [0, 5]);
    expect(
      curry.sessions.map((s) => s.cookDay),
      plain.sessions.map((s) => s.cookDay),
    );
    expect(
      curry.sessions.map((s) => s.scaleFactor),
      plain.sessions.map((s) => s.scaleFactor),
    );
    expect(curry.totalPortions, plain.totalPortions);
  });

  group("an optional COMPONENT line is the week's decision", () {
    Future<void> seed() async {
      await _insertRecipe(db, 'sliders', 'Sausage Sliders', servings: 1);
      await _insertRecipe(
        db,
        'aioli',
        'Romesco Aioli',
        servings: 4,
        keepsForDays: 5,
      );
      await _setYield(db, 'aioli', 1, cup);
      await _addComponentLine(db, 'sliders', 'aioli', optional: true);
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 5,
        mealSlot: 'Dinner',
        recipeId: 'sliders',
        eaterIds: ['a'],
      );
    }

    test('with no include row the sub-recipe is not cooked at all', () async {
      await seed();
      final plan = await repo.watchCookPlan(_week).first;
      expect(plan.recipes.map((r) => r.recipeId), ['sliders']);
      expect(plan.gaps, isEmpty);
    });

    test('ticking it in re-fires the watch and opens the session', () async {
      await seed();
      final stream = StreamIterator(repo.watchCookPlan(_week));
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.recipes, hasLength(1));

      final variants = SqliteWeekVariantRepository(db, householdId: 'h');
      await variants.setLineIncluded(
        _week,
        'sliders',
        'li-sliders-aioli',
        included: true,
      );

      expect(await stream.moveNext(), isTrue);
      final derived = stream.current.recipes.firstWhere(
        (r) => r.recipeId == 'aioli',
      );
      expect(derived.sessions.single.batchesToCook, closeTo(0.25, 1e-12));

      // …and taking it back out closes it again.
      await variants.setLineIncluded(
        _week,
        'sliders',
        'li-sliders-aioli',
        included: false,
      );
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.recipes.map((r) => r.recipeId), ['sliders']);
    });
  });
}
