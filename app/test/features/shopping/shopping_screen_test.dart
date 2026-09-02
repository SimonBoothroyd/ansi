import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

/// A canned cook plan for the empty-state branch test.
class _FakeCookPlanRepo implements CookPlanRepository {
  _FakeCookPlanRepo(this.plan);

  final CookPlan plan;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) => Stream.value(plan);
}

/// A canned shopping list; mutations are no-ops (the screen just renders).
class _FakeShoppingRepo implements ShoppingRepository {
  _FakeShoppingRepo(this.list);

  final ShoppingList list;

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) =>
      Stream.value(list);

  @override
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
    required DateTime weekStart,
  }) async {}

  @override
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  }) async {}

  @override
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {}

  @override
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
    String? measureId,
  }) async {}

  @override
  Future<void> removeContribution({required String contributionId}) async {}

  @override
  Future<void> addFreeTextItem({
    required String text,
    String? category,
  }) async {}

  @override
  Future<void> removeEntry({required String entryId}) async {}
}

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const ShoppingView()),
  ),
);

void main() {
  testWidgets('an empty list shows the blank state', (tester) async {
    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(
          _FakeShoppingRepo(const ShoppingList()),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Nothing to buy yet'), findsOneWidget);
    expect(find.text('Add an item'), findsOneWidget);
  });

  testWidgets('an empty list but a live plan explains the missing '
      'ingredients', (tester) async {
    const planned = CookPlan(
      recipes: [
        RecipeCookPlan(
          recipeId: 'r1',
          title: 'Chicken Curry',
          servingsBase: 2,
          sessions: [
            CookSession(
              recipeId: 'r1',
              recipeTitle: 'Chicken Curry',
              servingsBase: 2,
              cookDay: 0,
              covers: [
                CoveredMeal(dayOfWeek: 0, mealSlot: 'Dinner', portions: 2),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(
          _FakeShoppingRepo(const ShoppingList()),
        ),
        cookPlanRepositoryProvider.overrideWithValue(
          _FakeCookPlanRepo(planned),
        ),
      ]),
    );
    await tester.pump(); // shopping list stream
    await tester.pump(); // cook plan stream

    expect(find.text('Nothing to sum yet'), findsOneWidget);
    expect(find.textContaining("don't list any ingredients"), findsOneWidget);
    expect(find.text('Open the library'), findsOneWidget);
  });

  testWidgets('renders grouped items, totals and provenance', (tester) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Baking',
          items: [
            ShoppingItem(
              name: 'Flour',
              ingredientId: 'flour',
              totals: [Quantity(500, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Curry · cook Mon',
                  quantity: 300,
                  unit: g,
                  cookDay: 0,
                ),
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Oat Cookies',
                  quantity: 200,
                  unit: g,
                ),
              ],
            ),
          ],
        ),
        const ShoppingGroup(
          label: 'Non-food',
          items: [ShoppingItem(name: 'Paper towels', entryId: 'e1')],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    expect(find.text('BAKING'), findsOneWidget);
    expect(find.text('Flour'), findsOneWidget);
    expect(find.text('500 g'), findsOneWidget);
    expect(find.text('Curry · cook Mon'), findsOneWidget);
    expect(find.text('NON-FOOD'), findsOneWidget);
    expect(find.text('Paper towels'), findsOneWidget);
    // A numberless non-food staple shows an em dash.
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('add item or top up'), findsOneWidget);
  });

  testWidgets('a nested contribution names both levels (step 8.6 / D4)', (
    tester,
  ) async {
    // The provenance segment the domain builds for a component session: the
    // sub-recipe's own line, then the plan it is cooked for.
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(60, ml)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Sausage Sliders · cook Sat',
                  quantity: 30,
                  unit: ml,
                  cookDay: 5,
                ),
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Romesco Aioli · for Sliders · cook Sat',
                  quantity: 30,
                  unit: ml,
                  cookDay: 5,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    expect(find.text('Sausage Sliders · cook Sat'), findsOneWidget);
    expect(find.text('Romesco Aioli · for Sliders · cook Sat'), findsOneWidget);
    // Summed once, bought once.
    expect(find.text('60 ml'), findsOneWidget);
  });

  testWidgets('an unresolved component makes the list’s silence legible (D4)', (
    tester,
  ) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(30, ml)],
            ),
          ],
        ),
      ],
      unresolvedComponents: const [
        (recipeId: 'sliders', recipeTitle: 'Sausage Sliders', count: 1),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    expect(find.text('SAUSAGE SLIDERS'), findsOneWidget);
    expect(find.text('1 component unresolved — see Cook'), findsOneWidget);
  });
}
