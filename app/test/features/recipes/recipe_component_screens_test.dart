/// The recipe page's 8.6 faces (design board frames a · b): a component line's
/// recipe chip and the push behind it, the dangling-link degrade, the "makes"
/// pills, the conditional "Used in · N" tab, and D5's delete refusal.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_chip.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// A repository over a fixed set of recipes plus canned back-links.
/// A library keyed by id, so a component line can be followed to its target,
/// plus the back-links the "Used in" tab and the delete refusal both read.
class _FakeRecipeRepo extends FakeRecipeRepository {
  _FakeRecipeRepo(this.recipes, {this.uses = const []});

  final Map<String, Recipe> recipes;
  final List<RecipeUse> uses;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    for (final r in recipes.values)
      RecipeSummary(id: r.id, title: r.title, servingsBase: r.servingsBase),
  ]);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(recipes[id]);

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => uses;
}

Widget _host(_FakeRecipeRepo repo) => routedHost(
  initial: '/recipes/sliders',
  overrides: [recipeRepositoryProvider.overrideWithValue(repo)],
  routes: {
    '/recipes/:id': (_, state) =>
        RecipeView(recipeId: state.pathParameters['id']!),
  },
);

const _aioli = SubRecipeTarget(
  id: 'aioli',
  title: 'Romesco Aioli',
  yieldQty: 1,
  yieldUnit: cup,
);

Recipe _sliders({LineItem? component}) => Recipe(
  id: 'sliders',
  title: 'Sausage Sliders',
  servingsBase: 8,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        const LineItem(
          id: 'i1',
          ingredientId: 'oil',
          ingredientName: 'Olive oil',
          unit: tbsp,
          quantity: 2,
        ),
        component ??
            const LineItem(
              id: 'i2',
              subRecipeId: 'aioli',
              subRecipe: _aioli,
              ingredientName: 'Romesco Aioli',
              unit: cup,
              quantity: 0.25,
            ),
      ],
    ),
  ],
);

const _aioliRecipe = Recipe(
  id: 'aioli',
  title: 'Romesco Aioli',
  servingsBase: 4,
  yieldQty: 1,
  yieldUnit: cup,
);

