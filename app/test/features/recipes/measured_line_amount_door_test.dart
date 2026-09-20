/// The amount door on a MEASURED component line — `3 blob` (ADR-0018).
///
/// Two doors reach that cell and both are here: the recipe editor's own line
/// card, and week mode's row. The rule they share is that the sheet behind it
/// is the COMPONENT one, whose offer can say a recipe's own word; the
/// ingredient sheet's cannot, and opens such a line preselected on `piece`.
///
/// What each door must hold: the word is what the sheet opens on, the number is
/// editable without touching it, picking a unit clears it, and — the whole
/// reason this file exists — no path through either door can write a unit where
/// the word was without the person having tapped that unit.
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
import 'package:ansi/features/recipes/presentation/recipe_measures_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_measure_repository.dart';
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

/// The parent, whose one line is said in the aioli's own word.
const _measuredLine = LineItem(
  id: 'l1',
  subRecipeId: 'aioli',
  subRecipe: _aioli,
  ingredientName: 'Romesco Aioli',
  quantity: 3,
  recipeMeasureId: 'm-blob',
);

/// The same line before anybody said it in a word — a plain `¼ cup`, which is
/// still a COMPONENT line and still the component sheet's business.
const _unitLine = LineItem(
  id: 'l1',
  subRecipeId: 'aioli',
  subRecipe: _aioli,
  ingredientName: 'Romesco Aioli',
  quantity: 0.25,
  unit: cup,
);

