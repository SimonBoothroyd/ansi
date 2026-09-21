/// Riverpod ViewModels for the Shop screen.
///
/// [currentShoppingList] streams the derived list for the viewed week.
/// Mutations are fire-and-forget calls the view makes on the keep-alive
/// [shoppingRepositoryProvider] directly, never through a throwaway notifier
/// held across an async gap, which Riverpod disposes mid-call.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../ingredients/data/ingredient_providers.dart';
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

/// What the rest of the trip comes to, and how many rows it could not price
/// (ADR-0017). Unticked rows only. The figure is null when no row can be
/// priced.
@riverpod
TripCost shopTripCost(Ref ref) {
  final list = ref.watch(currentShoppingListProvider).asData?.value;
  if (list == null) return (cents: null, unpriced: 0);
  final pricing = ref.watch(ingredientPricingProvider);
  return tripCostCents([
    for (final group in list.openGroups) ...group.items,
  ], (id) => pricing[id]);
}