void main() {
  testWidgets('a component line keeps the v3 grammar and wears a recipe chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_FakeRecipeRepo({'sliders': _sliders(), 'aioli': _aioliRecipe})),
    );
    await tester.pumpAndSettle();

    // The amount column is the ordinary one — the identity cell is all that
    // changed (D1).
    expect(find.text('¼ cup'), findsOneWidget);
    expect(find.byType(RecipeChip), findsOneWidget);
    expect(find.text('Romesco Aioli'), findsOneWidget);
    // The ingredient line beside it is untouched.
    expect(find.text('2 tbsp'), findsOneWidget);
  });

  testWidgets('a line said in the target’s own word prints that word, and a '
      'word that has gone prints the number alone', (tester) async {
    await tester.pumpWidget(
      _host(
        _FakeRecipeRepo({
          'sliders': _sliders(
            component: const LineItem(
              id: 'i2',
              subRecipeId: 'aioli',
              subRecipe: SubRecipeTarget(
                id: 'aioli',
                title: 'Romesco Aioli',
                yieldQty: 1,
                yieldUnit: cup,
                measures: [
                  RecipeMeasure(
                    id: 'm-blob',
                    recipeId: 'aioli',
                    label: 'blob',
                    amount: 50,
                    unit: ml,
                  ),
                ],
              ),
              ingredientName: 'Romesco Aioli',
              quantity: 3,
              recipeMeasureId: 'm-blob',
            ),
          ),
          'aioli': _aioliRecipe,
        }),
      ),
    );
    await tester.pumpAndSettle();

    // The word is read off the target's LIVE measures, never joined onto the
    // line, which is what makes a re-stated `blob` follow through at once.
    expect(find.text('3 blob'), findsOneWidget);

    // Retired on the other recipe: the number is kept and there is nothing
    // honest to put where the word was. It is never re-read as a count.
    await tester.pumpWidget(
      _host(
        _FakeRecipeRepo({
          'sliders': _sliders(
            component: const LineItem(
              id: 'i2',
              subRecipeId: 'aioli',
              subRecipe: _aioli,
              ingredientName: 'Romesco Aioli',
              quantity: 3,
              recipeMeasureId: 'm-blob',
            ),
          ),
          'aioli': _aioliRecipe,
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(find.text('3 piece'), findsNothing);
  });

  testWidgets('the chip pushes the target recipe', (tester) async {
    await tester.pumpWidget(
      _host(_FakeRecipeRepo({'sliders': _sliders(), 'aioli': _aioliRecipe})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RecipeChip));
    await tester.pumpAndSettle();

    // The aioli's own page: its hero says what a batch makes.
    expect(find.text('makes 1 cup'), findsOneWidget);
    expect(find.text('serves 4'), findsOneWidget);
  });

  testWidgets('a dangling link reads as the text it stored, and says '
      'so', (tester) async {
    await tester.pumpWidget(
      _host(
        _FakeRecipeRepo({
          'sliders': _sliders(
            component: const LineItem(
              id: 'i2',
              subRecipeId: 'gone',
              ingredientName: 'Romesco Aioli',
              unit: cup,
              quantity: 0.25,
            ),
          ),
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RecipeChip), findsNothing);
    expect(
      find.textContaining('linked recipe missing', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a two-denomination yield reads as one sentence in two pills', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _FakeRecipeRepo({
          'sliders': const Recipe(
            id: 'sliders',
            title: 'Garlic Butter',
            servingsBase: 4,
            yieldQty: 250,
            yieldUnit: g,
            yieldQty2: 16,
            yieldUnit2: tbsp,
          ),
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('makes 250 g'), findsOneWidget);
    expect(find.text('· 16 tbsp'), findsOneWidget);
  });

  testWidgets('a recipe used in nothing keeps the two-tab '
      'page', (tester) async {
    await tester.pumpWidget(
      _host(_FakeRecipeRepo({'sliders': _aioliRecipe.copyWith(id: 'sliders')})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Method'), findsOneWidget);
    expect(find.textContaining('Used in'), findsNothing);
  });

  testWidgets('the "Used in · N" tab appears with the count, and its rows push '
      'the parent', (tester) async {
    final repo = _FakeRecipeRepo(
      {'sliders': _aioliRecipe.copyWith(id: 'sliders'), 'parent': _sliders()},
      uses: const [
        RecipeUse(
          lineId: 'i2',
          recipeId: 'parent',
          title: 'Sausage Sliders',
          quantity: 0.25,
          unit: cup,
          amount: ResolvedComponentAmount(0.25, against: (qty: 1, unit: cup)),
        ),
        RecipeUse(
          lineId: 'i9',
          recipeId: 'toasts',
          title: 'Romesco Toasts',
          quantity: 1,
          unit: batches,
          amount: ResolvedComponentAmount(1),
        ),
      ],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('Used in · 2'), findsOneWidget);
    await tester.tap(find.text('Used in · 2'));
    await tester.pumpAndSettle();

    expect(find.text('¼ cup · ¼ of a batch'), findsOneWidget);
    expect(find.text('1 batch'), findsOneWidget);

    await tester.tap(find.text('Sausage Sliders'));
    await tester.pumpAndSettle();
    // The parent's page: its own component line is there.
    expect(find.text('¼ cup'), findsOneWidget);
  });

  testWidgets('delete is refused with the count while something points '
      'here', (tester) async {
    filterForuiSemanticsAssertions();
    final repo = _FakeRecipeRepo(
      {'sliders': _aioliRecipe.copyWith(id: 'sliders')},
      uses: const [
        RecipeUse(
          lineId: 'i2',
          recipeId: 'parent',
          title: 'Sausage Sliders',
          quantity: 0.25,
          unit: cup,
          amount: ResolvedComponentAmount(0.25),
        ),
      ],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('Used in 1 recipe (1 line). Change those lines first.'),
      findsOneWidget,
    );
    expect(repo.deleted, isEmpty);
  });
}
