/// The recipe page's per-line macro toggle (design board frames "Macros per
/// line" / "On"): the `⋯` item, the figures under each identity, and the two
/// ways a line that is not in the total stays honest instead of showing a zero.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/macro_line.dart';
import '../../helpers/pump_app.dart';

/// A vocabulary where every id but `tofu` carries per-100 g macros — `tofu` is
/// the stub that keeps the summary honestly incomplete.
IngredientNutrition? _nutritionOf(String id) => id == 'tofu'
    ? (
        macros: null,
        basis: MacrosBasis.perG,
        densityGPerMl: null,
        pieceBasisAmount: null,
      )
    : (
        macros: const Macros(kcal: 100, protein: 10, carb: 20, fat: 5),
        basis: MacrosBasis.perG,
        densityGPerMl: null,
        pieceBasisAmount: null,
      );

/// The recipe under test with the real summation attached, exactly as the
/// repository attaches it on read — the page must never sum anything itself.
Recipe _summarized(Recipe recipe) => recipe.copyWith(
  macros: summarizeRecipeMacros(
    servingsBase: recipe.servingsBase,
    lines: [for (final g in recipe.groups) ...g.items],
    nutritionOf: _nutritionOf,
  ),
);

class _FakeRecipeRepo extends FakeRecipeRepository {
  _FakeRecipeRepo(Recipe recipe) : super(recipe: _summarized(recipe));

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    RecipeSummary(
      id: recipe!.id,
      title: recipe!.title,
      servingsBase: recipe!.servingsBase,
    ),
  ]);
}

/// Chicken (in the total), parsley by the handful (out by rule), a lime marked
/// optional (out by rule), and tofu with no macros (the one fixable refusal).
const _recipe = Recipe(
  id: 'r1',
  title: 'Weeknight Chicken',
  servingsBase: 4,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'i1',
          ingredientId: 'chicken',
          ingredientName: 'Chicken thigh',
          unit: g,
          quantity: 600,
        ),
        LineItem(
          id: 'i2',
          ingredientId: 'parsley',
          ingredientName: 'Parsley',
          unit: handful,
        ),
        LineItem(
          id: 'i3',
          ingredientId: 'lime',
          ingredientName: 'Lime',
          unit: g,
          quantity: 50,
          optional: true,
        ),
        LineItem(
          id: 'i4',
          ingredientId: 'tofu',
          ingredientName: 'Tofu',
          unit: g,
          quantity: 200,
        ),
      ],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, {Recipe recipe = _recipe}) async {
  await tester.pumpAnsiApp(
    const RecipeView(recipeId: 'r1'),
    overrides: [
      recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipe)),
    ],
  );
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('off by default: no line carries macros of its own', (
    tester,
  ) async {
    await _pump(tester);

    // 600 g of a 100 kcal/100 g row is the one line that would print.
    expect(macroText('600 kcal · 60P 120C 30F'), findsNothing);
    expect(find.text('Chicken thigh'), findsOneWidget);
  });

  testWidgets('on: a complete line prints its own macros under its name', (
    tester,
  ) async {
    await _pump(tester);
    await _toggle(tester, 'Show line macros');

    expect(macroText('600 kcal · 60P 120C 30F'), findsOneWidget);
  });

  testWidgets('the figures are the line AS SHOWN — they move with the scaler, '
      'unlike the per-serving strip', (tester) async {
    await _pump(tester);
    await _toggle(tester, 'Show line macros');

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();

    // 5 servings of a 4-serving recipe: 750 g of chicken, and its macros with
    // it. The strip above is unmoved — a serving is the same serving.
    expect(macroText('750 kcal · 75P 150C 38F'), findsOneWidget);
    expect(macroText('600 kcal · 60P 120C 30F'), findsNothing);
  });

  testWidgets('a line excluded BY RULE says why, in the panel’s words — never '
      'a zero', (tester) async {
    await _pump(tester);
    await _toggle(tester, 'Show line macros');

    // The handful says why. The optional lime says nothing here: its tag
    // already said it, and twice on one line is once too many.
    expect(find.text('not counted'), findsOneWidget);
    expect(find.text('optional'), findsOneWidget);
    expect(macroText('0 kcal · 0P 0C 0F'), findsNothing);
  });

  testWidgets('a line the total is WAITING ON is not told twice — its amber '
      'marker already carries the reason', (tester) async {
    await _pump(tester);
    await _toggle(tester, 'Show line macros');

    expect(find.text('stub ingredient'), findsOneWidget);
  });

  testWidgets('a resolved line still prints while the SUMMARY refuses', (
    tester,
  ) async {
    await _pump(tester);
    await _toggle(tester, 'Show line macros');

    // Tofu is a stub, so there is no per-serving total at all…
    expect(find.text('incomplete'), findsOneWidget);
    // …and the chicken line is still honest about itself.
    expect(macroText('600 kcal · 60P 120C 30F'), findsOneWidget);
  });

  testWidgets('toggling it back off removes every line figure', (tester) async {
    await _pump(tester);
    await _toggle(tester, 'Show line macros');
    await _toggle(tester, 'Hide line macros');

    expect(macroText('600 kcal · 60P 120C 30F'), findsNothing);
    expect(find.text('not counted'), findsNothing);
  });

  testWidgets('a folded multi-use row prints figures only when EVERY use '
      'joined — never a partial', (tester) async {
    const folded = Recipe(
      id: 'r1',
      title: 'Garlic Two Ways',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          items: [
            LineItem(
              id: 'i1',
              ingredientId: 'garlic',
              ingredientName: 'Garlic',
              unit: g,
              quantity: 20,
              note: 'finely chopped',
            ),
            LineItem(
              id: 'i2',
              ingredientId: 'garlic',
              ingredientName: 'Garlic',
              unit: handful,
              note: 'sliced',
            ),
          ],
        ),
      ],
    );
    await _pump(tester, recipe: folded);
    await _toggle(tester, 'Show line macros');

    // The 20 g use resolved and the handful did not, so the row says the
    // exclusion rather than printing the half it could add up.
    expect(macroText('20 kcal · 2P 4C 1F'), findsNothing);
    expect(find.text('not counted'), findsOneWidget);
  });

  testWidgets('the toggle is offered only from the tab it changes', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Method'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.text('Show line macros'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
  });
}
