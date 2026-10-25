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

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door to an
/// amount. The `To buy · At home?` toggle reads and writes it. This phone's
/// alone and never synced: tapping back to `To buy` ends it, and so do
/// leaving the Shop tab and the wide pane's ×.
@riverpod
class ShopChecking extends _$ShopChecking {
  @override
  bool build() => false;

  /// Enters the pass.
  void start() => state = true;

  /// Leaves the pass. Every tap in it was written as it was made.
  void done() => state = false;
}

/// The three sections at the foot of the walk that fold to one counted line.
enum ShopFold { basket, atHome, notes }

/// What is open on this phone's Shop: a row's breakdown (keyed by
/// `shoppingItemIdentity`) or a [ShopFold]. Everything starts closed. This
/// phone's alone, never synced, and it lasts the visit: leaving the Shop tab
/// closes it all.
@riverpod
class ShopOpen extends _$ShopOpen {
  @override
  Set<Object> build() => const {};

  /// Opens [key] if it is closed, and closes it if it is open.
  void toggle(Object key) => state = state.contains(key)
      ? {...state}.difference({key})
      : {...state, key};

  /// Closes [key], as a tick folds the row it ticks.
  void close(Object key) {
    if (state.contains(key)) state = {...state}.difference({key});
  }

  /// Closes everything.
  void reset() {
    if (state.isNotEmpty) state = const {};
  }
}
