/// Which price a cost reads. Pure Dart. See ADR-0017.
///
/// The one rule every cost surface goes through — a recipe, a planned week, a
/// snack, the shop's estimate: the newest price paid on a receipt for the row,
/// else the row's own base price, else nothing (unpriced, exactly as a row
/// nobody has priced). A base price set after a receipt does not outrank it:
/// what was paid is the better fact, and the base price is what stands in
/// until something has been.
///
/// Held by `test/structure/cost_reads_one_price_test.dart`: no cost consumer
/// reads a receipt line, or a base price, for itself.
library;

import 'price.dart';

/// The price a cost of one row reads: [paid] (the row's newest receipt-line
/// price) when there is one, else [base], else null.
UnitPrice? costPriceOf({PriceObservation? paid, BasePrice? base}) =>
    paid ?? base;

/// [costPriceOf] for every row at once, keyed by ingredient id. A row absent
/// from both maps is absent here, which every reader takes as unpriced.
Map<String, UnitPrice> costPrices({
  required Map<String, PriceObservation> latestPaid,
  required Map<String, BasePrice> base,
}) => {
  for (final id in {...base.keys, ...latestPaid.keys})
    if (costPriceOf(paid: latestPaid[id], base: base[id]) case final price?)
      id: price,
};
