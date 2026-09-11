/// The week variant over a REAL PowerSync database — the local tables are
/// SQLite views, so a save that reached for `ON CONFLICT` would fail here the
/// way it fails on a phone.
library;

import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

final _thisWeek = DateTime.utc(2026, 9, 14);
final _nextWeek = DateTime.utc(2026, 9, 21);

String get _now => DateTime.now().toUtc().toIso8601String();

Future<void> _insertWeek(PowerSyncDatabase db, String id, String key) =>
    db.execute(
      'INSERT INTO week_plan (id, household_id, week_start_date, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?)',
      [id, 'h', key, _now, _now],
    );

Future<void> _insertRecipe(
  PowerSyncDatabase db,
  String id,
  String title, {
  double servings = 4,
}) => db.execute(
  'INSERT INTO recipe (id, household_id, title, servings_base, created_at, '
  'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
  [id, 'h', title, servings, _now, _now],
);

Future<void> _insertIngredient(
  PowerSyncDatabase db,
  String id,
  String name, {
  String? macros,
}) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
  'match_text, macros, macros_basis, status, created_at, updated_at) '
  "VALUES (?, ?, ?, 'g', ?, ?, 'per_g', ?, ?, ?)",
  [
    id,
    'h',
    name,
    name.toLowerCase(),
    macros,
    if (macros == null) 'stub' else 'complete',
    _now,
    _now,
  ],
);

Future<void> _insertGroup(PowerSyncDatabase db, String id, String recipeId) =>
    db.execute(
      'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)',
      [id, 'h', recipeId, _now, _now],
    );

