/// Riverpod ViewModels for the Shop screen.
///
/// [currentShoppingList] streams the derived list for the viewed week.
/// Mutations are fire-and-forget calls the view makes on the keep-alive
/// [shoppingRepositoryProvider] directly, never through a throwaway notifier
/// held across an async gap, which Riverpod disposes mid-call.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/cost_price.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';
import '../domain/shopping_cost.dart';

part 'shopping_view_models.g.dart';

/// The derived shopping list for the viewed week, reacting to plan/recipe/
/// overlay changes.
@riverpod
Stream<ShoppingList> currentShoppingList(Ref ref) => ref
    .watch(shoppingRepositoryProvider)
    .watchShoppingList(ref.watch(viewedWeekStartProvider));

/// The price the Shop reads for every row that has one: the cheapest paid in
/// the window ending today, else the price every other cost reads
/// (`shopPriceOf`, ADR-0017). Keep-alive and re-keyed by [todayProvider], so
/// the window moves at midnight and leaving the tab keeps the watch. The
/// Shop's own: no other cost reads it.
@Riverpod(keepAlive: true)
Stream<Map<String, ShopPrice>> shopPriceMap(Ref ref) => ref
    .watch(priceRepositoryProvider)
    .watchShopPrices(today: ref.watch(todayProvider));

/// What each vocabulary row costs at the Shop's price and how its amounts
/// convert. A row the vocabulary has not synced is absent.
@riverpod
Map<String, ShopPricing> shopPricing(Ref ref) => shopPricingOf(
  ref.watch(vocabularyProvider).asData?.value ?? const <Ingredient>[],
  ref.watch(shopPriceMapProvider).asData?.value ?? const {},
);

/// What the rest of the trip comes to at the Shop's prices, and how many rows
/// it could not price (ADR-0017): the sum of the figures the rows print.
/// Unticked rows only. The figure is null when no row can be priced.
@riverpod
TripCost shopTripCost(Ref ref) {
  final list = ref.watch(currentShoppingListProvider).asData?.value;
  if (list == null) return (cents: null, unpriced: 0);
  final pricing = ref.watch(shopPricingProvider);
  return tripCostCents([
    for (final group in list.openGroups) ...group.items,
  ], (id) => pricing[id]);
}

/// [shopTripCost] for [weekStart], read once through [container]: the figure
/// the sync line prints, for a reader with no widget to watch it from (Ask's
/// trip answer). Reads the repositories' streams directly, so no auto-disposed
/// provider is read once and lost, and the window ends on the Shop's own day.
Future<TripCost> readShopTripCost(
  ProviderContainer container,
  DateTime weekStart,
) async {
  final list = await container
      .read(shoppingRepositoryProvider)
      .watchShoppingList(weekStart)
      .first;
  final prices = await container
      .read(priceRepositoryProvider)
      .watchShopPrices(today: container.read(todayProvider))
      .first;
  final vocabulary = await container
      .read(ingredientRepositoryProvider)
      .watchVocabulary()
      .first;
  final pricing = shopPricingOf(vocabulary, prices);
  return tripCostCents([
    for (final group in list.openGroups) ...group.items,
  ], (id) => pricing[id]);
}

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door
/// to an amount. This phone's alone and never synced: **Done** ends it, and so
/// does leaving the Shop tab.
@riverpod
class ShopChecking extends _$ShopChecking {
  @override
  bool build() => false;

  /// Enters the pass.
  void start() => state = true;

  /// Leaves the pass. Every tap in it was written as it was made.
  void done() => state = false;
}
