/// Two rules, each read where it belongs (ADR-0017 rule 1), over the real
/// schema: the Shop and Ask's answer about the trip read the cheapest price
/// seen in the window, and the recipe page, the Week's figure and Ask's other
/// costs read the latest.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/ask/domain/ask_tool_runner.dart';
import 'package:ansi/features/ask/presentation/ask_figures_wiring.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:ansi/features/ingredients/data/price_repository_impl.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/shopping_view_models.dart';
import 'package:ansi/shared/cost_words.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:powersync/powersync.dart';

import '../../helpers/measure_fixtures.dart';
import '../../helpers/test_db.dart';

final _thisWeek = DateTime(2026, 10, 19);

/// 240 g of rice: the aioli's one line, and the Shop's one row.
final _list = ShoppingList(
  groups: [
    ShoppingGroup(
      label: 'Pantry',
      items: [
        ShoppingItem(
          name: 'Rice',
          ingredientId: 'ing-rice',
          entryId: 'e-rice',
          totals: [Quantity(240, g)],
        ),
      ],
    ),
  ],
);

class _ListOnly extends Fake implements ShoppingRepository {
  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) =>
      Stream.value(_list);
}

Map<String, Object?> _json(String s) => jsonDecode(s) as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late Directory dir;
  late ProviderContainer container;
  late List<Override> overrides;

  setUp(() async {
    (db, dir) = await openTestDb();
    // TJ's, 3 Sep: $5.00 a kilo, 50¢ / 100 g — the cheapest in the window.
    await seedPricedRice(db);
    // Whole Foods, 20 Oct: $7.00 a kilo, 70¢ / 100 g — the latest.
    await db.execute(
      'INSERT INTO receipt (id, household_id, store, purchased_at, source, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['rc2', 'h', 'Whole Foods', '2026-10-20', 'photo', '2026-10-20'],
    );
    await db.execute(
      'INSERT INTO receipt_line (id, household_id, receipt_id, ingredient_id, '
      'cents, discount_cents, kind, pack_basis_amount, sort_order, created_at) '
      'VALUES (?, ?, ?, ?, ?, 0, ?, ?, 0, ?)',
      ['rl2', 'h', 'rc2', 'ing-rice', 700, 'item', 1000.0, '2026-10-20'],
    );
    final recipes = SqliteRecipeRepository(db, householdId: 'h');
    await recipes.saveRecipe(aioliRecipe());

    overrides = [
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 25, 12)),
      weekShapeProvider.overrideWithValue(WeekShape.monday),
      viewedWeekStartProvider.overrideWithBuild((ref, _) => _thisWeek),
      priceRepositoryProvider.overrideWithValue(SqlitePriceRepository(db)),
      ingredientRepositoryProvider.overrideWithValue(
        SqliteIngredientRepository(db, householdId: 'h'),
      ),
      recipeRepositoryProvider.overrideWithValue(recipes),
      weekVariantRepositoryProvider.overrideWithValue(
        SqliteWeekVariantRepository(db, householdId: 'h'),
      ),
      shoppingRepositoryProvider.overrideWithValue(_ListOnly()),
    ];
    container = ProviderContainer(overrides: overrides);
  });

  tearDown(() async {
    container.dispose();
    await closeTestDb(db, dir);
  });

  /// The Shop's sync-line figure, once its watches have landed.
  Future<double?> syncLineCents() async {
    final sub = container.listen(shopTripCostProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(shopPriceMapProvider.future);
    await container.read(vocabularyProvider.future);
    await container.read(currentShoppingListProvider.future);
    return container.read(shopTripCostProvider).cents;
  }

  test(
    "Ask's trip answer is the Shop's sync-line figure, at the cheapest",
    () async {
      // 240 g at 50¢ / 100 g, not at the latest 70¢.
      expect(await syncLineCents(), closeTo(120, 1e-9));
      final answer = _json(await askCost(container, AskTripFigures(_thisWeek)));
      expect(
        answer['still_to_buy'],
        tripEstimate(container.read(shopTripCostProvider)),
      );
      expect(answer['still_to_buy'], r'≈ $1 at the cheapest');
    },
  );

  test("Ask's recipe cost still reads the latest price", () async {
    final answer = _json(
      await askCost(container, const AskRecipeFigures('aioli', servings: 4)),
    );
    // 240 g at 70¢ / 100 g is $1.68 the recipe.
    expect(jsonEncode(answer), contains(r'$1.68'));
  });

  test('the recipe page reads the latest price', () async {
    final costs = await container
        .read(recipeRepositoryProvider)
        .watchRecipeCosts()
        .first;
    expect(costs['aioli']!.totalCents, closeTo(168, 1e-9));
  });

  test("the Week's figure reads the latest price", () async {
    const simon = Member(id: 'm1', displayName: 'Simon');
    // The aioli planned for one eater: one serving of it.
    final plan = WeekPlan(
      id: 'w1',
      weekStart: _thisWeek,
      entries: const [
        PlanEntry(
          id: 'p1',
          dayOfWeek: 2,
          mealSlot: 'Lunch',
          recipeId: 'aioli',
          recipeTitle: 'Romesco Aioli',
          eaterIds: ['m1'],
        ),
      ],
    );
    final scoped = ProviderContainer(
      overrides: [
        ...overrides,
        viewedWeekProvider.overrideWith((ref) => Stream.value(plan)),
        membersByIdProvider.overrideWithValue(const {'m1': simon}),
      ],
    );
    addTearDown(scoped.dispose);
    final sub = scoped.listen(weekCostProvider(null), (_, _) {});
    addTearDown(sub.close);
    await scoped.read(viewedWeekProvider.future);
    await scoped.read(recipeCostsProvider.future);
    await scoped.read(variantRecipeCostsProvider.future);
    await scoped.read(costPriceMapProvider.future);
    // A quarter of $1.68 at the latest 70¢ / 100 g; the Shop's cheapest would
    // make it 30¢.
    expect(scoped.read(weekCostProvider(null)).cents, closeTo(42, 1e-9));
  });
}
