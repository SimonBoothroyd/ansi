/// What the shop costs — PURE DART (invariant 2).
///
/// A row's estimate is the recipe panel's arithmetic at a different scope: the
/// row's rolled-up total, converted to the ingredient's basis unit through
/// [quantityInBasis] — the seam the macro and cost summations already share —
/// times the latest price per unit of that basis (ADR-0017).
///
/// **The trip figure sums what it can, and says so when it left something
/// out.** A list already sums an ingredient's honest subtotals and shows the
/// provenance of every part, and a row with no price prints `no price yet` in
/// its own words, inches from the total. What would be dishonest is a silent
/// zero, and there is none here — a row that cannot be priced adds nothing and
/// says so, and a trip nothing on it can price has **no** figure rather than
/// `≈ $0`. The figure itself carries the caveat too: a trip with an unpriced
/// row reads `at least …` rather than `≈ …`, because a sum that skipped a row
/// is a floor and naming the gap nearby is not the same as saying so
/// (ADR-0017 rule 4, owner).
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

/// What a trip comes to, and how many of its rows nothing could price.
///
/// `cents` is null when not one row could be priced: a trip with no figure
/// says nothing, where `≈ $0` would read as a free one.
///
/// `unpriced` is what keeps the figure honest. A row nothing can price adds
/// nothing to the sum, so a trip carrying one is a **floor** rather than an
/// estimate, and the words the sync line prints say which of the two it is
/// (`cost_words.dart`) — the week band's rule, on the shop's own version of
/// the same gap.
typedef TripCost = ({double? cents, int unpriced});

/// [TripCost] over the unticked part of [items].
///
/// A free-text row counts neither way: it names no vocabulary row, so there
/// is nothing to price and nothing anybody could go and fix.
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
