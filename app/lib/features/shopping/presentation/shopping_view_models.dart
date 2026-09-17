/// Riverpod ViewModels for the Shop screen.
///
/// [currentShoppingList] streams the derived shopping list for the **viewed**
/// week — the same week start the Week and Cook screens show (D3). Mutations
/// (check-off, top-up, add item) are fire-and-forget calls the view makes on
/// the keep-alive [shoppingRepositoryProvider] directly — never a throwaway
/// notifier held across an async gap, which Riverpod disposes underneath the
/// call.
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

/// What the rest of the trip comes to — the figure on the sync line
/// (ADR-0017).
///
/// The UNTICKED rows only: what is in the basket has been picked up, and the
/// question the line answers is what is left. Null when not one row can be
/// priced, because `≈ $0` would read as a free trip rather than an unpriced
/// one.
@riverpod
double? shopTripCost(Ref ref) {
  final list = ref.watch(currentShoppingListProvider).asData?.value;
  if (list == null) return null;
  final pricing = ref.watch(ingredientPricingProvider);
  return tripCostCents([
    for (final group in list.openGroups) ...group.items,
  ], (id) => pricing[id]);
}
