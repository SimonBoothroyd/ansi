/// What the shop costs — PURE DART (invariant 2).
///
/// A row's estimate is the recipe panel's arithmetic at a different scope: the
/// row's rolled-up total, converted to the ingredient's basis unit through
/// [quantityInBasis] — the seam the macro and cost summations already share —
/// times the latest price per unit of that basis (ADR-0017).
///
/// **The trip figure sums what it can, and the rows say what it could not.**
/// That is the shopping list's own doctrine, not a softening of invariant 3: a
/// list already sums an ingredient's honest subtotals and shows the provenance
/// of every part, and a row with no price prints `no price yet` in its own
/// words, inches from the total. What would be dishonest is a silent zero, and
/// there is none here — a row that cannot be priced adds nothing and says so,
/// and a trip nothing on it can price has **no** figure rather than `≈ $0`.
///
/// **The basket carries none.** The line answers *what is left to buy*, so a
/// ticked row is out of it; that is the caller's rule, since only the caller
/// knows which reading of the list it is showing.
library;

import '../../../core/result/result.dart';
import '../../recipes/domain/line_basis.dart';
import '../../recipes/domain/recipe_cost.dart';
import 'shopping.dart';

/// What [item] comes to at the latest price, in cents, or null when it cannot
/// be priced — no price for the row, a total that never reached the row's
/// basis unit, a price recorded against a different basis, or a free-text
/// item, which is not a vocabulary row and has nothing to price.
///
/// Every subtotal must convert. A row that could not be merged into one family
/// — a mass and a volume with no density between them — is a row this cannot
/// price either: pricing half of it would print a figure smaller than the
/// thing being bought.
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

/// What the unticked part of [items] comes to — the shop's trip estimate.
///
/// Null when not one row could be priced: a trip with no figure says nothing,
/// where `≈ $0` would read as a free one.
double? tripCostCents(
  Iterable<ShoppingItem> items,
  IngredientPricing? Function(String ingredientId) pricingOf,
) {
  double? total;
  for (final item in items) {
    final id = item.ingredientId;
    if (id == null) continue;
    final cents = shoppingItemCostCents(item, pricingOf(id));
    if (cents == null) continue;
    total = (total ?? 0) + cents;
  }
  return total;
}
