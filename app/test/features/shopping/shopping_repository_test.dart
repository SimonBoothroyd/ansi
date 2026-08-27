import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/planning/data/planning_repository_impl.dart';
import 'package:mise/features/shopping/data/shopping_repository_impl.dart';
import 'package:mise/features/shopping/domain/shopping.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

final _week = DateTime.utc(2026, 8, 24); // a Monday

Future<void> _insertIngredient(
  PowerSyncDatabase db,
  String id,
  String name,
  String category,
  String defaultUnit, {
  double? density,
}) async {
  await db.execute(
    'INSERT INTO ingredient (id, household_id, canonical_name, category, '
    'default_unit, density_g_per_ml, status, source, match_text) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [id, 'h', name, category, defaultUnit, density, 'complete', 'seed', name],
  );
}

/// Inserts a recipe with one group of line items ([(ingredientId, qty, unit)]).
Future<void> _insertRecipe(
  PowerSyncDatabase db,
  String id,
  String title, {
  required List<(String, double, Unit)> lines,
  double servings = 2,
  int? keepsForDays,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, '
    'keeps_for_days, freezable, freezer_days, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?)',
    [id, 'h', title, servings, keepsForDays, null, now, now],
  );
  final groupId = '$id-g';
  await db.execute(
    'INSERT INTO ingredient_group (id, household_id, recipe_id, name, '
    'sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, 0, ?, ?)',
    [groupId, 'h', id, null, now, now],
  );
  for (var i = 0; i < lines.length; i++) {
    final (ingredientId, qty, unit) = lines[i];
    await db.execute(
      'INSERT INTO recipe_line_item (id, household_id, group_id, '
      'ingredient_id, quantity, unit, sort_order, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      ['$id-li$i', 'h', groupId, ingredientId, qty, unit.id, i, now, now],
    );
  }
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteShoppingRepository repo;
  late SqlitePlanningRepository planning;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteShoppingRepository(db);
    planning = SqlitePlanningRepository(db);
    await _insertIngredient(db, 'onion', 'Yellow onion', 'produce', 'piece');
    await _insertIngredient(db, 'flour', 'Flour', 'baking', 'g');
  });

  tearDown(() => closeTestDb(db, dir));

  test('an unplanned, untouched week is an empty list', () async {
    expect((await repo.watchShoppingList(_week).first).isEmpty, isTrue);
  });

  test('sums a recipe’s lines into aisle-grouped items, scaled', () async {
    await _insertRecipe(
      db,
      'curry',
      'Curry',
      keepsForDays: 3,
      lines: [('onion', 3, pieces), ('flour', 100, g)],
    );
    // portions override 4 on a 2-serving recipe → ×2 scale.
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a', 'b'],
      portions: 4,
    );

    final list = await repo.watchShoppingList(_week).first;
    expect(list.groups.map((g) => g.label), ['Produce', 'Baking']);
    final onion = list.groups.first.items.single;
    expect(onion.name, 'Yellow onion');
    expect(onion.totals.single.amount, 6); // 3 × 2
    final flour = list.groups.last.items.single;
    expect(flour.totals.single.amount, 200); // 100 g × 2
  });

  test('merges a shared ingredient across recipes with provenance', () async {
    await _insertRecipe(db, 'curry', 'Curry', lines: [('onion', 3, pieces)]);
    await _insertRecipe(db, 'ragu', 'Ragù', lines: [('onion', 2, pieces)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a', 'b'],
    );
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 1,
      mealSlot: 'Dinner',
      recipeId: 'ragu',
      eaterIds: ['a', 'b'],
    );

    final onion =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(onion.totals.single.amount, 5); // 3 + 2
    expect(onion.contributions, hasLength(2));
    expect(onion.hasBreakdown, isTrue);
  });

  test('check-off lazily creates a persisted entry', () async {
    await _insertRecipe(db, 'curry', 'Curry', lines: [('onion', 3, pieces)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a'],
    );

    await repo.setIngredientChecked(ingredientId: 'onion', checked: true);
    final onion =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(onion.checked, isTrue);
    expect(onion.entryId, isNotNull);

    // One entry only — a second check-off updates in place (find-or-create).
    await repo.setIngredientChecked(ingredientId: 'onion', checked: false);
    final count = await db.get(
      'SELECT count(*) AS c FROM shopping_list_entry WHERE deleted_at IS NULL',
    );
    expect(count['c'], 1);
  });

  test('a manual top-up adds to the total and the breakdown', () async {
    await _insertRecipe(db, 'cake', 'Cake', lines: [('flour', 100, g)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'cake',
      eaterIds: ['a', 'b'],
    );

    await repo.addTopUp(ingredientId: 'flour', quantity: 50, unit: g);
    final flour =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(flour.totals.single.amount, 150); // 100 + 50
    expect(
      flour.contributions.where((c) => c.source == ContributionSource.manual),
      hasLength(1),
    );
  });

  test('a manual top-up can be edited and removed on its own', () async {
    await _insertRecipe(db, 'cake', 'Cake', lines: [('flour', 100, g)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'cake',
      eaterIds: ['a', 'b'],
    );
    await repo.addTopUp(ingredientId: 'flour', quantity: 50, unit: g);

    var item =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    final manual = item.contributions.firstWhere(
      (c) => c.source == ContributionSource.manual,
    );
    expect(manual.contributionId, isNotNull);

    // Edit: 50 → 200 g, so the total becomes 100 + 200.
    await repo.editContribution(
      contributionId: manual.contributionId!,
      quantity: 200,
      unit: g,
    );
    item =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(item.totals.single.amount, 300);

    // Remove just the top-up: the cook contribution (and the entry) remain.
    await repo.removeContribution(contributionId: manual.contributionId!);
    item =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(item.totals.single.amount, 100);
    expect(
      item.contributions.where((c) => c.source == ContributionSource.manual),
      isEmpty,
    );
  });

  test('a free-text item lands in Non-food and can be checked off', () async {
    await repo.addFreeTextItem(text: 'Paper towels');
    var list = await repo.watchShoppingList(_week).first;
    final group = list.groups.single;
    expect(group.label, 'Non-food');
    final item = group.items.single;
    expect(item.name, 'Paper towels');
    expect(item.isFreeText, isTrue);
    expect(item.totals, isEmpty);

    await repo.setEntryChecked(entryId: item.entryId!, checked: true);
    list = await repo.watchShoppingList(_week).first;
    expect(list.groups.single.items.single.checked, isTrue);

    await repo.removeEntry(entryId: item.entryId!);
    expect((await repo.watchShoppingList(_week).first).isEmpty, isTrue);
  });

  test('a deleted recipe drops a checked ingredient', () async {
    await _insertRecipe(db, 'curry', 'Curry', lines: [('onion', 3, pieces)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a'],
    );
    await repo.setIngredientChecked(ingredientId: 'onion', checked: true);
    expect((await repo.watchShoppingList(_week).first).groups, isNotEmpty);

    // Soft-delete the recipe: its cook contribution vanishes, and the checked
    // entry has no manual top-up, so the line drops off (lifecycle, 0006 SQL).
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'UPDATE recipe SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, 'curry'],
    );
    expect((await repo.watchShoppingList(_week).first).isEmpty, isTrue);
  });
}