Recipe _sliders(LineItem line) => Recipe(
  id: '1',
  title: 'Sausage Sliders',
  servingsBase: 4,
  groups: [
    IngredientGroup(id: 'g1', items: [line]),
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

/// A chip in the sheet's row, by its label — `find.text` alone would also match
/// the sentence beside the number, which says `blob (50 ml)`.
Finder _chip(String label) => find.descendant(
  of: find.byType(ComponentQuantityEditor),
  matching: find.text(label),
);

/// The chip row's manage chip — a real icon, because the bundled fonts carry
/// no U+FF0B.
final _plus = find.descendant(
  of: find.byType(ComponentQuantityEditor),
  matching: find.byIcon(FLucideIcons.plus),
);

/// Coins one word behind the ＋, which is open.
Future<void> _coin(
  WidgetTester tester, {
  required String label,
  required String amount,
}) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('add-word-measure-label')),
      matching: find.byType(TextField),
    ),
    label,
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('add-word-measure-amount')),
      matching: find.byType(TextField),
    ),
    amount,
  );
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(RecipeMeasuresEditor),
      matching: find.widgetWithText(FButton, 'Save'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Back out of the manage state, to the amount.
Future<void> _backToTheAmount(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Back'));
  await tester.pumpAndSettle();
}

void main() {
  group('the recipe editor', () {
    testWidgets('the amount cell opens on the word, and Done keeps it', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final repo = FakeRecipeRepo(_sliders(_measuredLine));
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

      // The word leads the row and is what the sheet opened on; the catalog
      // chips sit behind it, so the denomination is a choice rather than a
      // fact the person cannot reach.
      expect(_chip('blob'), findsOneWidget);
      expect(_chip('batch'), findsOneWidget);
      expect(_chip('cup'), findsOneWidget);
      // What one of the word comes to is said beside the number, the way a
      // picked ingredient measure says it.
      expect(find.text('blob (50 ml)'), findsOneWidget);
      expect(find.textContaining('3 blob = '), findsOneWidget);

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
      final repo = FakeRecipeRepo(_sliders(_measuredLine));
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

    testWidgets('picking a unit clears the word — a line is denominated once', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final repo = FakeRecipeRepo(_sliders(_measuredLine));
      await tester.pumpWidget(
        hostEditor('1', [recipeRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openLine(tester, 'Romesco Aioli');
      await tester.tap(find.byType(LineCardAmountChip));
      await tester.pumpAndSettle();
      await tester.tap(_chip('cup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await saveEditor(tester);

      final line = repo.saved.single.groups.single.items.single;
      expect(line.unit, cup);
      expect(
        line.recipeMeasureId,
        isNull,
        reason: 'the word and a unit cannot both count one number',
      );
    });

    testWidgets('and a units-said component line can be said in the word', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final repo = FakeRecipeRepo(_sliders(_unitLine));
      await tester.pumpWidget(
        hostEditor('1', [recipeRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openLine(tester, 'Romesco Aioli');
      await tester.tap(find.byType(LineCardAmountChip));
      await tester.pumpAndSettle();
      await tester.tap(_chip('blob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await saveEditor(tester);

      final line = repo.saved.single.groups.single.items.single;
      expect(line.recipeMeasureId, 'm-blob');
      expect(line.unit, isNull);
    });

    testWidgets('the ＋ on that dock opens the TARGET recipe’s own words — '
        'the sauce being measured, not the recipe being written', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final words = FakeRecipeMeasureRepo(measures: const [_blob]);
      await tester.pumpWidget(
        hostEditor('1', [
          recipeRepositoryProvider.overrideWithValue(
            FakeRecipeRepo(_sliders(_measuredLine)),
          ),
          recipeMeasureRepositoryProvider.overrideWithValue(words),
        ]),
      );
      await tester.pumpAndSettle();

      await openLine(tester, 'Romesco Aioli');
      await tester.tap(find.byType(LineCardAmountChip));
      await tester.pumpAndSettle();
      // The row scrolls: the manage chip is last, behind every unit the
      // yield's family opens.
      await tester.ensureVisible(_plus);
      await tester.pumpAndSettle();
      await tester.tap(_plus);
      await tester.pumpAndSettle();

      // The manage state, headed by the TARGET — this editor is open on
      // Sausage Sliders, and the word belongs to the aioli.
      expect(find.text('Measures'), findsOneWidget);
      expect(find.text('Romesco Aioli'), findsWidgets);
      expect(find.text('blob'), findsWidgets);
      expect(find.text('50 ml'), findsOneWidget);
    });

    testWidgets('a word coined behind that ＋ reaches the ROW — the line reads '
        '3 glug, not a bare 3', (tester) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final words = FakeRecipeMeasureRepo(measures: const [_blob]);
      final repo = FakeRecipeRepo(_sliders(_unitLine));
      await tester.pumpWidget(
        hostEditor('1', [
          recipeRepositoryProvider.overrideWithValue(repo),
          recipeMeasureRepositoryProvider.overrideWithValue(words),
        ]),
      );
      await tester.pumpAndSettle();

      await openLine(tester, 'Romesco Aioli');
      await tester.tap(find.byType(LineCardAmountChip));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_plus);
      await tester.pumpAndSettle();
      await tester.tap(_plus);
      await tester.pumpAndSettle();
      await _coin(tester, label: 'glug', amount: '30');
      await _backToTheAmount(tester);
      await tester.enterText(_qtyField(), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The word is newer than the target this row was built from, so the
      // sheet hands the row itself back rather than only its id.
      expect(find.text('3 glug'), findsWidgets);

      await saveEditor(tester);
      final line = repo.saved.single.groups.single.items.single;
      expect(line.recipeMeasureId, words.added.single.id);
      expect(line.quantity, 3);
    });
  });

  group('week mode', () {
    const weekKey = '2026-09-14';
    final monday = DateTime.utc(2026, 9, 14);

    List<Override> overrides(
      FakeWeekVariantRepository variants,
      LineItem line,
    ) => [
      recipeRepositoryProvider.overrideWithValue(
        FakeRecipeRepository(recipe: _sliders(line)),
      ),
      planningRepositoryProvider.overrideWithValue(_Planner(monday)),
      weekVariantRepositoryProvider.overrideWithValue(variants),
      ingredientRepositoryProvider.overrideWithValue(
        const ReadOnlyIngredientRepo(),
      ),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
    ];

    Future<GoRouter> openWeekEditor(
      WidgetTester tester,
      FakeWeekVariantRepository variants,
      LineItem line,
    ) async {
      late GoRouter router;
      await tester.pumpWidget(
        routedHost(
          initial: '/week',
          overrides: overrides(variants, line),
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
      return router;
    }

    testWidgets('this week’s amount for a measured line is said in the word, '
        'never in a unit', (tester) async {
      filterForuiSemanticsAssertions();
      final variants = FakeWeekVariantRepository();
      await openWeekEditor(tester, variants, _measuredLine);

      // The row's amount cell — `3 blob`, because the week's list reads the
      // word off the target's live measures too.
      await tester.tap(find.text('3 blob').first);
      await tester.pumpAndSettle();

      // The COMPONENT sheet, not the ingredient one: the ingredient sheet's
      // offer is catalog units and named INGREDIENT measures, and a recipe's
      // own word is neither — it would open preselected on `piece`.
      expect(find.byType(ComponentQuantityEditor), findsOneWidget);
      expect(_chip('blob'), findsOneWidget);

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

    testWidgets('an UNMEASURED component line gets the component sheet too — '
        'and can be said in the word from here', (tester) async {
      // The mismatch this closes: week mode reached for the INGREDIENT sheet on
      // a component line that happened to carry a unit, so the one row that
      // could say `blob` could not be asked about it, and the offer it did get
      // was about a stub ingredient that does not exist.
      filterForuiSemanticsAssertions();
      final variants = FakeWeekVariantRepository();
      await openWeekEditor(tester, variants, _unitLine);

      await tester.tap(find.text('¼ cup').first);
      await tester.pumpAndSettle();

      expect(find.byType(ComponentQuantityEditor), findsOneWidget);
      expect(_chip('batch'), findsOneWidget, reason: 'a recipe, not a row');

      await tester.tap(_chip('blob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = variants.saved.single.set.single;
      expect(stored.recipeMeasureId, 'm-blob');
      expect(stored.unit, isNull);
    });

    testWidgets('the ＋ is the same door here — the week says a line in the '
        'target’s own word exactly as the recipe does', (tester) async {
      filterForuiSemanticsAssertions();
      final variants = FakeWeekVariantRepository();
      await tester.pumpWidget(
        routedHost(
          initial: '/recipes/1/edit',
          overrides: [
            ...overrides(variants, _measuredLine),
            recipeMeasureRepositoryProvider.overrideWithValue(
              FakeRecipeMeasureRepo(measures: const [_blob]),
            ),
          ],
          routes: {
            '/recipes/1/edit': (_, _) =>
                const WeekVariantEditorView(recipeId: '1', weekKey: weekKey),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('3 blob').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_plus);
      await tester.pumpAndSettle();
      await tester.tap(_plus);
      await tester.pumpAndSettle();

      expect(find.text('Measures'), findsOneWidget);
      expect(find.text('50 ml'), findsOneWidget);
    });

    testWidgets('and a word coined behind it reaches this week’s row too', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      final variants = FakeWeekVariantRepository();
      final words = FakeRecipeMeasureRepo(measures: const [_blob]);
      await tester.pumpWidget(
        routedHost(
          initial: '/recipes/1/edit',
          overrides: [
            ...overrides(variants, _unitLine),
            recipeMeasureRepositoryProvider.overrideWithValue(words),
          ],
          routes: {
            '/recipes/1/edit': (_, _) =>
                const WeekVariantEditorView(recipeId: '1', weekKey: weekKey),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('¼ cup').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_plus);
      await tester.pumpAndSettle();
      await tester.tap(_plus);
      await tester.pumpAndSettle();
      await _coin(tester, label: 'glug', amount: '30');
      await _backToTheAmount(tester);
      await tester.enterText(_qtyField(), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('3 glug'), findsWidgets);
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
