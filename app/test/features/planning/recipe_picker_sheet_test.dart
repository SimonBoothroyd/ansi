// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/recipe_picker_sheet.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/shared/incomplete_macros.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';

/// The picker's read models, canned: two recipes — a favorite with complete
/// per-serving macros planned 3 days ago, and an unplanned one whose macros
/// are honestly incomplete (one stub line).
const _curry = RecipeSummary(
  id: 'r1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
  keepsForDays: 4,
  freezable: true,
  favorite: true,
  macros: RecipeMacroSummary(
    perServing: Macros(kcal: 520.2, protein: 31.4, carb: 40, fat: 18),
  ),
);
const _salad = RecipeSummary(
  id: 'r2',
  title: 'Halloumi Salad',
  servingsBase: 2,
  macros: RecipeMacroSummary(stubLines: 1),
);
const _bare = RecipeSummary(
  id: 'r3',
  title: 'Bare Idea',
  servingsBase: 4,
  macros: RecipeMacroSummary(noLines: true),
);

/// The rows print recency, so the planner remembers when `r1` was last eaten.
class _FakePlanningRepo extends FakePlanningRepository {
  _FakePlanningRepo()
    : super(const [
        Member(id: 'm1', displayName: 'Ada'),
        Member(id: 'm2', displayName: 'Jun'),
      ]);

  @override
  Stream<Map<String, DateTime>> watchLastPlanned() =>
      Stream.value({'r1': DateTime.now().subtract(const Duration(days: 3))});
}

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(const [Book(id: 'b1', name: 'Our Cookbook')]);
}

/// The one door's second corpus (step 8.14 / C-D1): the household vocabulary,
/// searched by the same call the editor's line picker makes.
const _bar = Ingredient(
  id: 'i1',
  canonicalName: 'Protein bar',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 350, protein: 33, carb: 30, fat: 11),
);

class _FakeVocab extends ReadOnlyIngredientRepo {
  const _FakeVocab();

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      query.toLowerCase().startsWith('prot')
      ? (rows: <Ingredient>[_bar], guessed: false)
      : (rows: const <Ingredient>[], guessed: false);
}

/// A host whose button opens the picker sheet for Wednesday dinner.
Widget _host({
  List<RecipeSummary> recipes = const [_curry, _salad],
  void Function(PickedMeal?)? onPicked,
}) => ProviderScope(
  overrides: [
    recipeRepositoryProvider.overrideWithValue(
      FakeRecipeRepository(summaries: recipes),
    ),
    planningRepositoryProvider.overrideWithValue(_FakePlanningRepo()),
    bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
    ingredientRepositoryProvider.overrideWithValue(const _FakeVocab()),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        child: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () async {
                final picked = await showRecipePickerSheet(
                  context,
                  dayOfWeek: 2,
                  slot: 'Dinner',
                );
                onPicked?.call(picked);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  List<RecipeSummary> recipes = const [_curry, _salad],
}) async {
  await tester.pumpWidget(_host(recipes: recipes));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rows are information-honest: recency, macros, incomplete', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Add a meal'), findsOneWidget);
    expect(find.textContaining('Wednesday, Dinner'), findsOneWidget);
    // The complete recipe: per-serving macros + recency; honest rounding.
    expect(find.textContaining('serves 4 · ~520 kcal · 31.4P'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);
    // The incomplete one: the badge and the reason — never zeros.
    expect(find.text('incomplete'), findsOneWidget);
    expect(find.textContaining(incompleteNote(_salad.macros!)), findsOneWidget);
    expect(find.textContaining('~0 kcal'), findsNothing);
    // The eating footer names the household.
    expect(find.textContaining('Eating: '), findsOneWidget);
    expect(find.textContaining('Ada & Jun'), findsOneWidget);
  });

  testWidgets('the picker row prints the bare-count reason in the shared words '
      '— the same sentence the panel and the confirm sheet '
      'render', (tester) async {
    const potatoes = RecipeSummary(
      id: 'r4',
      title: 'Roast Potatoes',
      servingsBase: 2,
      macros: RecipeMacroSummary(countLinesWithoutMeasure: 2),
    );
    await _open(tester, recipes: const [potatoes]);

    expect(find.text('incomplete'), findsOneWidget);
    expect(
      find.textContaining(incompleteNote(potatoes.macros!)),
      findsOneWidget,
    );
    expect(find.textContaining('unconvertible'), findsNothing);
  });

  testWidgets('a line-less recipe reads "no ingredients yet", never ~0 kcal', (
    tester,
  ) async {
    await _open(tester, recipes: const [_bare]);

    expect(find.text('incomplete'), findsOneWidget);
    expect(find.textContaining(incompleteNote(_bare.macros!)), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('Recent orders by last-planned, created order as fallback', (
    tester,
  ) async {
    // Incoming list order is created_at DESC (salad newer), but the rows
    // display last-planned recency — so the planned curry must lead, and
    // the never-planned salad follows in its created position (M11).
    await _open(tester, recipes: const [_salad, _curry]);

    final curryY = tester.getTopLeft(find.text('Weeknight Chicken Curry')).dy;
    final saladY = tester.getTopLeft(find.text('Halloumi Salad')).dy;
    expect(curryY, lessThan(saladY));
  });

  testWidgets('search matches word boundaries via the shared normalizer', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();

    await _open(tester);

    await tester.enterText(find.byType(EditableText).first, 'chicken');
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('Halloumi Salad'), findsNothing);

    // Mid-word fragments never match (deterministic search, ADR-0004).
    await tester.enterText(find.byType(EditableText).first, 'hick');
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsNothing);
  });

  testWidgets('the Favorites tab shows only starred recipes', (tester) async {
    await _open(tester);

    expect(find.text('Halloumi Salad'), findsOneWidget);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('Halloumi Salad'), findsNothing);
  });

  testWidgets('an empty Favorites tab explains the affordance', (tester) async {
    await _open(tester, recipes: const [_salad]); // nothing starred
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.textContaining('star a recipe'), findsOneWidget);
  });

  // --- One door, two kinds of thing (step 8.14 / C-D1) ----------------------

  group('the ingredients section', () {
    testWidgets('is absent until something is typed — an empty query is the '
        'shipped browse surface', (tester) async {
      await _open(tester);
      expect(find.text('INGREDIENTS'), findsNothing);
      expect(find.text('Protein bar'), findsNothing);
    });

    testWidgets('appears under the recipe rows when the query hits the '
        'vocabulary', (tester) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      await tester.enterText(find.byType(EditableText).first, 'prot');
      await tester.pumpAndSettle();

      expect(find.text('INGREDIENTS'), findsOneWidget);
      expect(find.text('Protein bar'), findsOneWidget);
      // Still one door: there is no second ＋ for ingredients.
      expect(find.textContaining('new recipe'), findsOneWidget);
    });

    testWidgets('picking one resolves the picker to an INGREDIENT, not a '
        'recipe', (tester) async {
      filterForuiSemanticsAssertions();

      PickedMeal? picked;
      await tester.pumpWidget(_host(onPicked: (p) => picked = p));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'prot');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protein bar'));
      await tester.pumpAndSettle();

      expect(picked, isA<PickedIngredientMeal>());
      expect((picked! as PickedIngredientMeal).ingredient.id, 'i1');
    });
  });
}
