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
    repo = SqliteShoppingRepository(db, householdId: 'h');
    planning = SqlitePlanningRepository(db, householdId: 'h');
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

  test('two live entries for one ingredient merge losslessly', () async {
    // Two offline devices each touched Flour; after sync both rows are live
    // (no unique index — one would make the offline dupe fail upload). The
    // list must union both top-ups, keep the checked state, and anchor on the
    // oldest row — not keep whichever row happened to iterate last.
    await _insertRecipe(db, 'cake', 'Cake', lines: [('flour', 100, g)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'cake',
      eaterIds: ['a', 'b'],
    );
    // Simulate the merged two-device state directly (each device did a
    // find-or-create while offline).
    Future<void> insertEntry(String id, String createdAt, int checked) =>
        db.execute(
          'INSERT INTO shopping_list_entry (id, household_id, ingredient_id, '
          'checked, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [id, 'h', 'flour', checked, createdAt, createdAt],
        );
    Future<void> insertTopUp(String id, String entryId, double qty) =>
        db.execute(
          'INSERT INTO shopping_list_contribution (id, household_id, '
          'entry_id, source_type, quantity, unit, created_at, updated_at) '
          "VALUES (?, ?, ?, 'manual', ?, 'g', ?, ?)",
          [
            id,
            'h',
            entryId,
            qty,
            '2026-08-24T12:00:00Z',
            '2026-08-24T12:00:00Z',
          ],
        );
    await insertEntry('dev-a', '2026-08-24T09:00:00Z', 0);
    await insertEntry('dev-b', '2026-08-24T10:00:00Z', 1); // checked on B
    await insertTopUp('top-a', 'dev-a', 50);
    await insertTopUp('top-b', 'dev-b', 25);

    final flour =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(flour.entryId, 'dev-a'); // oldest row is canonical
    expect(flour.checked, isTrue); // any-checked survives the merge
    expect(flour.totals.single.amount, 175); // 100 + 50 + 25 — nothing lost
    expect(
      flour.contributions.where((c) => c.source == ContributionSource.manual),
      hasLength(2),
    );

    // A write folds the duplicates into the canonical row (lossless: the
    // dupe's contributions are re-pointed, checked propagated, dupe
    // tombstoned) so every device converges on one entry.
    await repo.addTopUp(ingredientId: 'flour', quantity: 10, unit: g);
    final live = await db.getAll(
      'SELECT id, checked FROM shopping_list_entry '
      "WHERE ingredient_id = 'flour' AND deleted_at IS NULL",
    );
    expect(live.map((r) => r['id']), ['dev-a']);
    expect(live.single['checked'], 1);
    final contribs = await db.getAll(
      'SELECT entry_id FROM shopping_list_contribution '
      'WHERE deleted_at IS NULL',
    );
    expect(contribs.map((r) => r['entry_id']).toSet(), {'dev-a'});
    final merged =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(merged.totals.single.amount, 185); // 100 + 50 + 25 + 10
  });

  test('an unknown persisted unit is a note, never summed as pieces', () async {
    await _insertIngredient(db, 'spice', 'Mystery Spice', 'pantry', 'g');
    final now = DateTime.now().toUtc().toIso8601String();
    await _insertRecipe(db, 'stew', 'Stew', lines: [('spice', 100, g)]);
    // A line persisted with a unit id this build doesn't know (schema drift /
    // newer app wrote it).
    await db.execute(
      'INSERT INTO recipe_line_item (id, household_id, group_id, '
      'ingredient_id, quantity, unit, sort_order, created_at, updated_at) '
      "VALUES ('stew-li9', 'h', 'stew-g', 'spice', 2, 'scoop', 9, ?, ?)",
      [now, now],
    );
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'stew',
      eaterIds: ['a', 'b'],
    );

    final item =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    // Only the honest 100 g total — no invented "2 pieces" line.
    expect(item.totals.single.amount, 100);
    expect(item.totals.single.unit, g);
    expect(
      item.contributions.map((c) => c.label),
      anyElement(contains('unrecognised unit "scoop"')),
    );
  });

  test('the watch re-fires on an ingredient vocab change', () async {
    await _insertRecipe(db, 'cake', 'Cake', lines: [('flour', 100, g)]);
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'cake',
      eaterIds: ['a', 'b'],
    );

    final lists = repo.watchShoppingList(_week);
    final updated = lists.firstWhere(
      (l) =>
          l.groups.any((g) => g.items.any((i) => i.name == 'Bread Flour')) &&
          l.groups.first.label == 'Grains',
    );
    // The vocab row changes (name + aisle) with no shopping-table write; the
    // list must still re-derive — `ingredient` is part of the watch set.
    await db.execute(
      "UPDATE ingredient SET canonical_name = 'Bread Flour', "
      "category = 'grains' WHERE id = 'flour'",
    );
    await updated.timeout(const Duration(seconds: 5));
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

  test('a measure line sums in basis_amount, with a whole-unit hint', () async {
    // "3 × onion, medium (110 g)" scaled ×0.75 → 2.25 onions = 247.5 g, and
    // the count food's line offers the honest "buy 3" hint (step 7.6).
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      ['m-onion', 'h', 'onion', 'onion, medium', 110],
    );
    await _insertRecipe(
      db,
      'curry',
      'Curry',
      servings: 4,
      lines: [('onion', 3, pieces)],
    );
    await db.execute(
      "UPDATE recipe_line_item SET measure_id = 'm-onion' "
      "WHERE id = 'curry-li0'",
    );
    // 3 portions of a serves-4 recipe → ×0.75.
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a'],
      portions: 3,
    );

    final list = await repo.watchShoppingList(_week).first;
    final onion = list.groups.single.items.single;
    expect(onion.totals.single.unit.family, UnitFamily.mass);
    expect(onion.totals.single.amount, closeTo(2.25 * 110, 1e-9));
    final line = onion.contributions.single;
    expect(line.measure?.label, 'onion, medium');
    expect(line.quantity, closeTo(2.25, 1e-9));
    expect(onion.wholeUnitHint, isNotNull);
    expect(onion.wholeUnitHint!.buy, 3);
    expect(onion.wholeUnitHint!.unitLabel, 'onion, medium');
  });

  test('a measure top-up persists measure_id and resolves in the '
      'list', () async {
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      ['m-onion', 'h', 'onion', 'onion, medium', 110],
    );
    await repo.addTopUp(
      ingredientId: 'onion',
      quantity: 2,
      unit: pieces,
      measureId: 'm-onion',
    );

    final row = await db.get(
      'SELECT unit, measure_id FROM shopping_list_contribution',
    );
    expect(row['measure_id'], 'm-onion');
    expect(row['unit'], 'piece'); // the honest count fallback

    final list = await repo.watchShoppingList(_week).first;
    final onion = list.groups.single.items.single;
    expect(onion.totals.single.amount, closeTo(220, 1e-9));
    expect(onion.contributions.single.measure?.label, 'onion, medium');
  });

  test('a missing measure row degrades a top-up to an honest count', () async {
    // measure_id points at a row that never synced: the stored count unit
    // stands in — never invented grams (invariant 3).
    await repo.addTopUp(
      ingredientId: 'onion',
      quantity: 2,
      unit: pieces,
      measureId: 'm-ghost',
    );
    final list = await repo.watchShoppingList(_week).first;
    final onion = list.groups.single.items.single;
    expect(onion.totals.single.unit, pieces);
    expect(onion.totals.single.amount, 2);
  });

  test('an unresolved measure_id survives an edit round-trip (never '
      'wiped)', () async {
    // Mirror of the recipe repo's unresolved-measure test: the measure row
    // hasn't synced, the user edits the top-up's quantity, and the FK must
    // come through the load → edit → save cycle intact — a re-save that
    // wrote NULL would destroy the reference for every device (review A1).
    await repo.addTopUp(
      ingredientId: 'onion',
      quantity: 2,
      unit: pieces,
      measureId: 'm-ghost',
    );
    final list = await repo.watchShoppingList(_week).first;
    final line = list.groups.single.items.single.contributions.single;
    expect(line.measure, isNull); // unresolved…
    expect(line.measureId, 'm-ghost'); // …but the raw id rides along

    // The edit sheet re-saves with the loaded contribution's id preserved.
    await repo.editContribution(
      contributionId: line.contributionId!,
      quantity: 3,
      unit: pieces,
      measureId: line.measureId,
    );
    final row = await db.get(
      'SELECT quantity, measure_id FROM shopping_list_contribution '
      'WHERE deleted_at IS NULL',
    );
    expect(row['quantity'], 3);
    expect(row['measure_id'], 'm-ghost');
  });

  test('an unrecognised unit beside a resolvable measure is a note, not an '
      'unscaled mass', () async {
    // Weird-but-possible row: unit is an unknown string AND measure_id
    // resolves. The quantity's semantics are unknown and it can't be scaled,
    // so folding it through the measure's gram weight would sum an invented
    // (and unscaled) number — it must surface like any unrecognised unit.
    await _insertIngredient(db, 'spud', 'Potato', 'produce', 'piece');
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      ['m-spud', 'h', 'spud', 'potato, medium', 213],
    );
    await _insertRecipe(
      db,
      'stew',
      'Stew',
      servings: 4,
      lines: [('spud', 100, g)],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO recipe_line_item (id, household_id, group_id, '
      'ingredient_id, quantity, unit, measure_id, sort_order, created_at, '
      "updated_at) VALUES ('stew-li9', 'h', 'stew-g', 'spud', 2, 'scoop', "
      "'m-spud', 9, ?, ?)",
      [now, now],
    );
    // 3 portions of a serves-4 recipe → ×0.75 (so an unscaled leak differs
    // from the honest number).
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'stew',
      eaterIds: ['a'],
      portions: 3,
    );

    final item =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    // Only the honest scaled 75 g — never 75 + 2 × 213 unscaled grams.
    expect(item.totals.single.amount, closeTo(75, 1e-9));
    expect(
      item.contributions.map((c) => c.label),
      anyElement(contains('unrecognised unit "scoop"')),
    );
  });

  test('a recognised non-count unit beside a measure is a note, never '
      'invented mass', () async {
    // The other two-thirds of the invented-mass leak (review N2): a measure
    // row stores a count unit by design, so 'g' or 'to_taste' beside a
    // resolving measure_id is contradictory data. It must surface as a
    // visible note — never 500 g folding to 500 × 213 g, and never an
    // imprecise line folding to a hard 213 g that ignored the session scale.
    await _insertIngredient(db, 'spud', 'Potato', 'produce', 'piece');
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      ['m-spud', 'h', 'spud', 'potato, medium', 213],
    );
    await _insertRecipe(
      db,
      'stew',
      'Stew',
      servings: 4,
      lines: [('spud', 100, g)],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    const contradictory = [('li-g', 500.0, 'g'), ('li-t', 1.0, 'to_taste')];
    for (final (id, qty, unit) in contradictory) {
      await db.execute(
        'INSERT INTO recipe_line_item (id, household_id, group_id, '
        'ingredient_id, quantity, unit, measure_id, sort_order, created_at, '
        "updated_at) VALUES (?, 'h', 'stew-g', 'spud', ?, ?, 'm-spud', 9, "
        '?, ?)',
        [id, qty, unit, now, now],
      );
    }
    // 3 portions of a serves-4 recipe → ×0.75.
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'stew',
      eaterIds: ['a'],
      portions: 3,
    );

    final item =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    // Only the clean line's scaled 75 g stands: the contradictory rows are
    // not counted at all (not in the basis fold, not as measure counts) —
    // says why, and the user fixes the line rather than trusting a guess.
    expect(item.totals.single.amount, closeTo(75, 1e-9));
    final labels = item.contributions.map((c) => c.label).join('\n');
    expect(labels, contains('measure beside non-count unit "g"'));
    expect(labels, contains('measure beside non-count unit "to taste"'));
  });
}
