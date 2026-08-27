import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/recipes/data/recipe_repository_impl.dart';
import 'package:mise/features/recipes/domain/recipe.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Recipe _sampleRecipe() => const Recipe(
  id: 'r1',
  title: 'Weeknight Curry',
  servingsBase: 2,
  steps: ['Fry the onion', 'Add spices'],
  keepsForDays: 4,
  groups: [
    IngredientGroup(
      id: 'g1',
      name: 'For the sauce',
      items: [
        LineItem(
          id: 'i1',
          ingredientId: 'ing-onion',
          ingredientName: 'Onion',
          unit: pieces,
          quantity: 1,
        ),
        LineItem(
          id: 'i2',
          ingredientId: 'ing-salt',
          ingredientName: 'Salt',
          unit: toTaste,
        ),
      ],
    ),
    IngredientGroup(
      id: 'g2',
      items: [
        LineItem(
          id: 'i3',
          ingredientId: 'ing-rice',
          ingredientName: 'Rice',
          unit: g,
          quantity: 150,
          note: 'rinsed',
        ),
      ],
    ),
  ],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db);
    // Line-item names resolve via a join to `ingredient`, so the referenced
    // vocab rows must exist (they always do in the app — the picker only picks
    // existing ingredients).
    for (final (id, name) in const [
      ('ing-onion', 'Onion'),
      ('ing-salt', 'Salt'),
      ('ing-rice', 'Rice'),
    ]) {
      await db.execute(
        'INSERT INTO ingredient (id, household_id, canonical_name, '
        'default_unit, status, source, match_text) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, 'h', name, 'g', 'complete', 'seed', name.toLowerCase()],
      );
    }
  });

  tearDown(() => closeTestDb(db, dir));

  test('saveRecipe round-trips the full aggregate', () async {
    await repo.saveRecipe(_sampleRecipe());

    final loaded = await repo.watchRecipe('r1').first;
    expect(loaded, isNotNull);
    expect(loaded!.title, 'Weeknight Curry');
    expect(loaded.servingsBase, 2);
    expect(loaded.steps, ['Fry the onion', 'Add spices']);
    expect(loaded.keepsForDays, 4);

    expect(loaded.groups.map((g) => g.name), ['For the sauce', null]);
    expect(loaded.groups[0].items.map((i) => i.ingredientName), [
      'Onion',
      'Salt',
    ]);
    final salt = loaded.groups[0].items[1];
    expect(salt.quantity, isNull);
    expect(salt.unit, toTaste);
    final rice = loaded.groups[1].items.single;
    expect(rice.quantity, 150);
    expect(rice.unit, g);
    expect(rice.note, 'rinsed');
  });

  test('watchRecipes lists saved recipes (summaries)', () async {
    await repo.saveRecipe(_sampleRecipe());
    await repo.saveRecipe(
      const Recipe(
        id: 'r2',
        title: 'Salad',
        servingsBase: 4,
        groups: [IngredientGroup(id: 'r2-g1')],
      ),
    );

    final list = await repo.watchRecipes().first;
    expect(list.map((r) => r.title), containsAll(['Weeknight Curry', 'Salad']));
    expect(list.firstWhere((r) => r.id == 'r2').servingsBase, 4);
  });

  test('saveRecipe replaces children rather than duplicating them', () async {
    await repo.saveRecipe(_sampleRecipe());

    // Re-save with a single group holding one item.
    await repo.saveRecipe(
      _sampleRecipe().copyWith(
        groups: [
          const IngredientGroup(
            id: 'g1',
            name: 'Simplified',
            items: [
              LineItem(
                id: 'i9',
                ingredientId: 'ing-onion',
                ingredientName: 'Onion',
                unit: pieces,
                quantity: 3,
              ),
            ],
          ),
        ],
      ),
    );

    final loaded = await repo.watchRecipe('r1').first;
    expect(loaded!.groups.length, 1);
    expect(loaded.groups.single.name, 'Simplified');
    expect(loaded.groups.single.items.single.quantity, 3);

    // No stale rows left behind.
    final itemCount = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item',
    );
    expect(itemCount['c'], 1);
    final groupCount = await db.get(
      'SELECT count(*) AS c FROM ingredient_group',
    );
    expect(groupCount['c'], 1);
  });

  test('watchRecipe re-fires when its section is renamed', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO book (id, household_id, name, sort_order, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['b1', 'h', 'Our Cookbook', 0, now, now],
    );
    await db.execute(
      'INSERT INTO book_section (id, household_id, book_id, name, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['s1', 'h', 'b1', 'Weeknight', 0, now, now],
    );
    await repo.saveRecipe(
      _sampleRecipe().copyWith(bookId: 'b1', sectionId: 's1'),
    );

    // The breadcrumb is a join, so the watched query has to name the filing
    // tables too — otherwise a rename leaves the recipe page stale.
    final recipes = StreamIterator(repo.watchRecipe('r1'));
    addTearDown(recipes.cancel);

    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.sectionName, 'Weeknight');

    await db.execute('UPDATE book_section SET name = ? WHERE id = ?', [
      'Sunday Batch',
      's1',
    ]);
    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.sectionName, 'Sunday Batch');

    await db.execute('UPDATE book SET name = ? WHERE id = ?', [
      'The Big Book',
      'b1',
    ]);
    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.bookName, 'The Big Book');
  });

  test('deleteRecipe soft-deletes: gone from list and lookup', () async {
    await repo.saveRecipe(_sampleRecipe());
    await repo.deleteRecipe('r1');

    expect(await repo.watchRecipe('r1').first, isNull);
    expect(await repo.watchRecipes().first, isEmpty);

    // Row remains as a tombstone.
    final row = await db.get('SELECT deleted_at FROM recipe WHERE id = ?', [
      'r1',
    ]);
    expect(row['deleted_at'], isNotNull);
  });
}
