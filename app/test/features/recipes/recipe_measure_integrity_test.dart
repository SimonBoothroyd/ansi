/// What keeps a recipe's own words HONEST when the rows around them go: a line
/// that says a word but no number, a word whose only referrers are tombstones,
/// and a line pointing at the twin the merge hides.
///
/// Over the real PowerSync views, because each one is a question about stored
/// rows — which tombstones a count may see, and which row an id resolves to.
library;

import 'dart:io';

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_measure_repository_impl.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// What the aioli says a batch makes — every word below is a mass, because a
/// word is only sayable against a `makes` it can be held to.
const _yield = (qty: 300.0, unit: g);

RecipeMeasure _blob({String id = 'm-blob', double amount = 15}) =>
    RecipeMeasure(
      id: id,
      recipeId: 'aioli',
      label: 'blob',
      amount: amount,
      unit: g,
    );

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;
  late SqliteRecipeMeasureRepository measures;

  /// The Romesco Aioli: makes 300 g, and the household's word for a blob of it.
  Future<void> seedAioli() => repo.saveRecipe(
    Recipe(
      id: 'aioli',
      title: 'Romesco Aioli',
      servingsBase: 4,
      yieldQty: _yield.qty,
      yieldUnit: _yield.unit,
      measures: [_blob()],
      groups: const [
        IngredientGroup(
          id: 'ag',
          items: [
            LineItem(
              id: 'ai1',
              ingredientId: 'ing-rice',
              ingredientName: 'Rice',
              unit: g,
              quantity: 240,
            ),
          ],
        ),
      ],
    ),
  );

  /// A parent whose only line asks for [quantity] of the aioli's word.
  Recipe parent({double? quantity = 3, String measureId = 'm-blob'}) => Recipe(
    id: 'sliders',
    title: 'Sausage Sliders',
    servingsBase: 8,
    groups: [
      IngredientGroup(
        id: 'sg',
        items: [
          LineItem(
            id: 'si1',
            subRecipeId: 'aioli',
            ingredientName: 'Romesco Aioli',
            quantity: quantity,
            recipeMeasureId: measureId,
          ),
        ],
      ),
    ],
  );

  /// The other phone's second `blob`, arriving later and hidden behind the
  /// older row by the merge.
  Future<void> insertHiddenTwin({double amount = 12.5}) => db.execute(
    'INSERT INTO recipe_measure (id, household_id, recipe_id, label, '
    'amount, unit, sort_order, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'm-blob-2',
      'h',
      'aioli',
      'blob',
      amount,
      'g',
      0,
      '2099-01-01T00:00:00Z',
      '2099-01-01T00:00:00Z',
    ],
  );

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db, householdId: 'h');
    measures = SqliteRecipeMeasureRepository(db, householdId: 'h');
    await db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, '
      'default_unit, status, source, match_text) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['ing-rice', 'h', 'Rice', 'g', 'complete', 'seed', 'rice'],
    );
  });

  tearDown(() => closeTestDb(db, dir));

  group('a word with no number never reaches the queue', () {
    test('saveRecipe refuses a measured line that says no amount', () async {
      await seedAioli();
      await drainCrudQueue(db);
      // The server's `line_item_recipe_measure_needs_amount` would reject this
      // row on UPLOAD, and a rejected upload makes the connector drop the
      // WHOLE crud transaction — so the refusal happens here instead.
      await expectLater(
        repo.saveRecipe(parent(quantity: null)),
        throwsA(
          isA<AmountlessLineError>()
              .having((e) => e.lineId, 'lineId', 'si1')
              .having((e) => e.name, 'name', 'Romesco Aioli'),
        ),
      );
      expect(await queuedCrudOps(db), isEmpty);
      expect(await repo.watchRecipe('sliders').first, isNull);
    });
  });

  group('the delete gate counts only what is still live', () {
    test('a line in a retired recipe blocks nothing, and the bin goes '
        'through', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      // `deleteRecipe` tombstones the recipe row and leaves its lines where
      // they are, so a count that reads the line alone would refuse for ever
      // with no page to send anybody to.
      await repo.deleteRecipe('sliders');

      expect(await measures.countLinesUsing('m-blob'), RecipeMeasureUsage.none);
      await measures.softDeleteRecipeMeasure('m-blob');
      expect(await measures.watchRecipeMeasures('aioli').first, isEmpty);
    });

    test('a retired GROUP takes its lines out of the count too', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      await db.execute(
        'UPDATE ingredient_group SET deleted_at = ? WHERE id = ?',
        ['2026-09-19T00:00:00Z', 'sg'],
      );
      expect((await measures.countLinesUsing('m-blob')).any, isFalse);
    });

    test('a week’s own amount is counted apart, and a retired week is not '
        'counted at all', () async {
      await seedAioli();
      for (final (id, deletedAt) in [('wp', null), ('wp-old', '2026-09-01')]) {
        await db.execute(
          'INSERT INTO week_plan (id, household_id, week_start_date, '
          'deleted_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [id, 'h', '2026-09-21', deletedAt, '2026-09-19', '2026-09-19'],
        );
        await db.execute(
          'INSERT INTO week_recipe_line_override (id, household_id, '
          'week_plan_id, recipe_id, action, sub_recipe_id, quantity, '
          'recipe_measure_id, sort_order, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'wro-$id',
            'h',
            id,
            'sliders',
            'add',
            'aioli',
            5,
            'm-blob',
            0,
            '2026-09-19',
            '2026-09-19',
          ],
        );
      }

      final usage = await measures.countLinesUsing('m-blob');
      expect(usage.lines, 0, reason: 'no recipe line says it');
      expect(usage.weeks, 1, reason: 'the retired week does not count');
      expect(usage.any, isTrue);
    });
  });
}
