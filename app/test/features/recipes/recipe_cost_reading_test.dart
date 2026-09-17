/// The recipe page's COST reading (design board "A cost · the panel flips" /
/// "A cost · per line, following the panel"): the chip pair over the strip,
/// the one menu item that follows it, and the figures under each line.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/pump_app.dart';

PriceObservation _price({
  int cents = 110,
  String store = "TJ's",
  String? packLabel,
}) => PriceObservation(
  lineId: 'rl-$store',
  receiptId: 'r-1',
  cents: cents,
  packBasisAmount: 100,
  basis: MacrosBasis.perG,
  store: store,
  purchasedAt: DateTime.utc(2026, 9, 3),
  packLabel: packLabel,
);

/// Chicken priced, parsley by the handful (out by rule), tomatoes with no
/// price at all — the three states the strip has to say something about.
IngredientPricing? _pricingOf(String id) => (
  row: (basis: MacrosBasis.perG, densityGPerMl: null, pieceBasisAmount: null),
  price: id == 'chicken' ? _price() : null,
);

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
          ingredientId: 'tomatoes',
          ingredientName: 'Chopped tomatoes',
          unit: g,
          quantity: 400,
        ),
      ],
    ),
  ],
);

/// The recipe with the real cost summation attached, exactly as the repository
/// attaches it — the page must never sum anything itself.
RecipeCostSummary _costOf(Recipe recipe, {bool priceEverything = false}) =>
    summarizeRecipeCost(
      servingsBase: recipe.servingsBase,
      lines: [for (final group in recipe.groups) ...group.items],
      pricingOf: priceEverything
          ? (_) => (
              row: (
                basis: MacrosBasis.perG,
                densityGPerMl: null,
                pieceBasisAmount: null,
              ),
              price: _price(),
            )
          : _pricingOf,
    );

/// Every row carries per-100 g macros, so the Macros reading has a real strip
/// to be exactly itself — the flip must change the figures and nothing else.
IngredientNutrition? _nutritionOf(String id) => (
  macros: const Macros(kcal: 100, protein: 10, carb: 20, fat: 5),
  basis: MacrosBasis.perG,
  densityGPerMl: null,
  pieceBasisAmount: null,
);

Recipe _summarized(Recipe recipe) => recipe.copyWith(
  macros: summarizeRecipeMacros(
    servingsBase: recipe.servingsBase,
    lines: [for (final group in recipe.groups) ...group.items],
    nutritionOf: _nutritionOf,
  ),
);

class _FakeRecipeRepo extends FakeRecipeRepository {
  _FakeRecipeRepo(Recipe recipe, {bool priceEverything = false})
    : super(
        recipe: _summarized(recipe),
        costs: {recipe.id: _costOf(recipe, priceEverything: priceEverything)},
      );

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    RecipeSummary(
      id: recipe!.id,
      title: recipe!.title,
      servingsBase: recipe!.servingsBase,
    ),
  ]);
}

Future<void> _pump(WidgetTester tester, {bool priceEverything = false}) async {
  await tester.pumpAnsiApp(
    const RecipeView(recipeId: 'r1'),
    overrides: [
      recipeRepositoryProvider.overrideWithValue(
        _FakeRecipeRepo(_recipe, priceEverything: priceEverything),
      ),
    ],
  );
  await tester.pumpAndSettle();
}

Future<void> _flipToCost(WidgetTester tester) async {
  await tester.tap(find.text('Cost'));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the strip opens on Macros, with the pair over it', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Macros'), findsOneWidget);
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('per serving'), findsOneWidget);
    // The old micro-label is what the pair replaced — one header, not two.
    expect(find.text('PER SERVING'), findsNothing);
    expect(find.text('UNPRICED'), findsNothing);
  });

  testWidgets('flipped to Cost, an unpriced line takes the cells', (
    tester,
  ) async {
    await _pump(tester);
    await _flipToCost(tester);

    expect(find.text('A SERVING'), findsNothing);
    expect(find.text('UNPRICED'), findsOneWidget);
    expect(find.text('Chopped tomatoes · no price yet'), findsOneWidget);
    // Out by the macro rule, named in its own row and never as a gap.
    expect(find.text('NOT COUNTED'), findsOneWidget);
    expect(find.text('Parsley · handful'), findsOneWidget);
  });

  testWidgets('with every line priced, the three cells read', (tester) async {
    await _pump(tester, priceEverything: true);
    await _flipToCost(tester);

    // 600 g + 400 g at $1.10/100 g = $11.00, over 4 servings.
    expect(find.text(r'$11.00'), findsOneWidget);
    expect(find.text('THE RECIPE'), findsOneWidget);
    expect(find.text(r'$2.75'), findsOneWidget);
    expect(find.text('A SERVING'), findsOneWidget);
    expect(find.text('Sep'), findsOneWidget);
  });

  testWidgets('flipping back to Macros is exactly the macro strip', (
    tester,
  ) async {
    await _pump(tester);
    await _flipToCost(tester);
    await tester.tap(find.text('Macros'));
    await tester.pumpAndSettle();

    expect(find.text('UNPRICED'), findsNothing);
    expect(find.text('OLDEST'), findsNothing);
  });

  group('Show line figures', () {
    testWidgets('is one item, and it prints what the panel reads', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byIcon(FLucideIcons.ellipsis), findsOneWidget);
      await _menu(tester, 'Show line figures');

      // Under Macros: the macro record. Nothing about money.
      expect(find.textContaining(r'$6.60'), findsNothing);

      await _flipToCost(tester);
      // Under Cost: the whole chain — figure, unit price, store and month.
      expect(find.text(r"$6.60 · $1.10 / 100 g · TJ's, Sep"), findsOneWidget);
      expect(find.text('no price yet'), findsOneWidget);
      expect(find.text('not counted'), findsOneWidget);
    });

    testWidgets('the menu item names the state it will leave', (tester) async {
      await _pump(tester);
      await _menu(tester, 'Show line figures');
      await tester.tap(find.byIcon(FLucideIcons.ellipsis));
      await tester.pumpAndSettle();
      expect(find.text('Hide line figures'), findsOneWidget);
      expect(find.text('Show line macros'), findsNothing);
    });

    testWidgets('a line figure moves with the scaler', (tester) async {
      await _pump(tester);
      await _menu(tester, 'Show line figures');
      await _flipToCost(tester);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();
      // 5 servings of a 4-serving recipe: ×1.25 on the line, and the strip's
      // per-serving figure would not have moved had there been one.
      expect(find.text(r"$8.25 · $1.10 / 100 g · TJ's, Sep"), findsOneWidget);
    });
  });
}
