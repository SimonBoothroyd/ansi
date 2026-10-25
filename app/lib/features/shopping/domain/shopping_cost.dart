/// What the shop costs. Pure Dart.
///
/// A row's estimate is what it buys converted to the ingredient's basis unit
/// through [quantityInBasis], times the price the Shop reads per unit of that
/// basis (`shopPriceOf`, ADR-0017: the cheapest seen in the window, else the
/// price every other cost reads). A row that rounds up to a whole count is
/// priced on the whole count ([roundedBuy]). A row that cannot be priced adds
/// nothing and says `no price yet`; a trip with one reads `at least …` rather
/// than `≈ …`, and a trip nothing can price has no figure. The caller leaves
/// ticked rows out.
library;

import '../../../core/result/result.dart';
import '../../ingredients/domain/cost_price.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/domain/line_basis.dart';
import 'shopping.dart';

/// One vocab row's basis facts and the price the Shop reads for it. A null
/// `price` means nothing prices the row.
typedef ShopPricing = ({IngredientBasis row, ShopPrice? price});

/// [ShopPricing] for every row of [vocabulary], keyed by ingredient id, from
/// the Shop's price map. The Shop and Ask's trip answer both assemble it here,
/// so they price a row the same way.
Map<String, ShopPricing> shopPricingOf(
  Iterable<Ingredient> vocabulary,
  Map<String, ShopPrice> prices,
) => {
  for (final row in vocabulary)
    row.id: (
      row: (
        basis: row.macrosBasis,
        densityGPerMl: row.densityGPerMl,
        pieceBasisAmount: row.pieceBasisAmount,
      ),
      price: prices[row.id],
    ),
};

/// A row that rounds up: the fractional count it needs and the whole count
/// bought.
typedef RoundedBuy = ({double need, int buy});

/// What [item] rounds up to, or null when it buys what it needs.
///
/// A row rounds when its count is fractional: a count of one measure
/// (`2½ lime, whole`), a count of pieces (`≈ 2½ piece`), or the whole-unit
/// hint on a single total ([ShoppingItem.wholeUnitHint]). On a part-have the
/// counts are what is left to buy, so that is what rounds.
RoundedBuy? roundedBuy(ShoppingItem item) {
  final count = item.pieceTotal?.count ?? item.measureTotal?.amount;
  if (count != null) {
    final buy = count.ceil();
    return buy > count ? (need: count, buy: buy) : null;
  }
  final hint = item.wholeUnitHint;
  if (hint == null || !(hint.count > 0)) return null;
  return (need: hint.count, buy: hint.buy);
}

/// What [item] comes to at the price the Shop reads for its row, in cents, or
/// null when it cannot be priced: no price, a total that never reached the
/// basis unit, a price against a different basis, or a free-text item. Every
/// subtotal must convert; pricing half a row would understate it.
///
/// A row that rounds ([roundedBuy]) is priced on the whole count bought, three
/// limes rather than two and a half. Its totals weigh the fractional count
/// through the row's piece or measure weight, so the whole count weighs
/// `buy / need` of that.
double? shoppingItemCostCents(ShoppingItem item, ShopPricing? pricing) {
  final price = pricing?.price?.price;
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
  final rounded = roundedBuy(item);
  if (rounded != null) basisAmount = basisAmount * rounded.buy / rounded.need;
  return per100.cents * basisAmount / 100;
}

/// What a trip comes to, and how many of its rows nothing could price. `cents`
/// is null when no row could be priced. A non-zero `unpriced` makes the figure
/// a floor, which the sync line's words say (`cost_words.dart`).
typedef TripCost = ({double? cents, int unpriced});

/// [TripCost] over the unticked part of [items]: the sum of the figures their
/// rows print ([shoppingItemCostCents]). A free-text row counts neither way.
TripCost tripCostCents(
  Iterable<ShoppingItem> items,
  ShopPricing? Function(String ingredientId) pricingOf,
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
