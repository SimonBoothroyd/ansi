/// What keeps a recipe's own words honest when the rows around them go: a word
/// with no number, a word whose only referrers are tombstones, and a line
/// pointing at the twin the merge hides. Over the real PowerSync views.
library;

import 'dart:io';

import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/features/recipes/data/recipe_measure_repository_impl.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/component_units.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/measure_fixtures.dart';
import '../../helpers/test_db.dart';

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;
  late SqliteRecipeMeasureRepository measures;

  Future<void> seedAioli() => repo.saveRecipe(aioliRecipe());

  Recipe parent({double? quantity = 3, String measureId = 'm-blob'}) =>
      sliders(quantity: quantity, measureId: measureId);

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

  group('a line resolves by id, against every live row', () {
    test('a line on the merge-hidden twin keeps ITS word and amount', () async {
      await seedAioli();
      await insertHiddenTwin();
      await repo.saveRecipe(parent(measureId: 'm-blob-2'));

      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      final amount = line.componentAmount;
      expect(
        amount,
        isA<ResolvedComponentAmount>(),
        reason: 'the hidden row is live, so its line is not a gap',
      );
      expect((amount! as ResolvedComponentAmount).viaMeasure?.amount, 12.5);
      expect((amount as ResolvedComponentAmount).viaMeasure?.label, 'blob');
    });

    test('and its target recipe still saves, tombstoning nothing', () async {
      await seedAioli();
      await insertHiddenTwin();
      await repo.saveRecipe(parent(measureId: 'm-blob-2'));

      // The editor's list is the MERGED one, so the hidden twin is not in it —
      // and a Save must not read that absence as "drop this word".
      final loaded = (await repo.watchRecipe('aioli').first)!;
      expect(loaded.measures.map((m) => m.id), ['m-blob']);
      await repo.saveRecipe(loaded.copyWith(title: 'Romesco Aioli II'));

      final rows = await db.getAll(
        'SELECT id, deleted_at FROM recipe_measure WHERE recipe_id = ? '
        'ORDER BY id',
        ['aioli'],
      );
      expect(rows.map((r) => r['deleted_at']), [null, null]);
    });

    test('the chip row still offers the word ONCE', () async {
      await seedAioli();
      await insertHiddenTwin();
      await repo.saveRecipe(parent(measureId: 'm-blob-2'));
      final sliders = (await repo.watchRecipe('sliders').first)!;
      final target = sliders.groups.single.items.single.subRecipe!;
      final hidden = target.measures.firstWhere((m) => m.id == 'm-blob-2');

      final offer = componentUnitChoices(
        target,
        target.measures,
        current: RecipeMeasureOption(hidden),
      );
      expect(
        offer.choices.whereType<RecipeMeasureOption>().map((c) => c.measure.id),
        ['m-blob-2'],
        reason: 'one “blob” chip, and it is the one this line says',
      );
      expect(offer.offFilter, isNull);
    });
  });
}
