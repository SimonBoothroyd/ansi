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
    repo = SqliteRecipeRepository(db, householdId: 'h');
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

  test('a measure line round-trips: id persisted, measure resolved', () async {
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, grams, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['m-onion', 'h', 'ing-onion', 'onion, medium', 110, 0],
    );
    final recipe = _sampleRecipe();
    final withMeasure = recipe.copyWith(
      groups: [
        recipe.groups.first.copyWith(
          items: [
            recipe.groups.first.items.first.copyWith(
              quantity: 2,
              measureId: 'm-onion',
            ),
            ...recipe.groups.first.items.skip(1),
          ],
        ),
        ...recipe.groups.skip(1),
      ],
    );
    await repo.saveRecipe(withMeasure);

    final loaded = await repo.watchRecipe('r1').first;
    final onion = loaded!.groups.first.items.first;
    expect(onion.measureId, 'm-onion');
    expect(onion.measure, isNotNull);
    expect(onion.measure!.label, 'onion, medium');
    expect(onion.measure!.grams, 110);
    expect(onion.unit, pieces); // the honest count fallback stays stored
  });

  test('an unresolved measure_id survives a re-save (never '
      'stripped)', () async {
    // The measure row hasn't synced (or was deleted): the line loads with
    // measure null but keeps its id, and an unrelated edit re-saves it.
    final recipe = _sampleRecipe();
    final withMeasure = recipe.copyWith(
      groups: [
        recipe.groups.first.copyWith(
          items: [
            recipe.groups.first.items.first.copyWith(measureId: 'm-ghost'),
            ...recipe.groups.first.items.skip(1),
          ],
        ),
        ...recipe.groups.skip(1),
      ],
    );
    await repo.saveRecipe(withMeasure);

    final loaded = await repo.watchRecipe('r1').first;
    final onion = loaded!.groups.first.items.first;
    expect(onion.measure, isNull);
    expect(onion.measureId, 'm-ghost');

    await repo.saveRecipe(loaded.copyWith(title: 'Renamed'));
    final reloaded = await repo.watchRecipe('r1').first;
    expect(reloaded!.groups.first.items.first.measureId, 'm-ghost');
  });

  test('watchRecipe re-fires when a measure is renamed', () async {
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, grams, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['m-onion', 'h', 'ing-onion', 'onion, medium', 110, 0],
    );
    final recipe = _sampleRecipe();
    await repo.saveRecipe(
      recipe.copyWith(
        groups: [
          recipe.groups.first.copyWith(
            items: [
              recipe.groups.first.items.first.copyWith(
                quantity: 2,
                measureId: 'm-onion',
              ),
              ...recipe.groups.first.items.skip(1),
            ],
          ),
          ...recipe.groups.skip(1),
        ],
      ),
    );

    final labels = repo
        .watchRecipe('r1')
        .map((r) => r?.groups.first.items.first.measure?.label)
        .distinct()
        .take(2)
        .toList();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.execute('UPDATE ingredient_measure SET label = ? WHERE id = ?', [
      'onion, large',
      'm-onion',
    ]);
    expect(await labels, ['onion, medium', 'onion, large']);
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

    // No stale *live* rows left behind — dropped children are tombstoned
    // (deleted_at set), never hard-deleted, so the delete syncs upstream.
    final itemCount = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item WHERE deleted_at IS NULL',
    );
    expect(itemCount['c'], 1);
    final groupCount = await db.get(
      'SELECT count(*) AS c FROM ingredient_group WHERE deleted_at IS NULL',
    );
    expect(groupCount['c'], 1);
    final tombstones = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item WHERE deleted_at IS NOT NULL',
    );
    expect(tombstones['c'], 3, reason: 'i1, i2 and i3 were all dropped');
  });

  test('an edited re-save queues no DELETE for kept children', () async {
    await repo.saveRecipe(_sampleRecipe());
    await drainCrudQueue(db);

    // A title-only edit keeps every child id. The old delete + re-insert
    // implementation queued DELETE-then-PUT per child; the connector maps
    // DELETE to a server tombstone the later PUT never cleared, so every
    // ingredient vanished on other devices after any edit.
    await repo.saveRecipe(_sampleRecipe().copyWith(title: 'Renamed'));

    final ops = await queuedCrudOps(db);
    expect(
      ops.where((o) => o['op'] == 'DELETE'),
      isEmpty,
      reason: 'kept child ids must never round-trip through DELETE',
    );

    // The children still exist, live, exactly once.
    final itemCount = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item WHERE deleted_at IS NULL',
    );
    expect(itemCount['c'], 3);
  });

  test(
    'dropping a child on re-save queues a tombstone PATCH, not a DELETE',
    () async {
      await repo.saveRecipe(_sampleRecipe());
      await drainCrudQueue(db);

      final edited = _sampleRecipe();
      await repo.saveRecipe(
        edited.copyWith(
          groups: [
            edited.groups.first, // keep g1 (i1, i2); drop g2 (i3)
          ],
        ),
      );

      final ops = await queuedCrudOps(db);
      expect(ops.where((o) => o['op'] == 'DELETE'), isEmpty);

      final itemTombstone = ops.singleWhere(
        (o) =>
            o['type'] == 'recipe_line_item' &&
            o['id'] == 'i3' &&
            o['op'] == 'PATCH',
      );
      expect((itemTombstone['data'] as Map)['deleted_at'], isNotNull);
      final groupTombstone = ops.singleWhere(
        (o) =>
            o['type'] == 'ingredient_group' &&
            o['id'] == 'g2' &&
            o['op'] == 'PATCH',
      );
      expect((groupTombstone['data'] as Map)['deleted_at'], isNotNull);
    },
  );

  test('watchRecipe re-fires when an ingredient is renamed', () async {
    await repo.saveRecipe(_sampleRecipe());

    final recipes = StreamIterator(repo.watchRecipe('r1'));
    addTearDown(recipes.cancel);

    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.groups.first.items.first.ingredientName, 'Onion');

    // A server-side vocab rename arrives as a plain UPDATE on `ingredient`;
    // the open recipe page must re-assemble (the watch has to name the
    // ingredient table with a selected column, or SQLite drops the join).
    await db.execute('UPDATE ingredient SET canonical_name = ? WHERE id = ?', [
      'Brown Onion',
      'ing-onion',
    ]);
    expect(await recipes.moveNext(), isTrue);
    expect(
      recipes.current?.groups.first.items.first.ingredientName,
      'Brown Onion',
    );
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
