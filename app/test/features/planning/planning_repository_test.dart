import 'dart:async';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/planning/domain/week_macros.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// A vocab row — the other half of the entry XOR (step 8.14).
Future<void> _insertIngredient(
  PowerSyncDatabase db,
  String id,
  String name, {
  String? macros,
  double? density,
  double? pieceBasisAmount,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
    'match_text, macros, macros_basis, density_g_per_ml, piece_basis_amount, '
    'status, created_at, updated_at) '
    "VALUES (?, ?, ?, 'g', ?, ?, 'per_g', ?, ?, ?, ?, ?)",
    [
      id,
      'h',
      name,
      name.toLowerCase(),
      macros,
      density,
      pieceBasisAmount,
      if (macros == null) 'stub' else 'complete',
      now,
      now,
    ],
  );
}

Future<void> _insertMeasure(
  PowerSyncDatabase db,
  String id,
  String ingredientId,
  String label,
  double amount,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    'INSERT INTO ingredient_measure (id, household_id, ingredient_id, label, '
    'basis_amount, sort_order, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, 0, ?, ?)',
    [id, 'h', ingredientId, label, amount, now, now],
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

/// The first day of the active test week and the one before it — Mondays,
/// because a Monday-start household is what the app defaults to, and the whole
/// point of the assertions below is that its output has not moved.
final _thisWeek = DateTime.utc(2026, 8, 24);
final _lastWeek = DateTime.utc(2026, 8, 17);

/// The same week under a Sunday-start household: Sun 23 Aug – Sat 29 Aug.
final _thisWeekSunday = DateTime.utc(2026, 8, 23);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqlitePlanningRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqlitePlanningRepository(db, householdId: 'h');
  });

  tearDown(() => closeTestDb(db, dir));

  group('members', () {
    test('reads the synced household members in display order', () async {
      // Members are server-owned (onboarding); the app reads them. Seed the
      // synced table directly, as sync would.
      await _insertMember(db, 'm2', 'Jun', 1);
      await _insertMember(db, 'm1', 'Ada', 0);
      final members = await repo.watchMembers().first;
      expect(members.map((m) => m.displayName), ['Ada', 'Jun']);
    });

    test('a tombstoned member is not pickable', () async {
      await _insertMember(db, 'm1', 'Ada', 0);
      await _insertMember(db, 'm2', 'Gone', 1);
      await db.execute(
        "UPDATE household_member SET deleted_at = '2026-01-01T00:00:00Z' "
        "WHERE id = 'm2'",
      );
      final members = await repo.watchMembers().first;
      expect(members.map((m) => m.displayName), ['Ada']);
    });

    test(
      'a member row without a factor reads 1 — the column’s own default',
      () async {
        await _insertMember(db, 'm1', 'Ada', 0);
        expect((await repo.watchMembers().first).single.portionFactor, 1);
      },
    );

    test('setPortionFactor writes the one client-owned column and watchMembers '
        're-emits it', () async {
      await _insertMember(db, 'm1', 'Ada', 0);
      await _insertMember(db, 'm2', 'Jun', 1);
      final stream = StreamIterator(repo.watchMembers());
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.map((m) => m.portionFactor), [1, 1]);

      // Either member may set either's — the repo takes the member id, not
      // "me".
      await repo.setPortionFactor('m2', 0.75);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.map((m) => m.portionFactor), [1, 0.75]);
      await stream.cancel();

      // Nothing else on the row moved: the server grants UPDATE on
      // portion_factor + updated_at alone, and the local write matches.
      final row = await db.get(
        'SELECT display_name, sort_order FROM household_member WHERE id = ?',
        ['m2'],
      );
      expect(row['display_name'], 'Jun');
      expect(row['sort_order'], 1);
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

    test('the week is addressed by the key it is handed', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      // Resolving a date into a week belongs to the household's WeekShape, so
      // the repository binds exactly the key it is given — a Monday household
      // and a Sunday one write into different weeks from the same Saturday.
      final saturday = DateTime.utc(2026, 8, 29);
      expect(WeekShape.monday.weekStartOf(saturday), _thisWeek);
      expect(WeekShape.sunday.weekStartOf(saturday), _thisWeekSunday);

      await repo.addEntry(
        weekStart: WeekShape.monday.weekStartOf(saturday),
        dayOfWeek: WeekShape.monday.offsetOf(saturday),
        mealSlot: 'Lunch',
        recipeId: 'r1',
        eaterIds: const [],
      );
      final week = await repo.watchWeek(_thisWeek).first;
      expect(week?.entries, hasLength(1));
      // Saturday is offset 5 of a Monday week — the byte-identical value the
      // Monday-only code stored.
      expect(week!.entries.single.dayOfWeek, 5);
      expect(await repo.watchWeek(_thisWeekSunday).first, isNull);
    });

    test('a Sunday household puts its Sunday meal at offset 0', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      final sunday = DateTime.utc(2026, 8, 23);
      await repo.addEntry(
        weekStart: WeekShape.sunday.weekStartOf(sunday),
        dayOfWeek: WeekShape.sunday.offsetOf(sunday),
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: const [],
      );
      // The meal the owner shops for on Sunday morning heads its own week,
      // instead of trailing the week that is ending.
      final week = await repo.watchWeek(_thisWeekSunday).first;
      expect(week?.weekStart, _thisWeekSunday);
      expect(week!.entries.single.dayOfWeek, 0);
      expect(WeekShape.sunday.keyOf(sunday), '2026-08-23');
      // And it is a different week from the Monday one that contains the same
      // date — nothing about the old week was touched.
      expect(await repo.watchWeek(_lastWeek).first, isNull);
    });

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

    test('setPortions writes an override and can hand it back', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      final id = await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: ['m1', 'm2'],
      );
      expect(
        (await repo.watchWeek(_thisWeek).first)!.entries.single.portions,
        isNull,
      );

      await repo.setPortions(id, 3);
      var entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.portions, 3);
      expect(entry.portionsOrDefault, 3);

      // Null is a real value — "track |eaters|" again, not "leave it alone".
      await repo.setPortions(id, null);
      entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.portions, isNull);
      expect(entry.portionsOrDefault, 2);
    });

    test('setMealSlot moves the meal to another slot on its day', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      final id = await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: ['m1'],
      );

      await repo.setMealSlot(id, 'Lunch');
      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.mealSlot, 'Lunch');
      // The day is not a field: the move is within the same day.
      expect(entry.dayOfWeek, 0);
    });

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

      final copied = (await repo.copyLastWeek(_thisWeek)).meals;
      expect(copied, 2);

      final week = await repo.watchWeek(_thisWeek).first;
      expect(week!.entries, hasLength(2));
      expect(week.entries.map((e) => e.recipeTitle).toSet(), {'Curry', 'Ragu'});
      // Eaters and slots survive the copy.
      final dinner = week.entries.firstWhere((e) => e.mealSlot == 'Dinner');
      expect(dinner.eaterIds, ['m1', 'm2']);
    });

    test(
      "copyLastWeek leaves last week's variant behind, and names it",
      () async {
        await _insertRecipe(db, 'r1', 'Slow-Cooker Beef Ragù');
        await repo.addEntry(
          weekStart: _lastWeek,
          dayOfWeek: 1,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          eaterIds: ['m1'],
        );
        // A line of that recipe, and a change to it on LAST week.
        final now = DateTime.now().toUtc().toIso8601String();
        await db.execute(
          'INSERT INTO ingredient_group (id, household_id, recipe_id, '
          'sort_order, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)',
          ['g1', 'h', 'r1', now, now],
        );
        await db.execute(
          'INSERT INTO recipe_line_item (id, household_id, group_id, '
          'ingredient_id, quantity, unit, sort_order, created_at, updated_at) '
          "VALUES (?, ?, ?, ?, 400, 'g', 0, ?, ?)",
          ['l1', 'h', 'g1', 'i1', now, now],
        );
        final variants = SqliteWeekVariantRepository(db, householdId: 'h');
        await variants.saveOverrides(
          _lastWeek,
          'r1',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.exclude,
              recipeLineItemId: 'l1',
            ),
          ],
        );

        final result = await repo.copyLastWeek(_thisWeek);
        expect(result.meals, 1);
        expect(result.variantsLeftBehind, [
          (recipeTitle: 'Slow-Cooker Beef Ragù', changes: 1),
        ]);
        // Not copied is already the behaviour — this pins that it stays so.
        expect(await variants.loadOverrides(_thisWeek, 'r1'), isEmpty);
        expect(await variants.loadOverrides(_lastWeek, 'r1'), hasLength(1));
      },
    );

    test('a copy with no variant behind it reports none', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      await repo.addEntry(
        weekStart: _lastWeek,
        dayOfWeek: 1,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: ['m1'],
      );
      final result = await repo.copyLastWeek(_thisWeek);
      expect(result.meals, 1);
      expect(result.variantsLeftBehind, isEmpty);
    });

    test('copyLastWeek is a no-op with no earlier week', () async {
      expect((await repo.copyLastWeek(_thisWeek)).meals, 0);
      expect(await repo.watchWeek(_thisWeek).first, isNull);
    });
  });

  group('watchLastPlanned — picker recency', () {
    test('maps each recipe to its most recent planned date', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      await _insertRecipe(db, 'r2', 'Salad');
      await _insertRecipe(db, 'r3', 'Never planned');
      // Curry: last week Thursday AND this week Monday → the later wins.
      await repo.addEntry(
        weekStart: _lastWeek,
        dayOfWeek: 3,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: const [],
      );
      await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: const [],
      );
      await repo.addEntry(
        weekStart: _lastWeek,
        dayOfWeek: 5,
        mealSlot: 'Lunch',
        recipeId: 'r2',
        eaterIds: const [],
      );

      final last = await repo.watchLastPlanned().first;
      expect(last['r1'], DateTime.utc(2026, 8, 24)); // this week Monday
      expect(last['r2'], DateTime.utc(2026, 8, 22)); // last week Saturday
      expect(last.containsKey('r3'), isFalse);
    });

    test('a removed meal drops out of the recency map', () async {
      await _insertRecipe(db, 'r1', 'Curry');
      final entryId = await repo.addEntry(
        weekStart: _thisWeek,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        eaterIds: const [],
      );
      expect(await repo.watchLastPlanned().first, contains('r1'));

      await repo.removeEntry(entryId);
      expect(await repo.watchLastPlanned().first, isEmpty);
    });
  });

  // --- A slot takes an ingredient (step 8.14) --------------------------------

  group('an ingredient meal', () {
    test('round-trips with its amount, its measure and its eaters', () async {
      await _insertIngredient(db, 'i1', 'Protein bar');
      await _insertMeasure(db, 'mz', 'i1', 'bar', 60);
      await repo.addIngredientEntry(
        weekStart: _thisWeek,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const ['m1', 'm2'],
        quantity: 1,
        unit: pieces,
        measureId: 'mz',
      );

      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.isIngredient, isTrue);
      expect(entry.recipeId, isNull);
      expect(entry.ingredientId, 'i1');
      expect(entry.title, 'Protein bar');
      expect(entry.quantity, 1);
      expect(entry.unit, pieces);
      expect(entry.measure!.label, 'bar');
      expect(entry.measure!.amount, 60);
      // It carries eaters and multiplies like any other entry (A-D3).
      expect(entry.eaterIds, ['m1', 'm2']);
      expect(entry.mealSlot, 'Snack');
    });

    test('carries the vocab row’s numbers so the week can weigh it', () async {
      await _insertIngredient(
        db,
        'i1',
        'Protein bar',
        macros: '{"kcal":350,"protein":33,"carb":30,"fat":11}',
        density: 1.1,
      );
      await repo.addIngredientEntry(
        weekStart: _thisWeek,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const [],
        quantity: 60,
        unit: g,
      );
      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.nutrition!.macros!.kcal, 350);
      expect(entry.nutrition!.densityGPerMl, 1.1);
      expect(entry.nutrition!.basis, MacrosBasis.perG);
    });

    test('the piece weight rides along too, so a bare count weighs '
        '(ADR-0015)', () async {
      await _insertIngredient(
        db,
        'i1',
        'Protein bar',
        macros: '{"kcal":350,"protein":33,"carb":30,"fat":11}',
        pieceBasisAmount: 60,
      );
      await repo.addIngredientEntry(
        weekStart: _thisWeek,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const ['m1'],
        quantity: 2,
        unit: pieces,
      );
      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.nutrition!.pieceBasisAmount, 60);

      // …and the number reaches the sum: 2 × 60 g of a 350 kcal/100 g bar.
      final macros = sumPlannedMacros([entry], summaryFor: (_) => null);
      expect(macros.excluded, isEmpty);
      expect(macros.total!.kcal, closeTo(420, 1e-9));
    });

    test(
      'with no piece weight the same bare count is left out, and named',
      () async {
        await _insertIngredient(
          db,
          'i1',
          'Protein bar',
          macros: '{"kcal":350,"protein":33,"carb":30,"fat":11}',
        );
        await repo.addIngredientEntry(
          weekStart: _thisWeek,
          dayOfWeek: 1,
          mealSlot: 'Snack',
          ingredientId: 'i1',
          eaterIds: const ['m1'],
          quantity: 2,
          unit: pieces,
        );
        final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
        expect(entry.nutrition!.pieceBasisAmount, isNull);

        final macros = sumPlannedMacros([entry], summaryFor: (_) => null);
        expect(macros.total, isNull);
        expect(macros.excluded.single.lineReason, MacroLineReason.needsWeight);
      },
    );

    test('a vocab row this device cannot see leaves the name AND the '
        'nutrition null — a different answer from a stub', () async {
      await _insertIngredient(db, 'i1', 'Protein bar');
      await repo.addIngredientEntry(
        weekStart: _thisWeek,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const [],
        quantity: 60,
        unit: g,
      );
      await db.execute(
        "UPDATE ingredient SET deleted_at = '2026-01-01T00:00:00Z' "
        "WHERE id = 'i1'",
      );
      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.ingredientName, isNull);
      expect(entry.nutrition, isNull);
      expect(entry.isIngredient, isTrue);
    });

    test('an unknown persisted unit stays null rather than becoming '
        'pieces', () async {
      await _insertIngredient(db, 'i1', 'Protein bar');
      await repo.addIngredientEntry(
        weekStart: _thisWeek,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const [],
        quantity: 2,
        unit: g,
      );
      await db.execute("UPDATE plan_entry SET unit = 'scoop'");
      final entry = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(entry.unit, isNull);
    });

    test('copy last week copies the snack WITH its amount', () async {
      await _insertIngredient(db, 'i1', 'Protein bar');
      await _insertMeasure(db, 'mz', 'i1', 'bar', 60);
      await repo.addIngredientEntry(
        weekStart: _lastWeek,
        dayOfWeek: 2,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const ['m1'],
        quantity: 1,
        unit: pieces,
        measureId: 'mz',
      );

      expect((await repo.copyLastWeek(_thisWeek)).meals, 1);
      final copied = (await repo.watchWeek(_thisWeek).first)!.entries.single;
      expect(copied.ingredientId, 'i1');
      expect(copied.quantity, 1);
      expect(copied.unit, pieces);
      expect(copied.measureId, 'mz');
      expect(copied.eaterIds, ['m1']);
    });

    test(
      'it is NOT in the recipe recency map — that map is for dishes',
      () async {
        await _insertIngredient(db, 'i1', 'Protein bar');
        await repo.addIngredientEntry(
          weekStart: _thisWeek,
          dayOfWeek: 1,
          mealSlot: 'Snack',
          ingredientId: 'i1',
          eaterIds: const [],
          quantity: 60,
          unit: g,
        );
        expect(await repo.watchLastPlanned().first, isEmpty);
      },
    );

    test('the week watch re-fires when the vocab row is renamed', () async {
      await _insertIngredient(db, 'i1', 'Protein bar');
      await repo.addIngredientEntry(
        weekStart: _thisWeek,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        eaterIds: const [],
        quantity: 60,
        unit: g,
      );
      final stream = StreamIterator(repo.watchWeek(_thisWeek));
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current!.entries.single.ingredientName, 'Protein bar');

      // `ingredient` is a joined table of this watch's load path, so a rename
      // must re-fire it — the unselected-LEFT-JOIN trap in person.
      await db.execute(
        "UPDATE ingredient SET canonical_name = 'Protein flapjack' "
        "WHERE id = 'i1'",
      );
      expect(await stream.moveNext(), isTrue);
      expect(stream.current!.entries.single.ingredientName, 'Protein flapjack');
    });
  });
}