Future<void> _insertLine(
  PowerSyncDatabase db,
  String id,
  String groupId,
  String ingredientId, {
  double quantity = 100,
  String unit = 'g',
  bool optional = false,
  int sortOrder = 0,
}) => db.execute(
  'INSERT INTO recipe_line_item (id, household_id, group_id, ingredient_id, '
  'quantity, unit, optional, sort_order, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    'h',
    groupId,
    ingredientId,
    quantity,
    unit,
    if (optional) 1 else 0,
    sortOrder,
    _now,
    _now,
  ],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteWeekVariantRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteWeekVariantRepository(db, householdId: 'h');
    await _insertWeek(db, 'wp-1', '2026-09-14');
    await _insertWeek(db, 'wp-2', '2026-09-21');
    await _insertRecipe(db, 'r1', 'Slow-Cooker Beef Ragù');
    await _insertRecipe(db, 'r2', 'Weeknight Chicken Curry');
    await _insertIngredient(
      db,
      'i-sausage',
      'Pork sausage',
      macros: '{"kcal":300,"protein":14,"carb":2,"fat":26}',
    );
    await _insertIngredient(
      db,
      'i-mince',
      'Beef mince',
      macros: '{"kcal":137,"protein":21,"carb":0,"fat":5}',
    );
    await _insertGroup(db, 'g1', 'r1');
    await _insertLine(db, 'l1', 'g1', 'i-sausage', quantity: 400);
    await _insertLine(db, 'l2', 'g1', 'i-mince', quantity: 500, sortOrder: 1);
  });

  tearDown(() => closeTestDb(db, dir));

  group('the set is written whole', () {
    test('nothing stored means no variant at all', () async {
      expect(await repo.loadOverrides(_thisWeek, 'r1'), isEmpty);
      expect(await repo.watchWeekOverrides(_thisWeek).first, isEmpty);
    });

    test('a set saves and reads back by week and recipe', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'l1',
            ingredientId: 'i-mince',
            quantity: 400,
            unit: g,
            note: 'browned',
          ),
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );

      final set = await repo.loadOverrides(_thisWeek, 'r1');
      expect(set, hasLength(2));
      final replace = set.firstWhere(
        (o) => o.action == LineOverrideAction.replace,
      );
      expect(replace.recipeLineItemId, 'l1');
      expect(replace.ingredientId, 'i-mince');
      // The name comes off the live vocab row, not off the stored delta.
      expect(replace.ingredientName, 'Beef mince');
      expect(replace.quantity, 400);
      expect(replace.unit, g);
      expect(replace.note, 'browned');
      expect(replace.id, isNotEmpty);
    });

    test('re-saving keeps one row per line rather than racing tombstones',
        () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'l1',
            ingredientId: 'i-mince',
            quantity: 400,
            unit: g,
          ),
        ],
      );
      final first = (await repo.loadOverrides(_thisWeek, 'r1')).single.id;

      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'l1',
            ingredientId: 'i-mince',
            quantity: 600,
            unit: g,
          ),
        ],
      );
      final second = (await repo.loadOverrides(_thisWeek, 'r1')).single;
      expect(second.id, first);
      expect(second.quantity, 600);

      final live = await db.get(
        'SELECT COUNT(*) AS n FROM week_recipe_line_override '
        "WHERE recipe_id = 'r1' AND deleted_at IS NULL",
      );
      expect(live['n'], 1);
    });

    test('an empty set is back to the recipe — every row tombstoned', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      await repo.saveOverrides(_thisWeek, 'r1', overrides: const []);
      expect(await repo.loadOverrides(_thisWeek, 'r1'), isEmpty);
      final row = await db.get(
        'SELECT deleted_at FROM week_recipe_line_override '
        "WHERE recipe_line_item_id = 'l2'",
      );
      expect(row['deleted_at'], isNotNull);
    });

    test('an added line keeps the id it was drafted with', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            id: 'ov-basil',
            action: LineOverrideAction.add,
            ingredientId: 'i-mince',
            quantity: 1,
            unit: pieces,
            sortOrder: 0,
          ),
        ],
      );
      var set = await repo.loadOverrides(_thisWeek, 'r1');
      expect(set.single.id, 'ov-basil');

      // Re-saving the same addition updates it in place.
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            id: 'ov-basil',
            action: LineOverrideAction.add,
            ingredientId: 'i-mince',
            quantity: 2,
            unit: pieces,
            sortOrder: 0,
          ),
        ],
      );
      set = await repo.loadOverrides(_thisWeek, 'r1');
      expect(set, hasLength(1));
      expect(set.single.quantity, 2);
    });

    test('the week plan is created lazily by the first change', () async {
      final unplanned = DateTime.utc(2026, 10, 5);
      await repo.saveOverrides(
        unplanned,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      final row = await db.get(
        "SELECT id FROM week_plan WHERE week_start_date = '2026-10-05'",
      );
      expect(row['id'], isNotNull);
      expect(await repo.loadOverrides(unplanned, 'r1'), hasLength(1));
    });
  });

  group('a variant never leaks', () {
    test('into another week', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      expect(await repo.loadOverrides(_nextWeek, 'r1'), isEmpty);
      expect(await repo.watchWeekOverrides(_nextWeek).first, isEmpty);
    });

    test('into another recipe', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      final byRecipe = await repo.watchWeekOverrides(_thisWeek).first;
      expect(byRecipe.keys, ['r1']);
      expect(await repo.loadOverrides(_thisWeek, 'r2'), isEmpty);
    });

    test("and saving one recipe leaves another recipe's set alone", () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      await repo.saveOverrides(_thisWeek, 'r2', overrides: const []);
      expect(await repo.loadOverrides(_thisWeek, 'r1'), hasLength(1));
    });
  });

  group("the week's own macro summaries", () {
    /// The Library's per-recipe figure — what the week keeps borrowing for
    /// every recipe it does not vary.
    Future<Macros?> libraryFigure() async {
      final summaries = await SqliteRecipeRepository(
        db,
        householdId: 'h',
      ).watchRecipes().first;
      return summaries.firstWhere((s) => s.id == 'r1').macros?.perServing;
    }

    test('a recipe with no variant is absent — the Library figure stands',
        () async {
      expect(await repo.watchVariantRecipeMacros(_thisWeek).first, isEmpty);
    });

    test("an exclusion moves this week's figure, and no other week's",
        () async {
      final library = await libraryFigure();
      expect(library, isNotNull);

      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      final varied = await repo.watchVariantRecipeMacros(_thisWeek).first;
      expect(varied.keys, ['r1']);
      expect(varied['r1']!.perServing, isNot(library));
      // And the Library's own figure has not moved: the recipe is untouched.
      expect(await libraryFigure(), library);
      expect(await repo.watchVariantRecipeMacros(_nextWeek).first, isEmpty);
    });
  });
}
