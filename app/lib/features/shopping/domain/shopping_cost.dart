/// What the shop costs. Pure Dart.
///
/// A row's estimate is its rolled-up total converted to the ingredient's basis
/// unit through [quantityInBasis], times the latest price per unit of that
/// basis (ADR-0017). A row that cannot be priced adds nothing and says `no
/// price yet`; a trip with one reads `at least …` rather than `≈ …`, and a trip
/// nothing can price has no figure. The caller leaves ticked rows out.
library;

import '../../../core/result/result.dart';
import '../../recipes/domain/line_basis.dart';
import '../../recipes/domain/recipe_cost.dart';
import 'shopping.dart';

/// What [item] comes to at the latest price, in cents, or null when it cannot
/// be priced: no price, a total that never reached the basis unit, a price
/// against a different basis, or a free-text item. Every subtotal must convert;
/// pricing half a row would understate it.
double? shoppingItemCostCents(ShoppingItem item, IngredientPricing? pricing) {
  final price = pricing?.price;
  if (pricing == null || price == null) return null;
  if (price.basis != pricing.row.basis) return null;
  if (item.totals.isEmpty) return null;
  final per100 = switch (price.per100) {
    Ok(:final value) => value,
    Err() => null,
  };
  if (per100 == null) return null;

  var basisAmount = 0.0;
  for (final total in item.totals) {
    final amount = quantityInBasis(total.amount, total.unit, pricing.row);
    if (amount == null) return null;
    basisAmount += amount;
  }
  return per100.cents * basisAmount / 100;
}

/// What a trip comes to, and how many of its rows nothing could price. `cents`
/// is null when no row could be priced. A non-zero `unpriced` makes the figure
/// a floor, which the sync line's words say (`cost_words.dart`).
typedef TripCost = ({double? cents, int unpriced});

/// [TripCost] over the unticked part of [items]. A free-text row counts neither
/// way.
TripCost tripCostCents(
  Iterable<ShoppingItem> items,
  IngredientPricing? Function(String ingredientId) pricingOf,
) {
  double? total;
  var unpriced = 0;
  for (final item in items) {
    final id = item.ingredientId;
    if (id == null) continue;
    final cents = shoppingItemCostCents(item, pricingOf(id));
    if (cents == null) {
      unpriced++;
      continue;
    }
    total = (total ?? 0) + cents;
  }
  return (cents: total, unpriced: unpriced);
}
