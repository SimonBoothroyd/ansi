import 'dart:async';

import 'package:ansi/core/theme/mise_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_macro_panel.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/shared/incomplete_macros.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Serves the one recipe the page under test renders, over a controllable
/// stream so a live vocab change can be pushed mid-test.
class _FakeRecipeRepo implements RecipeRepository {
  _FakeRecipeRepo(this.recipes);

  final Stream<Recipe?> recipes;

  @override
  Stream<Recipe?> watchRecipe(String id) => recipes;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => const Stream.empty();

  @override
  Future<void> saveRecipe(Recipe recipe) async {}

  @override
  Future<void> deleteRecipe(String id) async {}

  @override
  Future<void> setFavorite(String id, bool favorite) async {}
}

Widget _host(Widget child, {Stream<Recipe?>? recipes}) => ProviderScope(
  overrides: [
    if (recipes != null)
      recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipes)),
  ],
  child: MaterialApp(
    home: FTheme(data: miseThemeData(), child: child),
  ),
);

const _complete = RecipeMacroSummary(
  perServing: Macros(kcal: 611.6, protein: 41.4, carb: 17.7, fat: 38.5),
);

Recipe _recipe(RecipeMacroSummary? macros) => Recipe(
  id: '1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
  macros: macros,
  groups: const [
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
      ],
    ),
  ],
);

void main() {
  testWidgets('a complete summary renders the four per-serving cells', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const RecipeMacroPanel(summary: _complete)));

    expect(find.text('PER SERVING'), findsOneWidget);
    expect(find.text('612'), findsOneWidget); // kcal, rounded
    expect(find.text('KCAL'), findsOneWidget);
    expect(find.text('41 g'), findsOneWidget);
    expect(find.text('PROTEIN'), findsOneWidget);
    expect(find.text('18 g'), findsOneWidget);
    expect(find.text('CARB'), findsOneWidget);
    expect(find.text('39 g'), findsOneWidget);
    expect(find.text('FAT'), findsOneWidget);
    expect(find.byType(IncompleteBadge), findsNothing);
  });

  testWidgets('an incomplete summary shows the badge and no numbers', (
    tester,
  ) async {
    const summary = RecipeMacroSummary(stubLines: 2, unconvertibleLines: 1);
    await tester.pumpWidget(_host(const RecipeMacroPanel(summary: summary)));

    expect(find.byType(IncompleteBadge), findsOneWidget);
    // The picker rows' exact words, so the two surfaces refuse identically.
    expect(find.text(incompleteNote(summary)), findsOneWidget);
    expect(find.text('2 stub lines · 1 unconvertible'), findsOneWidget);
    // Invariant 3: a partial total never surfaces, and nothing reads as 0.
    expect(find.text('KCAL'), findsNothing);
    expect(find.textContaining('0 g'), findsNothing);
  });

  testWidgets('a recipe with no lines says so rather than showing zeros', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const RecipeMacroPanel(summary: RecipeMacroSummary(noLines: true))),
    );

    expect(find.text('no ingredients yet'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('no summary at all draws nothing', (tester) async {
    await tester.pumpWidget(_host(const RecipeMacroPanel(summary: null)));

    expect(find.text('PER SERVING'), findsNothing);
    expect(find.byType(IncompleteBadge), findsNothing);
  });

  testWidgets('RecipeView renders the panel below the ingredients', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RecipeView(recipeId: '1'),
        recipes: Stream.value(_recipe(_complete)),
      ),
    );
    await tester.pump();

    expect(find.byType(RecipeMacroPanel), findsOneWidget);
    expect(find.text('612'), findsOneWidget);
    // Placement: after the last ingredient line, per the board's Recipe frame.
    final ingredient = tester.getBottomLeft(
      find.textContaining('Chicken thigh', findRichText: true).first,
    );
    expect(
      tester.getTopLeft(find.text('PER SERVING')).dy,
      greaterThan(ingredient.dy),
    );
  });

  testWidgets('the servings scaler never moves the per-serving numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RecipeView(recipeId: '1'),
        recipes: Stream.value(_recipe(_complete)),
      ),
    );
    await tester.pump();

    expect(find.text('600 g'), findsOneWidget);
    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();

    // The lines scaled (5 servings ⇒ ×1.25) but a serving is still a serving.
    expect(find.text('750 g'), findsOneWidget);
    expect(find.text('612'), findsOneWidget);
    expect(find.text('41 g'), findsOneWidget);
  });

  testWidgets('the panel is derived from the watched aggregate, not a '
      'one-shot read', (tester) async {
    final controller = StreamController<Recipe?>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '1'), recipes: controller.stream),
    );
    controller.add(_recipe(const RecipeMacroSummary(stubLines: 1)));
    await tester.pump();
    expect(find.byType(IncompleteBadge), findsOneWidget);

    // The vocab row gains macros upstream: the same watch re-emits and the
    // badge becomes numbers, with no navigation.
    controller.add(_recipe(_complete));
    await tester.pump();
    expect(find.byType(IncompleteBadge), findsNothing);
    expect(find.text('612'), findsOneWidget);
  });
}
