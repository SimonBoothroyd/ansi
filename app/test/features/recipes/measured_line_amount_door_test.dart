/// The one destructive door this reader release has to close.
///
/// No screen on this build can AUTHOR a recipe measure — but a device can meet
/// a measured line (`3 blob`) written by a later build, because the data layer
/// ships a release ahead of the authoring UI (ADR-0018). The amount cell on
/// such a line opened the units-only component quantity sheet, which always
/// returns a unit, so a person tapping the cell to change the NUMBER and
/// pressing Done would have written `g` where `blob` was — and the word is the
/// only place the line's amount lived.
///
/// Two doors reach that cell, and both are here: the recipe editor's own line
/// card, and week mode's row (which reaches for the INGREDIENT sheet, whose
/// offer cannot express a recipe's word at all).
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_variant_editor.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart';
import 'package:ansi/features/recipes/presentation/line_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// A blob is 50 ml, and the aioli makes 1 cup — so `3 blob` is 150 ml, which
/// is a little under two thirds of a batch.
const _blob = RecipeMeasure(
  id: 'm-blob',
  recipeId: 'aioli',
  label: 'blob',
  amount: 50,
  unit: ml,
);

const _aioli = SubRecipeTarget(
  id: 'aioli',
  title: 'Romesco Aioli',
  yieldQty: 1,
  yieldUnit: cup,
  measures: [_blob],
);

/// The parent, whose one line is the one no screen here can write.
const _measuredLine = LineItem(
  id: 'l1',
  subRecipeId: 'aioli',
  subRecipe: _aioli,
  ingredientName: 'Romesco Aioli',
  quantity: 3,
  recipeMeasureId: 'm-blob',
);

const _sliders = Recipe(
  id: '1',
  title: 'Sausage Sliders',
  servingsBase: 4,
  groups: [
    IngredientGroup(id: 'g1', items: [_measuredLine]),
  ],
);

/// The sheet's own quantity field — scoped to the sheet, because every host
/// here has text fields of its own.
Finder _qtyField() => find
    .descendant(
      of: find.byType(ComponentQuantityEditor),
      matching: find.byType(TextField),
    )
    .first;

void main() {
  group('the recipe editor', () {
    testWidgets('the amount cell opens on the word, and Done keeps it', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final repo = FakeRecipeRepo(_sliders);
      await tester.pumpWidget(
        hostEditor('1', [recipeRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      // The row reads the word off the target's LIVE measures rather than off
      // the resolution, so it says `3 blob` rather than a bare `3`.
      expect(find.text('3 blob'), findsWidgets);

      await openLine(tester, 'Romesco Aioli');
      await tester.tap(find.byType(LineCardAmountChip));
      await tester.pumpAndSettle();

      // The component sheet, on the word alone.
      expect(find.text('this recipe’s word'), findsOneWidget);
      expect(
        find.text(ComponentQuantityEditor.kMeasuredLineKeepsItsWord),
        findsOneWidget,
      );
      expect(find.text('cup'), findsNothing, reason: 'no unit to replace it');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await saveEditor(tester);

      final line = repo.saved.single.groups.single.items.single;
      expect(line.recipeMeasureId, 'm-blob');
      expect(line.unit, isNull, reason: 'a unit here would lose the word');
      expect(line.quantity, 3);
    });

    testWidgets('the number is still editable through that door', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final repo = FakeRecipeRepo(_sliders);
      await tester.pumpWidget(
        hostEditor('1', [recipeRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openLine(tester, 'Romesco Aioli');
      await tester.tap(find.byType(LineCardAmountChip));
      await tester.pumpAndSettle();
      await tester.enterText(_qtyField(), '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await saveEditor(tester);

      final line = repo.saved.single.groups.single.items.single;
      expect(line.quantity, 5, reason: 'the part a cook wants to change');
      expect(line.recipeMeasureId, 'm-blob');
      expect(line.unit, isNull);
    });
  });

  group('week mode', () {
    const weekKey = '2026-09-14';
    final monday = DateTime.utc(2026, 9, 14);

    List<Override> overrides(FakeWeekVariantRepository variants) => [
      recipeRepositoryProvider.overrideWithValue(
        FakeRecipeRepository(recipe: _sliders),
      ),
      planningRepositoryProvider.overrideWithValue(_Planner(monday)),
      weekVariantRepositoryProvider.overrideWithValue(variants),
      ingredientRepositoryProvider.overrideWithValue(
        const ReadOnlyIngredientRepo(),
      ),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
    ];

    testWidgets('this week’s amount for a measured line is said in the word, '
        'never in a unit', (tester) async {
      filterForuiSemanticsAssertions();
      final variants = FakeWeekVariantRepository();
      late GoRouter router;
      await tester.pumpWidget(
        routedHost(
          initial: '/week',
          overrides: overrides(variants),
          expose: (r) => router = r,
          routes: {
            '/week': (_, _) => const Text('the week'),
            '/recipes/1/edit': (_, _) =>
                const WeekVariantEditorView(recipeId: '1', weekKey: weekKey),
          },
        ),
      );
      unawaited(router.push('/recipes/1/edit'));
      await tester.pumpAndSettle();

      // The row's amount cell — `3 blob`, because the week's list reads the
      // word off the target's live measures too.
      await tester.tap(find.text('3 blob').first);
      await tester.pumpAndSettle();

      // The COMPONENT sheet, not the ingredient one: the ingredient sheet's
      // offer is catalog units and named INGREDIENT measures, and a recipe's
      // own word is neither — it would open preselected on `piece`.
      expect(
        find.text(ComponentQuantityEditor.kMeasuredLineKeepsItsWord),
        findsOneWidget,
      );
      expect(find.text('this recipe’s word'), findsOneWidget);

      await tester.enterText(_qtyField(), '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = variants.saved.single.set.single;
      expect(stored.quantity, 5, reason: 'the number this week asks for');
      expect(stored.recipeMeasureId, 'm-blob');
      expect(stored.unit, isNull, reason: 'the word IS the denomination');
    });
  });
}

class _Planner extends FakePlanningRepository {
  _Planner(this.monday) : super(const [Member(id: 'm1', displayName: 'Ada')]);

  final DateTime monday;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(
    WeekPlan(
      id: 'wp1',
      weekStart: monday,
      entries: const [
        PlanEntry(
          id: 'e1',
          dayOfWeek: 1,
          mealSlot: 'Dinner',
          recipeId: '1',
          recipeTitle: 'Sausage Sliders',
          eaterIds: ['m1'],
        ),
      ],
    ),
  );
}
