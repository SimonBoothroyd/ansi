/// A word coined behind the ＋ of the component sheet, written through the real
/// repositories over the real PowerSync views, then costed and macro'd as the
/// share of a batch it says. How a host maps the sheet's answer onto its line
/// is `measured_line_amount_door_test`'s.
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/presentation/unit_chips.dart';
import 'package:ansi/features/recipes/data/recipe_measure_repository_impl.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart';
import 'package:ansi/features/recipes/presentation/recipe_measures_editor.dart';
import 'package:ansi/shared/unit_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/forui_semantics.dart';
import '../../helpers/measure_fixtures.dart';
import '../../helpers/test_db.dart';

/// The word coined mid-sentence: a ladle is 30 g, a tenth of a batch.
const _ladle = (label: 'ladle', grams: 30.0);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db, householdId: 'h');
    await seedPricedRice(db);
    await repo.saveRecipe(aioliRecipe());
  });

  tearDown(() => closeTestDb(db, dir));

  testWidgets('a word coined behind the ＋ is live, selected, and costs and '
      'macros the share it says — all of it through the real repository', (
    tester,
  ) async {
    // The parent as it stands: one whole batch of the aioli.
    final target = (await tester.runAsync(
      () async => (await repo.watchRecipe('aioli').first)!.asSubRecipeTarget,
    ))!;
    await tester.runAsync(
      () => repo.saveRecipe(
        sliders(quantity: 1, unit: batches, measureId: null, target: target),
      ),
    );

    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ComponentQuantity? picked;
    await tester.pumpWidget(
      ProviderScope(
        // The ＋ writes through the real repository, and the sheet reads the
        // word back through its watch.
        // ignore: scoped_providers_should_specify_dependencies
        overrides: [
          recipeMeasureRepositoryProvider.overrideWithValue(
            SqliteRecipeMeasureRepository(db, householdId: 'h'),
          ),
        ],
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: FToaster(
              child: FScaffold(
                child: ComponentQuantityEditor(
                  target: target,
                  initialQuantity: 1,
                  initialUnit: batches,
                  mayCoinWords: true,
                  onDone: (q) => picked = q,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Coin `ladle` from the sliders' line rather than on the aioli's page.
    await tester.ensureVisible(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('add-word-measure-label')),
        matching: find.byType(TextField),
      ),
      _ladle.label,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('add-word-measure-amount')),
        matching: find.byType(TextField),
      ),
      '${_ladle.grams.toInt()}',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(RecipeMeasuresEditor),
        matching: find.widgetWithText(FButton, 'Save'),
      ),
    );
    // Real SQLite runs on the real event loop, so wait for the write on the
    // repository's own watch, then pump until the sheet has drawn it.
    final words = SqliteRecipeMeasureRepository(db, householdId: 'h');
    await tester.runAsync(
      () => words
          .watchRecipeMeasures('aioli')
          .firstWhere((list) => list.length == 2),
    );
    final chip = find.descendant(
      of: find.byType(UnitChipRow),
      matching: find.widgetWithText(UnitChip, _ladle.label),
    );
    for (var i = 0; i < 50 && chip.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    // Stored, once, against the recipe the word belongs to.
    final rows = (await tester.runAsync(
      () => db.getAll(
        'SELECT id, label, amount, unit FROM recipe_measure '
        'WHERE recipe_id = ? AND deleted_at IS NULL ORDER BY sort_order',
        ['aioli'],
      ),
    ))!;
    expect(rows.map((r) => r['label']), ['blob', _ladle.label]);
    final coinedId = rows.last['id'] as String;
    expect(rows.last['amount'], _ladle.grams);
    expect(rows.last['unit'], 'g');

    // Back on the amount the new word is a chip, and the one being counted.
    expect(chip, findsOneWidget);
    expect(tester.widget<UnitChip>(chip).selected, isTrue);

    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked!.recipeMeasureId, coinedId);
    expect(picked!.unit, isNull);

    // Stand in for the host: put the sheet's answer on the line and save.
    await tester.runAsync(
      () => repo.saveRecipe(
        sliders(
          quantity: picked!.quantity,
          unit: picked!.unit,
          measureId: picked!.recipeMeasureId,
          target: target,
        ),
      ),
    );

    final coined = RecipeMeasure(
      id: coinedId,
      recipeId: 'aioli',
      label: _ladle.label,
      amount: _ladle.grams,
      unit: g,
    );
    final saved = (await tester.runAsync(
      () async => (await repo.watchRecipe('sliders').first)!,
    ))!;
    final line = saved.groups.single.items.single;
    expect(line.recipeMeasureId, coinedId);
    expect(line.unit, isNull);
    expect(
      (line.componentAmount! as ResolvedComponentAmount).batches,
      closeTo(batchesOf(2, coined), 1e-12),
    );

    final aioli = (await tester.runAsync(
      () async => (await repo.watchRecipe('aioli').first)!,
    ))!;
    expect(
      saved.macros!.perServing!.kcal * 8,
      closeTo(batchesOf(2, coined) * aioli.macros!.perServing!.kcal * 4, 1e-9),
    );

    final costs = (await tester.runAsync(() => repo.watchRecipeCosts().first))!;
    expect(
      costs['sliders']!.totalCents,
      closeTo(batchesOf(2, coined) * costs['aioli']!.totalCents!, 1),
    );

    // Take the tree down and let the real loop close the sheet's live query,
    // or the binding finds its read lock still pending.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  });
}
