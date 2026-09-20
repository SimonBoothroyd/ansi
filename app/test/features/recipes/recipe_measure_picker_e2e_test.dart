/// Picking a recipe's own word on a component line, all the way through.
///
/// The data layer for `3 blob` has its own file (`recipe_measure_data_test`);
/// what this one holds is the seam the picker closed: a chip tapped in the
/// component quantity sheet, written through the real repository over the real
/// PowerSync views, read back, and costed and macro'd as the share of a batch
/// the word says it is.
///
/// It exists because every step of that chain can be right on its own and
/// still hand the next one the wrong thing — a sheet returning a unit beside
/// the word, a caller writing the unit and dropping the pointer, a mapper
/// storing both. The numbers at the end are the only place that shows.
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/forui_semantics.dart';
import '../../helpers/test_db.dart';

/// What the aioli says a batch makes, and the word it coins for a ladleful:
/// a blob is 15 g, so against `makes 300 g` it is a twentieth of a batch.
const _yield = (qty: 300.0, unit: g);

const _blob = RecipeMeasure(
  id: 'm-blob',
  recipeId: 'aioli',
  label: 'blob',
  amount: 15,
  unit: g,
);

/// The share of a batch a count of the word comes to — read through the one
/// resolution every reader uses, so the expectation says "a share of the
/// target's batch" rather than a literal that would quietly stop being right.
double _batchesOf(double count) =>
    (resolveComponentAmount(
              quantity: count,
              unit: null,
              yields: const [_yield],
              recipeMeasureId: _blob.id,
              measures: const [_blob],
            )
            as ResolvedComponentAmount)
        .batches;

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db, householdId: 'h');
    // Rice carries per-100 g macros and a price, so a parent's figures have
    // something real to be a share OF.
    await db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, '
      'default_unit, status, source, match_text, macros, macros_basis) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'ing-rice',
        'h',
        'Rice',
        'g',
        'complete',
        'seed',
        'rice',
        '{"kcal":360,"protein":7,"carb":80,"fat":1}',
        'per_g',
      ],
    );
    await db.execute(
      'INSERT INTO receipt (id, household_id, store, purchased_at, source, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['rc1', 'h', "TJ's", '2026-09-03', 'photo', '2026-09-03'],
    );
    await db.execute(
      'INSERT INTO receipt_line (id, household_id, receipt_id, ingredient_id, '
      'cents, discount_cents, kind, pack_basis_amount, sort_order, created_at) '
      'VALUES (?, ?, ?, ?, ?, 0, ?, ?, 0, ?)',
      ['rl1', 'h', 'rc1', 'ing-rice', 500, 'item', 1000.0, '2026-09-03'],
    );
    await repo.saveRecipe(
      Recipe(
        id: 'aioli',
        title: 'Romesco Aioli',
        servingsBase: 4,
        keepsForDays: 5,
        yieldQty: _yield.qty,
        yieldUnit: _yield.unit,
        measures: const [_blob],
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
  });

  tearDown(() => closeTestDb(db, dir));

  testWidgets('a word picked on a component line survives the round trip, and '
      'the parent costs and macros the share it says', (tester) async {
    // Every repository step runs through `runAsync`: a watched query is real
    // SQLite on a real event loop, and the widget zone's fake clock never gets
    // round to it.
    //
    // The parent as it stands before anybody says a word: one whole batch of
    // the aioli, which is the denomination that never needs a yield.
    final target = (await tester.runAsync(
      () async => (await repo.watchRecipe('aioli').first)!.asSubRecipeTarget,
    ))!;
    await tester.runAsync(
      () => repo.saveRecipe(
        Recipe(
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
                  subRecipe: target,
                  ingredientName: 'Romesco Aioli',
                  quantity: 1,
                  unit: batches,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // The door: the component sheet, opened on that line, with the target's own
    // words read off the row the repository just handed back.
    filterForuiSemanticsAssertions();
    ComponentQuantity? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(
            child: ComponentQuantityEditor(
              target: target,
              initialQuantity: 1,
              initialUnit: batches,
              onDone: (q) => picked = q,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('blob'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    expect(
      find.text('3 blob = 0.15 of a batch · a blob is 15 g'),
      findsWidgets,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(picked!.recipeMeasureId, 'm-blob');
    expect(picked!.unit, isNull, reason: 'a unit here would lose the word');

    // What the host writes: the sheet's answer put on the line unchanged.
    final before = (await tester.runAsync(
      () async =>
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single,
    ))!;
    await tester.runAsync(
      () => repo.saveRecipe(
        Recipe(
          id: 'sliders',
          title: 'Sausage Sliders',
          servingsBase: 8,
          groups: [
            IngredientGroup(
              id: 'sg',
              items: [
                before.copyWith(
                  quantity: picked!.quantity,
                  unit: picked!.unit,
                  recipeMeasureId: picked!.recipeMeasureId,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Reloaded: exactly one of the two columns is set, and the line reads the
    // word off its target rather than off anything joined onto it.
    final row = (await tester.runAsync(
      () => db.get(
        'SELECT unit, recipe_measure_id, quantity FROM recipe_line_item '
        'WHERE id = ?',
        ['si1'],
      ),
    ))!;
    expect(row['unit'], isNull);
    expect(row['recipe_measure_id'], 'm-blob');
    expect(row['quantity'], 3);

    final sliders = (await tester.runAsync(
      () async => (await repo.watchRecipe('sliders').first)!,
    ))!;
    final line = sliders.groups.single.items.single;
    expect(line.recipeMeasureId, 'm-blob');
    expect(line.unit, isNull);
    expect(
      (line.componentAmount! as ResolvedComponentAmount).batches,
      closeTo(_batchesOf(3), 1e-12),
    );

    // And the numbers: the parent's figures are that share of the aioli's
    // whole batch, in both currencies the app derives.
    final aioli = (await tester.runAsync(
      () async => (await repo.watchRecipe('aioli').first)!,
    ))!;
    final aioliBatchKcal = aioli.macros!.perServing!.kcal * 4;
    expect(
      sliders.macros!.perServing!.kcal * 8,
      closeTo(_batchesOf(3) * aioliBatchKcal, 1e-9),
    );

    final costs = (await tester.runAsync(() => repo.watchRecipeCosts().first))!;
    expect(
      costs['sliders']!.totalCents,
      closeTo(_batchesOf(3) * costs['aioli']!.totalCents!, 1),
    );
  });
}
