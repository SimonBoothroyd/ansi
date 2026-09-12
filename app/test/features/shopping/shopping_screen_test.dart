import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart' show mondayOf;
import 'package:ansi/features/planning/presentation/week_header.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';

/// A canned shopping list; mutations are no-ops (the screen just renders).
class _FakeShoppingRepo implements ShoppingRepository {
  _FakeShoppingRepo(this.list, {this.tickThrows = false});

  final ShoppingList list;

  /// Whether a check-off refuses — the aisle case the status line and the
  /// failure toast exist for.
  final bool tickThrows;
  int tickCalls = 0;

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
  }) async {
    tickCalls++;
    if (tickThrows) throw StateError('RLS denied');
  }

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
    required DateTime weekStart,
    String? category,
  }) async {}

  @override
  Future<void> removeEntry({required String entryId}) async {}
}

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: const FToaster(child: ShoppingView()),
    ),
  ),
);

void main() {
  testWidgets('an empty list is a quiet line INSIDE the list '
      'chrome', (tester) async {
    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(
          _FakeShoppingRepo(const ShoppingList()),
        ),
      ]),
    );
    await tester.pump();

    // The chrome stays — and the chrome is the week switcher, not a screen
    // name (0025 D7c): the lit tab in the bar is what says "Shop".
    expect(find.byType(WeekSwitcher), findsOneWidget);
    expect(find.textContaining('Shopping list'), findsNothing);
    expect(
      find.textContaining('nothing to buy for this week yet'),
      findsOneWidget,
    );
    expect(find.text('plan a meal'), findsOneWidget);
    // The add-item door works with no plan at all, so it is never swapped away.
    expect(find.textContaining('add item or top up'), findsOneWidget);
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
          FakeCookPlanRepository(planned),
        ),
      ]),
    );
    await tester.pump(); // shopping list stream
    await tester.pump(); // cook plan stream

    // The two causes are still told apart — and now inside the list chrome,
    // with `Add an item` still on screen (D5b/D5c).
    expect(find.textContaining('nothing to sum yet'), findsOneWidget);
    expect(find.textContaining('list no ingredients'), findsOneWidget);
    expect(find.text('add ingredients to a recipe'), findsOneWidget);
    expect(
      find.textContaining('add item or top up'),
      findsOneWidget,
      reason: 'a staple works with no plan at all — never take that away',
    );
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

  testWidgets('a single-source row still says where it came from', (
    tester,
  ) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Dairy',
          items: [
            ShoppingItem(
              name: 'Halloumi',
              ingredientId: 'halloumi',
              totals: [Quantity(250, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Charred Broccoli & Halloumi Salad · cook Wed',
                  quantity: 250,
                  unit: g,
                  cookDay: 2,
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

    expect(
      find.text('Charred Broccoli & Halloumi Salad · cook Wed'),
      findsOneWidget,
    );
  });

  testWidgets('a row asked for in one measure is shopped in it', (
    tester,
  ) async {
    const can = Measure(id: 'ml', label: 'can (400 g), drained', amount: 240);
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Canned Lentils',
              ingredientId: 'lentils',
              totals: [Quantity(240, g)],
              measureTotal: const (amount: 1, measure: can),
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Dal · cook Mon',
                  quantity: 1,
                  measure: can,
                  cookDay: 0,
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

    // The total is what goes in the basket, not the 8.47 oz it weighs —
    // twice over, because the one line behind it says the same words.
    expect(find.text('1 can (400 g), drained'), findsNWidgets(2));
    // …with the honest mass beside the total, never instead of it.
    expect(find.text('240 g'), findsOneWidget);
    expect(find.text('Dal · cook Mon'), findsOneWidget);
    expect(find.textContaining('oz'), findsNothing);
  });

  testWidgets('a nested contribution names both levels', (tester) async {
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

  testWidgets('a tick that does not land says so, in the item’s own name', (
    tester,
  ) async {
    const list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Non-food',
          items: [ShoppingItem(name: 'Paper towels', entryId: 'e1')],
        ),
      ],
    );
    final repo = _FakeShoppingRepo(list, tickThrows: true);

    await tester.pumpWidget(
      _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
    );
    await tester.pump();

    await tester.tap(find.text('Paper towels'));
    await tester.pumpAndSettle();

    expect(repo.tickCalls, 1);
    expect(find.text('Couldn’t tick Paper towels.'), findsOneWidget);
  });

  testWidgets('an unresolved component makes the list’s silence '
      'legible', (tester) async {
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

  testWidgets('a line at a RETIRED ingredient is named at the bottom, with '
      'the pick it needs — never bought from the dead row', (tester) async {
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
      retiredIngredients: const [
        (
          heading: 'Curry',
          ingredientName: 'Sauerkraut',
          site: RetiredIngredientSite.recipeLine,
        ),
        (
          heading: 'Snack · Tue',
          ingredientName: 'Protein bar',
          site: RetiredIngredientSite.planEntry,
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // Neither is an aisle row; both are named, and each says where the pick
    // is — the recipe for a recipe line, the plan for a bare-ingredient meal.
    expect(find.text('CURRY'), findsOneWidget);
    expect(
      find.text('Sauerkraut · ingredient removed · pick again in the recipe'),
      findsOneWidget,
    );
    expect(find.text('SNACK · TUE'), findsOneWidget);
    expect(
      find.text('Protein bar · ingredient removed · pick again in the plan'),
      findsOneWidget,
    );
    // Amber, like the unresolved echo: a broken line is a defect somebody can
    // fix, not a rule somebody chose.
    expect(
      find.descendant(
        of: find.byType(RetiredIngredientEcho),
        matching: find.byIcon(FLucideIcons.flag),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('an optional line that left the list is named by its recipe, '
      'muted — a rule, not a defect', (tester) async {
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
      optionalLines: const [
        (
          recipeId: 'curry',
          recipeTitle: 'Weeknight Chicken Curry',
          names: ['lime', 'coriander'],
          lineIds: ['li-lime', 'li-coriander'],
          reason: LineDropReason.optional,
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    expect(find.text('WEEKNIGHT CHICKEN CURRY'), findsOneWidget);
    expect(
      find.textContaining('2 optional lines not listed — lime, coriander'),
      findsOneWidget,
    );
    // Muted, not amber: the unresolved echo's flag icon is not on this row.
    expect(
      find.descendant(
        of: find.byType(OptionalLinesEcho),
        matching: find.byIcon(FLucideIcons.flag),
      ),
      findsNothing,
    );
  });

  group('the echo row is a door', () {
    /// The names are kept short on purpose: the test font is fixed-width, and
    /// a longer sentence ellipsizes before the name a tap is aimed at.
    ShoppingList listWith(
      LineDropReason reason, {
      List<String> names = const ['lime'],
      List<String> lineIds = const ['li-lime'],
    }) => ShoppingList(
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
      optionalLines: [
        (
          recipeId: 'curry',
          recipeTitle: 'Weeknight Chicken Curry',
          names: names,
          lineIds: lineIds,
          reason: reason,
        ),
      ],
    );

    testWidgets('tapping an optional name ticks that line in for the '
        "shop's week", (tester) async {
      final variants = FakeWeekVariantRepository();
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(listWith(LineDropReason.optional)),
          ),
          weekVariantRepositoryProvider.overrideWithValue(variants),
        ]),
      );
      await tester.pump();

      await tester.tapOnText(find.textRange.ofSubstring('lime'));
      await tester.pump();

      expect(variants.ticked, hasLength(1));
      final write = variants.ticked.single;
      expect(write.recipeId, 'curry');
      expect(write.lineId, 'li-lime');
      expect(write.included, isTrue);
      expect(write.weekStart, mondayOf(DateTime.now()));
    });

    testWidgets('a line the WEEK left out is not a door — that change is '
        'undone where it was made', (tester) async {
      final variants = FakeWeekVariantRepository();
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(
              listWith(
                LineDropReason.thisWeek,
                names: const ['wine'],
                lineIds: const ['li-wine'],
              ),
            ),
          ),
          weekVariantRepositoryProvider.overrideWithValue(variants),
        ]),
      );
      await tester.pump();

      await tester.tapOnText(find.textRange.ofSubstring('wine'));
      await tester.pump();

      expect(variants.ticked, isEmpty);
    });
  });
}
