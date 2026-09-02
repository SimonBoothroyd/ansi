import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

/// A canned cook plan: emits a fixed plan built from the planned recipes, or
/// the plan handed straight to the `.plan` constructor.
class _FakeCookPlanRepo implements CookPlanRepository {
  _FakeCookPlanRepo(List<PlannedRecipe> recipes)
    : _plan = buildCookPlan(recipes);

  _FakeCookPlanRepo.plan(this._plan);

  final CookPlan _plan;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) => Stream.value(_plan);
}

/// The recipe list the component card reads its target's yield off.
class _FakeRecipeRepo implements RecipeRepository {
  _FakeRecipeRepo({this.yieldQty, this.yieldUnit});

  final double? yieldQty;
  final Unit? yieldUnit;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    RecipeSummary(
      id: 'aioli',
      title: 'Romesco Aioli',
      servingsBase: 4,
      yieldQty: yieldQty,
      yieldUnit: yieldUnit,
    ),
  ]);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);

  @override
  Future<void> saveRecipe(Recipe recipe) async {}

  @override
  Future<void> deleteRecipe(String id) async {}

  @override
  Future<void> setFavorite(String id, bool favorite) async {}

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const CookView()),
  ),
);

PlannedRecipe _recipe(
  String title,
  Map<int, int> days, {
  int? keeps,
  bool freezable = false,
}) => PlannedRecipe(
  recipeId: title,
  title: title,
  servingsBase: 2,
  keepsForDays: keeps,
  freezable: freezable,
  meals: [
    for (final e in days.entries)
      CoveredMeal(dayOfWeek: e.key, mealSlot: 'Dinner', portions: e.value),
  ],
);

void main() {
  testWidgets('an empty plan shows the blank state', (tester) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          _FakeCookPlanRepo(const []),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Nothing to cook yet'), findsOneWidget);
    expect(find.text('Plan the week'), findsOneWidget);
  });

  testWidgets('a split recipe renders its sessions and split note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          // Mon + Sat, keeps 3 → two batches.
          _FakeCookPlanRepo([
            _recipe('Chicken Curry', {0: 2, 5: 2}, keeps: 3),
          ]),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Chicken Curry'), findsOneWidget);
    expect(find.text('Cook Mon'), findsOneWidget);
    expect(find.text('Cook Sat'), findsOneWidget);
    expect(find.textContaining('cook it again, fresh'), findsOneWidget);
  });

  testWidgets('a freezable far meal shows the freezer note', (tester) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          // Tue + Sat, keeps 3, freezable → one batch, Saturday frozen.
          _FakeCookPlanRepo([
            _recipe('House Ragù', {1: 2, 5: 2}, keeps: 3, freezable: true),
          ]),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Cook Tue'), findsOneWidget);
    expect(find.textContaining('freezes'), findsOneWidget);
    expect(find.textContaining("Saturday's share"), findsOneWidget);
  });

  group('component sessions (step 8.6 / D3, board frame f)', () {
    testWidgets('a component card reads in batches, names its parents, and '
        'says what is left over', (tester) async {
      await tester.pumpWidget(
        _host([
          cookPlanRepositoryProvider.overrideWithValue(
            _FakeCookPlanRepo.plan(_planWith(yields: [(qty: 1, unit: cup)])),
          ),
          recipeRepositoryProvider.overrideWithValue(
            _FakeRecipeRepo(yieldQty: 1, yieldUnit: cup),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Romesco Aioli · for Sausage Sliders'), findsOneWidget);
      expect(
        find.text('derived from a component line · keeps 5 d'),
        findsOneWidget,
      );
      // Ready BY the parent's cook day, denominated in batches.
      expect(find.text('Cook by Sat'), findsOneWidget);
      expect(find.text('×0.25 batch'), findsOneWidget);
      expect(
        find.text(
          'covers Sausage Sliders · cook Sat — makes 1 cup, you need 0.25',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nothing here tracks the leftover'),
        findsOneWidget,
      );
    });

    testWidgets('a component with no yield is a named gap, never a ×1', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          cookPlanRepositoryProvider.overrideWithValue(
            _FakeCookPlanRepo.plan(_planWith(yields: const [])),
          ),
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Romesco Aioli · for Sausage Sliders'), findsOneWidget);
      expect(
        find.text('derived from a component line · yield not set'),
        findsOneWidget,
      );
      expect(find.text('no scale'), findsOneWidget);
      expect(
        find.text('Romesco Aioli doesn’t say how much it makes'),
        findsOneWidget,
      );
      expect(find.text('Set the yield'), findsOneWidget);
      // The refusal this whole state exists to avoid: the only scale on the
      // screen is the sliders' own ×1 — the gap contributes none.
      expect(find.textContaining('×'), findsOneWidget);
      expect(find.text('×1'), findsOneWidget);
      expect(find.text('×1 batch'), findsNothing);
    });
  });
}

/// A week with the sliders planned for Saturday and a ¼-cup aioli component,
/// where the aioli states [yields] (empty ⇒ the gap state).
CookPlan _planWith({required List<YieldDenomination> yields}) => buildCookPlan(
  const [
    PlannedRecipe(
      recipeId: 'sliders',
      title: 'Sausage Sliders',
      servingsBase: 8,
      meals: [CoveredMeal(dayOfWeek: 5, mealSlot: 'Dinner', portions: 8)],
    ),
  ],
  components: {
    'sliders': (
      title: 'Sausage Sliders',
      servingsBase: 8.0,
      keepsForDays: null,
      freezable: false,
      freezerDays: null,
      yields: const <YieldDenomination>[],
      components: [(subRecipeId: 'aioli', quantity: 0.25, unit: cup)],
    ),
    'aioli': (
      title: 'Romesco Aioli',
      servingsBase: 4.0,
      keepsForDays: 5,
      freezable: false,
      freezerDays: null,
      yields: yields,
      components: const <ComponentLine>[],
    ),
  },
);
