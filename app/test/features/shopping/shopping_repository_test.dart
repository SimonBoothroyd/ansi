import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/shopping/data/shopping_repository_impl.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

final _week = DateTime.utc(2026, 8, 24); // a Monday

/// The week a Sunday-start household is standing in on the same Saturday:
/// Sun 23 Aug – Sat 29 Aug.
final _weekSunday = DateTime.utc(2026, 8, 23);

Future<void> _insertIngredient(
  PowerSyncDatabase db,
  String id,
  String name,
  String category,
  String defaultUnit, {
  double? density,
  double? pieceWeight,
}) async {
  await db.execute(
    'INSERT INTO ingredient (id, household_id, canonical_name, category, '
    'default_unit, density_g_per_ml, piece_basis_amount, status, source, '
    'match_text) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      'h',
      name,
      category,
      defaultUnit,
      density,
      pieceWeight,
      'complete',
      'seed',
      name,
    ],
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

/// Adds a component line ("¼ cup of [subRecipeId]") to [recipeId] in its own
/// group — plain INSERTs, because the local tables are VIEWS (no UPSERT).
Future<void> _insertComponentLine(
  PowerSyncDatabase db,
  String recipeId,
  String subRecipeId, {
  double? quantity = 0.25,
  Unit unit = cup,
  bool optional = false,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final groupId = '$recipeId-cg-$subRecipeId';
  await db.execute(
    'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
    'created_at, updated_at) VALUES (?, ?, ?, 1, ?, ?)',
    [groupId, 'h', recipeId, now, now],
  );
  await db.execute(
    'INSERT INTO recipe_line_item (id, household_id, group_id, sub_recipe_id, '
    'quantity, unit, optional, sort_order, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)',
    [
      '$recipeId-cli-$subRecipeId',
      'h',
      groupId,
      subRecipeId,
      quantity,
      unit.id,
      if (optional) 1 else 0,
      now,
      now,
    ],
  );
}

/// "makes [qty] [unit]" on [id].
Future<void> _setYield(
  PowerSyncDatabase db,
  String id,
  double qty,
  Unit unit,
) => db.execute(
  'UPDATE recipe SET yield_qty = ?, yield_unit = ? WHERE id = ?',
  [qty, unit.id, id],
);

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

  test('the list scales by the same fractional demand the cook plan derives '
      '(shopping otherwise untouched)', () async {
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
    await _insertRecipe(db, 'curry', 'Curry', lines: [('flour', 100, g)]);
    // 1 + ¾ eaters of a 2-serving recipe → ×0.875.
    await planning.addEntry(
      weekStart: _week,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'curry',
      eaterIds: ['a', 'b'],
    );
    final list = await repo.watchShoppingList(_week).first;
    final flour = list.groups.single.items.single;
    expect(flour.totals.single.amount, closeTo(87.5, 1e-9));
  });

  test(
    'an optional line is left off the list, and its recipe says which',
    () async {
      await _insertIngredient(db, 'lime', 'Lime', 'produce', 'piece');
      await _insertRecipe(
        db,
        'curry',
        'Curry',
        lines: [('onion', 3, pieces), ('lime', 1, pieces)],
      );
      await db.execute(
        'UPDATE recipe_line_item SET optional = 1 WHERE id = ?',
        ['curry-li1'],
      );
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: ['a', 'b'],
      );

      final list = await repo.watchShoppingList(_week).first;
      // No lime item anywhere — and no invented quantity in its place.
      expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
        'onion',
      ]);
      final echo = list.optionalLines.single;
      expect(echo.recipeId, 'curry');
      expect(echo.recipeTitle, 'Curry');
      expect(echo.names, ['Lime']);
    },
  );

  // --- A line at a RETIRED ingredient (0041's incident, from the aisle) -----

  group('an ingredient the household retired', () {
    Future<void> retire(String id) => db.execute(
      'UPDATE ingredient SET deleted_at = ? WHERE id = ?',
      [DateTime.now().toUtc().toIso8601String(), id],
    );

    Future<void> planCurry() async {
      await _insertRecipe(
        db,
        'curry',
        'Curry',
        lines: [('onion', 3, pieces), ('flour', 100, g)],
      );
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: const ['a', 'b'],
      );
    }

    test('buys nothing for the line that names it — and the list says which '
        'line, and where the pick is', () async {
      await planCurry();
      await retire('flour');

      final list = await repo.watchShoppingList(_week).first;
      // Nothing is shopped from the dead row: not its name, not its aisle,
      // not the amount the line still states.
      expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
        'onion',
      ]);
      expect(list.retiredIngredients, [
        (
          heading: 'Curry',
          ingredientName: 'Flour',
          site: RetiredIngredientSite.recipeLine,
        ),
      ]);
      // The echo is not the optional one: a defect is not a rule somebody
      // chose, and the two channels do not borrow each other's words.
      expect(list.optionalLines, isEmpty);
    });

    test('a week that is whole carries no echo', () async {
      await planCurry();
      expect(
        (await repo.watchShoppingList(_week).first).retiredIngredients,
        isEmpty,
      );
    });

    test('the week re-pointing the line repairs it — the new thing is bought '
        'and nothing is left to say', () async {
      await planCurry();
      await retire('flour');
      final variants = SqliteWeekVariantRepository(db, householdId: 'h');
      await variants.saveOverrides(
        _week,
        'curry',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'curry-li1',
            ingredientId: 'onion',
            quantity: 2,
            unit: pieces,
          ),
        ],
      );

      final list = await repo.watchShoppingList(_week).first;
      expect(list.retiredIngredients, isEmpty);
      final onion = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'onion');
      expect(onion.totals.single.amount, 5); // 3 + the week's 2
      expect(
        onion.contributions.map((c) => c.label).join('|'),
        contains('this week, for Flour'),
      );
    });
  });

  group("this week's variant reaches the aisle", () {
    /// The week's meal, and a variant repository pointed at the same database.
    Future<SqliteWeekVariantRepository> planRagu() async {
      await _insertRecipe(
        db,
        'ragu',
        'Ragù',
        lines: [('onion', 2, pieces), ('flour', 100, g)],
      );
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'ragu',
        eaterIds: ['a', 'b'],
      );
      return SqliteWeekVariantRepository(db, householdId: 'h');
    }

    test('an amount changed for the week is bought, and says why', () async {
      final variants = await planRagu();
      await variants.saveOverrides(
        _week,
        'ragu',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'ragu-li0',
            ingredientId: 'onion',
            quantity: 3,
            unit: pieces,
          ),
        ],
      );

      final list = await repo.watchShoppingList(_week).first;
      final onion = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'onion');
      // 3 per the week's line, on a 2-serving recipe cooked for 2 → ×1.
      expect(onion.totals.single.amount, 3);
      expect(onion.contributions.single.label, contains('this week, was 2'));
    });

    test('a swap buys the new thing, and names the old one', () async {
      final variants = await planRagu();
      await variants.saveOverrides(
        _week,
        'ragu',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'ragu-li1',
            ingredientId: 'onion',
            quantity: 100,
            unit: g,
          ),
        ],
      );

      final list = await repo.watchShoppingList(_week).first;
      final ids = list.groups.expand((g) => g.items).map((i) => i.ingredientId);
      expect(ids, isNot(contains('flour')));
      final onion = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'onion');
      expect(
        onion.contributions.map((c) => c.label).join('|'),
        contains('this week, for Flour'),
      );
    });

    test('an added line is bought and marked as added', () async {
      final variants = await planRagu();
      await variants.saveOverrides(
        _week,
        'ragu',
        overrides: const [
          LineOverride(
            id: 'ov-flour',
            action: LineOverrideAction.add,
            ingredientId: 'flour',
            quantity: 50,
            unit: g,
            sortOrder: 0,
          ),
        ],
      );

      final list = await repo.watchShoppingList(_week).first;
      final flour = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'flour');
      expect(flour.totals.single.amount, 150);
      expect(
        flour.contributions.map((c) => c.label).join('|'),
        contains('this week, added'),
      );
    });

    test(
      'an excluded line leaves the list, and is named on the echo row',
      () async {
        final variants = await planRagu();
        await variants.saveOverrides(
          _week,
          'ragu',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.exclude,
              recipeLineItemId: 'ragu-li1',
            ),
          ],
        );

        final list = await repo.watchShoppingList(_week).first;
        expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
          'onion',
        ]);
        final echo = list.optionalLines.single;
        expect(echo.reason, LineDropReason.thisWeek);
        expect(echo.recipeTitle, 'Ragù');
        expect(echo.names, ['Flour']);
      },
    );

    test('another week is untouched by it', () async {
      final variants = await planRagu();
      await variants.saveOverrides(
        _week,
        'ragu',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'ragu-li1',
          ),
        ],
      );
      await planning.addEntry(
        weekStart: _week.add(const Duration(days: 7)),
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'ragu',
        eaterIds: ['a', 'b'],
      );

      final next = await repo
          .watchShoppingList(_week.add(const Duration(days: 7)))
          .first;
      expect(
        next.groups.expand((g) => g.items).map((i) => i.ingredientId),
        containsAll(<String>['onion', 'flour']),
      );
      expect(next.optionalLines, isEmpty);
    });
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

    await repo.setIngredientChecked(
      ingredientId: 'onion',
      checked: true,
      weekStart: _week,
    );
    final onion =
        (await repo.watchShoppingList(_week).first).groups.single.items.single;
    expect(onion.checked, isTrue);
    expect(onion.entryId, isNotNull);

    // One entry only — a second check-off updates in place (find-or-create).
    await repo.setIngredientChecked(
      ingredientId: 'onion',
      checked: false,
      weekStart: _week,
    );
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

    await repo.addTopUp(
      ingredientId: 'flour',
      quantity: 50,
      unit: g,
      weekStart: _week,
    );
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
    await repo.addTopUp(
      ingredientId: 'flour',
      quantity: 50,
      unit: g,
      weekStart: _week,
    );

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
    await repo.addFreeTextItem(text: 'Paper towels', weekStart: _week);
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
    // Both devices stamp the same week (0018) — the convergence is WITHIN a
    // week, which is exactly what a shared list needs.
    Future<void> insertEntry(String id, String createdAt, int checked) =>
        db.execute(
          'INSERT INTO shopping_list_entry (id, household_id, ingredient_id, '
          'checked, week_start_date, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [id, 'h', 'flour', checked, '2026-08-24', createdAt, createdAt],
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
    await repo.addTopUp(
      ingredientId: 'flour',
      quantity: 10,
      unit: g,
      weekStart: _week,
    );
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
    await repo.setIngredientChecked(
      ingredientId: 'onion',
      checked: true,
      weekStart: _week,
    );
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

  test('a measure line is counted in its measure, and weighs its '
      'basis_amount', () async {
    // "3 × onion, medium (110 g)" scaled ×0.75 → 2.25 onions, which weigh
    // 247.5 g.
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
    // One measure asked for, so the row is counted in it — and the count
    // already says "2.25 onions", which is what the round-up hint used to
    // reconstruct from grams.
    expect(onion.measureTotal!.measure.label, 'onion, medium');
    expect(onion.measureTotal!.amount, closeTo(2.25, 1e-9));
    expect(onion.wholeUnitHint, isNull);
  });

  test('a piece line on a piece-weighted row folds through the weight, and '
      'the row is bought in pieces', () async {
    // The live repro: "1 lime, whole" in the curry, "1½ piece" in the salad.
    // Lime's row says a piece is 67 g (the weight the measure lent it), so
    // the two are 2½ limes — never "67 g + 1½ piece".
    await _insertIngredient(
      db,
      'lime',
      'Lime',
      'produce',
      'piece',
      pieceWeight: 67,
    );
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      ['m-lime', 'h', 'lime', 'lime, whole', 67],
    );
    await _insertRecipe(db, 'curry', 'Curry', lines: [('lime', 1, pieces)]);
    await db.execute(
      "UPDATE recipe_line_item SET measure_id = 'm-lime' "
      "WHERE id = 'curry-li0'",
    );
    await _insertRecipe(db, 'salad', 'Salad', lines: [('lime', 1.5, pieces)]);
    for (final (day, recipe) in [(0, 'curry'), (2, 'salad')]) {
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: day,
        mealSlot: 'Dinner',
        recipeId: recipe,
        eaterIds: ['a', 'b'],
      );
    }

    final list = await repo.watchShoppingList(_week).first;
    final lime = list.groups.single.items.single;
    expect(lime.totals.single.unit, g);
    expect(lime.totals.single.amount, closeTo(167.5, 1e-9));
    expect(lime.pieceTotal, isNotNull);
    expect(lime.pieceTotal!.count, closeTo(2.5, 1e-9));
    expect(lime.pieceTotal!.approx, isFalse);
    expect(lime.measureTotal, isNull);
    expect(lime.wholeUnitHint, isNull);
    // The lines keep their own words.
    expect(lime.contributions.first.measure?.label, 'lime, whole');
    expect(lime.contributions.last.unit, pieces);
    expect(lime.contributions.last.quantity, closeTo(1.5, 1e-9));
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
      weekStart: _week,
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
      weekStart: _week,
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
      weekStart: _week,
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

  test('a recognised non-count unit beside a measure is a note, never invented '
      'mass', () async {
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

  group('nested recipes', () {
    /// Sliders (serves 1) with 500 g flour and ¼ cup of the aioli; the aioli
    /// (makes 1 cup) is 240 g of almonds.
    Future<void> seed({bool withYield = true, bool optional = false}) async {
      await _insertIngredient(db, 'almonds', 'Almonds', 'pantry', 'g');
      await _insertRecipe(
        db,
        'sliders',
        'Sausage Sliders',
        servings: 1,
        lines: [('flour', 500, g)],
      );
      await _insertRecipe(
        db,
        'aioli',
        'Romesco Aioli',
        servings: 4,
        keepsForDays: 5,
        lines: [('almonds', 240, g)],
      );
      if (withYield) await _setYield(db, 'aioli', 1, cup);
      await _insertComponentLine(db, 'sliders', 'aioli', optional: optional);
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 5,
        mealSlot: 'Dinner',
        recipeId: 'sliders',
        eaterIds: ['a'],
      );
    }

    test("the sub-recipe's ingredients contribute, scaled by the batch factor, "
        'with provenance naming both levels', () async {
      await seed();
      final list = await repo.watchShoppingList(_week).first;
      final almonds = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'almonds');
      // 240 g × ¼ batch.
      expect(almonds.totals.single.amount, closeTo(60, 1e-9));
      expect(
        almonds.contributions.single.label,
        'Romesco Aioli · for Sausage Sliders · cook Sat',
      );
    });

    test('the component LINE itself never becomes an item — you buy almonds, '
        'not aioli', () async {
      await seed();
      final list = await repo.watchShoppingList(_week).first;
      final names = list.groups.expand((g) => g.items).map((i) => i.name);
      expect(names, isNot(contains('Romesco Aioli')));
      expect(names, containsAll(['Flour', 'Almonds']));
    });

    test('an unresolved component contributes NOTHING, and the echo names the '
        'parent that is short', () async {
      await seed(withYield: false);
      final list = await repo.watchShoppingList(_week).first;
      expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
        'flour',
      ]);
      expect(list.unresolvedComponents, [
        (recipeId: 'sliders', recipeTitle: 'Sausage Sliders', count: 1),
      ]);
    });

    test('a resolved week carries no echo', () async {
      await seed();
      expect(
        (await repo.watchShoppingList(_week).first).unresolvedComponents,
        isEmpty,
      );
    });

    test('an ingredient used at both levels sums into one line', () async {
      await _insertRecipe(
        db,
        'sliders',
        'Sausage Sliders',
        servings: 1,
        lines: [('flour', 100, g)],
      );
      await _insertRecipe(
        db,
        'aioli',
        'Romesco Aioli',
        servings: 4,
        keepsForDays: 5,
        lines: [('flour', 200, g)],
      );
      await _setYield(db, 'aioli', 1, cup);
      await _insertComponentLine(db, 'sliders', 'aioli', quantity: 0.5);
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 5,
        mealSlot: 'Dinner',
        recipeId: 'sliders',
        eaterIds: ['a'],
      );

      final list = await repo.watchShoppingList(_week).first;
      final flour = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'flour');
      // 100 g direct + 200 g × ½ batch.
      expect(flour.totals.single.amount, closeTo(200, 1e-9));
      expect(flour.contributions, hasLength(2));
    });

    test('scaling the parent scales the nested contribution too', () async {
      await seed();
      await planning.addEntry(
        weekStart: _week,
        dayOfWeek: 5,
        mealSlot: 'Lunch',
        recipeId: 'sliders',
        eaterIds: ['a'],
      );
      final list = await repo.watchShoppingList(_week).first;
      final almonds = list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'almonds');
      // Two portions of a serves-1 recipe → ×2 → ½ batch of the aioli.
      expect(almonds.totals.single.amount, closeTo(120, 1e-9));
    });

    group("an OPTIONAL sub-recipe is the week's decision", () {
      test('with no include row it buys nothing, and the echo names it by '
          'title', () async {
        await seed(optional: true);
        final list = await repo.watchShoppingList(_week).first;
        expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
          'flour',
        ]);
        final echo = list.optionalLines.single;
        expect(echo.recipeId, 'sliders');
        expect(echo.recipeTitle, 'Sausage Sliders');
        expect(echo.names, ['Romesco Aioli']);
        expect(echo.lineIds, ['sliders-cli-aioli']);
        expect(echo.reason, LineDropReason.optional);
      });

      test("ticking it in buys the sub-recipe's ingredients, and the echo "
          'goes', () async {
        await seed(optional: true);
        await SqliteWeekVariantRepository(db, householdId: 'h').setLineIncluded(
          _week,
          'sliders',
          'sliders-cli-aioli',
          included: true,
        );

        final list = await repo.watchShoppingList(_week).first;
        final almonds = list.groups
            .expand((g) => g.items)
            .firstWhere((i) => i.ingredientId == 'almonds');
        expect(almonds.totals.single.amount, closeTo(60, 1e-9));
        expect(list.optionalLines, isEmpty);
      });
    });
  });

  group('the overlay is scoped to a week', () {
    final nextWeek = DateTime.utc(2026, 8, 31);

    /// Plans one Curry meal on [week] so the ingredient is derived onto that
    /// week's list and can be ticked.
    Future<void> planCurryOn(DateTime week) async {
      await planning.addEntry(
        weekStart: week,
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: ['a', 'b'],
      );
    }

    setUp(() async {
      await _insertRecipe(
        db,
        'curry',
        'Curry',
        lines: [('onion', 2, pieces), ('flour', 100, g)],
      );
    });

    bool checkedOn(ShoppingList list, String ingredientId) => list.groups
        .expand((g) => g.items)
        .firstWhere((i) => i.ingredientId == ingredientId)
        .checked;

    test('a check-off belongs to the week it was made on', () async {
      await planCurryOn(_week);
      await planCurryOn(nextWeek);

      await repo.setIngredientChecked(
        ingredientId: 'onion',
        checked: true,
        weekStart: _week,
      );

      expect(
        checkedOn(await repo.watchShoppingList(_week).first, 'onion'),
        isTrue,
      );
      // The same ingredient on the OTHER week is untouched — the whole point
      // of the column.
      expect(
        checkedOn(await repo.watchShoppingList(nextWeek).first, 'onion'),
        isFalse,
      );

      final row = await db.get(
        'SELECT week_start_date FROM shopping_list_entry '
        "WHERE ingredient_id = 'onion'",
      );
      expect(row['week_start_date'], '2026-08-24');
    });

    test('a top-up lands on one week only', () async {
      await planCurryOn(_week);
      await planCurryOn(nextWeek);
      await repo.addTopUp(
        ingredientId: 'flour',
        quantity: 50,
        unit: g,
        weekStart: nextWeek,
      );

      double flourOn(ShoppingList list) => list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.ingredientId == 'flour')
          .totals
          .single
          .amount;

      // Two portions of a serves-2 recipe → x1 → 100 g derived on each week;
      // only next week also carries the manual 50 g.
      expect(flourOn(await repo.watchShoppingList(_week).first), 100);
      expect(flourOn(await repo.watchShoppingList(nextWeek).first), 150);
    });

    test('two touches on the same week converge on one entry', () async {
      await planCurryOn(_week);
      await repo.setIngredientChecked(
        ingredientId: 'onion',
        checked: true,
        weekStart: _week,
      );
      await repo.addTopUp(
        ingredientId: 'onion',
        quantity: 1,
        unit: pieces,
        weekStart: _week,
      );
      final rows = await db.getAll(
        'SELECT id FROM shopping_list_entry '
        "WHERE ingredient_id = 'onion' AND deleted_at IS NULL",
      );
      expect(rows, hasLength(1));
    });

    Iterable<String> namesOn(ShoppingList list) =>
        list.groups.expand((g) => g.items).map((i) => i.name);

    test('a free-text item belongs to the week it was added on', () async {
      await repo.addFreeTextItem(text: 'Paper towels', weekStart: _week);

      final row = await db.get(
        'SELECT week_start_date FROM shopping_list_entry '
        "WHERE free_text = 'Paper towels'",
      );
      expect(row['week_start_date'], '2026-08-24');

      expect(
        namesOn(await repo.watchShoppingList(_week).first),
        contains('Paper towels'),
      );
      expect(
        namesOn(await repo.watchShoppingList(nextWeek).first),
        isNot(contains('Paper towels')),
        reason: 'you added it while shopping for one week, not for every week',
      );
    });

    test('a free-text check-off is per week, because its entry is', () async {
      await repo.addFreeTextItem(text: 'Paper towels', weekStart: _week);
      await repo.addFreeTextItem(text: 'Paper towels', weekStart: nextWeek);

      bool towelsCheckedOn(ShoppingList list) => list.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.name == 'Paper towels')
          .checked;

      final thisWeek = await repo.watchShoppingList(_week).first;
      final entryId = thisWeek.groups
          .expand((g) => g.items)
          .firstWhere((i) => i.name == 'Paper towels')
          .entryId!;
      await repo.setEntryChecked(entryId: entryId, checked: true);

      expect(
        towelsCheckedOn(await repo.watchShoppingList(_week).first),
        isTrue,
      );
      expect(
        towelsCheckedOn(await repo.watchShoppingList(nextWeek).first),
        isFalse,
        reason: 'the two weeks hold two entries, and only one was ticked',
      );
    });

    test('a free-text row with no week reads on no week', () async {
      // The shape an older client writes. The list read takes one week's rows
      // and nothing else, so this row is invisible here; it comes back on the
      // week it was created in once the server stamps it.
      final now = DateTime.utc(2026, 8, 26).toIso8601String();
      await db.execute(
        'INSERT INTO shopping_list_entry '
        '(id, household_id, free_text, checked, created_at, updated_at) '
        'VALUES (?, ?, ?, 0, ?, ?)',
        ['legacy-towels', 'h', 'Paper towels', now, now],
      );

      for (final week in [_week, nextWeek]) {
        expect(
          namesOn(await repo.watchShoppingList(week).first),
          isNot(contains('Paper towels')),
        );
      }
    });
  });

  // --- A meal eaten out is bought by nobody ---------------------------------

  group('a planned meal eaten OUT', () {
    test('buys nothing, and leaves the list it stands beside whole', () async {
      await _insertIngredient(db, 'bar', 'Protein bar', 'snacks', 'g');
      await planning.addOutEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Lunch',
        label: 'Office lunch',
        eaterIds: const ['a', 'b'],
      );

      expect((await repo.watchShoppingList(_week).first).groups, isEmpty);

      // Beside a snack that IS bought, the list holds exactly the snack.
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a'],
        quantity: 60,
        unit: g,
      );
      final list = await repo.watchShoppingList(_week).first;
      expect(list.groups.single.items.single.name, 'Protein bar');
      expect(
        list.groups.expand((g) => g.items).map((i) => i.name),
        isNot(contains('Office lunch')),
      );
    });
  });

  // --- A planned ingredient is bought, though nothing cooks it (8.14 / A-D4) -

  group('a planned INGREDIENT meal', () {
    setUp(() async {
      await _insertIngredient(db, 'bar', 'Protein bar', 'snacks', 'g');
      await db.execute(
        'INSERT INTO ingredient_measure (id, household_id, ingredient_id, '
        'label, basis_amount, sort_order, created_at, updated_at) '
        "VALUES ('mz', 'h', 'bar', 'bar', 60, 0, '2026-01-01', '2026-01-01')",
      );
    });

    test(
      'reaches the list from the WEEK, with no cook session at all',
      () async {
        await planning.addIngredientEntry(
          weekStart: _week,
          dayOfWeek: 1,
          mealSlot: 'Snack',
          ingredientId: 'bar',
          eaterIds: const ['a'],
          quantity: 1,
          unit: pieces,
          measureId: 'mz',
        );

        final list = await repo.watchShoppingList(_week).first;
        final item = list.groups.single.items.single;
        expect(item.name, 'Protein bar');
        expect(item.totals.single.amount, 60); // one bar, through its weight
        final c = item.contributions.single;
        expect(c.source, ContributionSource.planEntry);
        expect(c.label, 'Snack · Tue');
      },
    );

    test('a Monday household reads exactly what it always did', () async {
      // The default shape is Monday, and the repository is constructed here
      // exactly as the app constructs it for such a household — so the day a
      // breakdown line names must be byte-identical to the Monday-only code's.
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a'],
        quantity: 60,
        unit: g,
      );
      final explicit = SqliteShoppingRepository(
        db,
        householdId: 'h',
        // Stated on purpose: the assertion is that the default and an
        // explicit Monday shape are the same repository.
        // ignore: avoid_redundant_argument_values
        weekShape: WeekShape.monday,
      );
      final byDefault = (await repo.watchShoppingList(_week).first)
          .groups
          .single
          .items
          .single;
      final byShape = (await explicit.watchShoppingList(_week).first)
          .groups
          .single
          .items
          .single;
      expect(byDefault.contributions.single.label, 'Snack · Tue');
      expect(byShape.contributions.single.label, 'Snack · Tue');
      expect(byShape.totals.single.amount, byDefault.totals.single.amount);
    });

    test('a Sunday household names the same offset a day earlier', () async {
      final sunday = SqliteShoppingRepository(
        db,
        householdId: 'h',
        weekShape: WeekShape.sunday,
      );
      // Offset 0 of a Sunday-start week IS a Sunday — the meal the owner
      // shops for on shopping day, inside the week being shopped for.
      await planning.addIngredientEntry(
        weekStart: _weekSunday,
        dayOfWeek: 0,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a'],
        quantity: 60,
        unit: g,
      );
      final list = await sunday.watchShoppingList(_weekSunday).first;
      final item = list.groups.single.items.single;
      expect(item.contributions.single.label, 'Snack · Sun');
      // Offset 1 is the Monday after it, not the Tuesday a Monday week reads.
      await planning.addIngredientEntry(
        weekStart: _weekSunday,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a'],
        quantity: 60,
        unit: g,
      );
      final second = await sunday.watchShoppingList(_weekSunday).first;
      expect(
        second.groups.single.items.single.contributions
            .map((c) => c.label)
            .toSet(),
        {'Snack · Sun', 'Snack · Mon'},
      );
      // And the Monday week is untouched: a different key, a different list.
      expect((await repo.watchShoppingList(_week).first).isEmpty, isTrue);
    });

    test('two eaters buy two — the demand multiplies it (A-D3)', () async {
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a', 'b'],
        quantity: 1,
        unit: pieces,
        measureId: 'mz',
      );
      final item = (await repo.watchShoppingList(_week).first)
          .groups
          .single
          .items
          .single;
      expect(item.totals.single.amount, 120);
    });

    test(
      'a portions override wins over the eater count, as everywhere else',
      () async {
        await planning.addIngredientEntry(
          weekStart: _week,
          dayOfWeek: 1,
          mealSlot: 'Snack',
          ingredientId: 'bar',
          eaterIds: const ['a'],
          quantity: 30,
          unit: g,
          portions: 3,
        );
        final item = (await repo.watchShoppingList(_week).first)
            .groups
            .single
            .items
            .single;
        expect(item.totals.single.amount, 90);
      },
    );

    test('an entry that states no amount contributes nothing', () async {
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a'],
      );
      final item = (await repo.watchShoppingList(_week).first)
          .groups
          .single
          .items
          .single;
      expect(item.totals, isEmpty);
      expect(item.contributions.single.quantity, isNull);
    });

    test('at a RETIRED vocab row buys nothing — and does not vanish, which is '
        'what took its check-off row with it', () async {
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'bar',
        eaterIds: const ['a'],
        quantity: 60,
        unit: g,
      );
      await db.execute(
        "UPDATE ingredient SET deleted_at = '2026-01-01T00:00:00Z' "
        "WHERE id = 'bar'",
      );

      final list = await repo.watchShoppingList(_week).first;
      // Nothing to buy — a retired row has no honest name, aisle or weight.
      expect(list.isEmpty, isTrue);
      // …but the planned meal still has a row somebody can read, and its
      // pick is in the plan, not in a recipe there isn't one of.
      expect(list.retiredIngredients, [
        (
          heading: 'Snack · Tue',
          ingredientName: 'Protein bar',
          site: RetiredIngredientSite.planEntry,
        ),
      ]);
    });

    test('at a row this device has never synced still drops out silently — '
        'there is nothing to name', () async {
      await planning.addIngredientEntry(
        weekStart: _week,
        dayOfWeek: 1,
        mealSlot: 'Snack',
        ingredientId: 'never-synced',
        eaterIds: const ['a'],
        quantity: 60,
        unit: g,
      );
      final list = await repo.watchShoppingList(_week).first;
      expect(list.isEmpty, isTrue);
      expect(list.retiredIngredients, isEmpty);
    });

    test(
      'it sums into the SAME line as a recipe that uses it — bought once',
      () async {
        await _insertRecipe(
          db,
          'flapjack',
          'Flapjacks',
          lines: [('bar', 100, g)],
        );
        await planning.addEntry(
          weekStart: _week,
          dayOfWeek: 0,
          mealSlot: 'Dinner',
          recipeId: 'flapjack',
          eaterIds: const ['a', 'b'],
        );
        await planning.addIngredientEntry(
          weekStart: _week,
          dayOfWeek: 3,
          mealSlot: 'Snack',
          ingredientId: 'bar',
          eaterIds: const ['a'],
          quantity: 60,
          unit: g,
        );
        final item = (await repo.watchShoppingList(_week).first)
            .groups
            .single
            .items
            .single;
        expect(item.totals.single.amount, 160);
        expect(item.contributions.map((c) => c.source), [
          ContributionSource.cookSession,
          ContributionSource.planEntry,
        ]);
      },
    );
  });
}
