/// Which price a cost reads. Pure Dart. See ADR-0017.
///
/// Two rules, each chosen in one place:
///
/// - **Every cost but the Shop's** — a recipe, a planned week, a snack, Ask's
///   figures — reads [costPriceOf]: the newest price paid on a receipt for the
///   row, else the row's own base price, else nothing (unpriced, exactly as a
///   row nobody has priced). A base price set after a receipt does not outrank
///   it: what was paid is the better fact, and the base price is what stands
///   in until something has been.
/// - **The Shop** (its rows, its trip, and Ask's answer about the trip) reads
///   [shopPriceOf]: the cheapest price paid in the last [shopPriceWindowDays]
///   days, because the cheapest seen is what may send a person to another
///   store. With nothing paid in that window it reads [costPriceOf]'s answer.
///
/// Held by `test/structure/cost_reads_one_price_test.dart`: no cost consumer
/// reads a receipt line, or a base price, for itself, and the Shop's map
/// reaches no other cost.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
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

/// How many days back, today included as day 0, a receipt still counts as
/// seen for the Shop's cheapest price: day 90 is in, day 91 is out.
const shopPriceWindowDays = 90;

/// How [shopPriceOf] came to a row's price, which is what its words say.
enum ShopPriceChoice {
  /// The cheapest per-100 figure paid on a receipt dated in the window. Always
  /// a [PriceObservation]; it names its store and no month, because the
  /// window is the date.
  cheapestSeen,

  /// Nothing paid in the window: the price every other cost reads
  /// ([costPriceOf]), the newest receipt or the base price, named with its
  /// month because it is not the window's.
  costPrice,
}

/// The price the Shop reads for one row, and how it was chosen.
@immutable
class ShopPrice {
  const ShopPrice(this.price, this.choice);

  final UnitPrice price;
  final ShopPriceChoice choice;

  @override
  bool operator ==(Object other) =>
      other is ShopPrice &&
      other.price.key == price.key &&
      other.choice == choice;

  @override
  int get hashCode => Object.hash(price.key, choice);

  @override
  String toString() => 'ShopPrice(${price.key}, ${choice.name})';
}

/// Whether [purchasedAt] falls within [shopPriceWindowDays] days up to and
/// including [today], compared as calendar days.
///
/// A receipt's date is its wall day ([receiptStamp]) and [today] is the app's
/// local day, so both are read by their date parts. A receipt dated after
/// today is another device's clock, not a future shop, and counts as today's.
bool inShopPriceWindow(DateTime purchasedAt, {required DateTime today}) {
  final day = DateTime.utc(
    purchasedAt.year,
    purchasedAt.month,
    purchasedAt.day,
  );
  final now = DateTime.utc(today.year, today.month, today.day);
  return now.difference(day).inDays <= shopPriceWindowDays;
}

/// The price the Shop reads for one row, or null when the row is unpriced.
///
/// [paid] is every receipt price for the row, **newest first**, as the price
/// repository reads them. [basis] is the row's current basis. In order:
///
/// 1. **Cheapest seen.** Among [paid] dated in the window
///    ([inShopPriceWindow]) and in [basis] whose per-100 figure reads, the
///    lowest per-100 figure. Compared per 100 of the basis, never by the
///    pack's cents, so a 1 kg bag and a 500 g bag compare honestly. What was
///    paid is after the printed discount, so a sale counts. A tie goes to the
///    newest.
/// 2. **Nothing in the window:** exactly [costPriceOf] over the newest of
///    [paid] and [base].
/// 3. **Neither:** null.
ShopPrice? shopPriceOf({
  required List<PriceObservation> paid,
  required MacrosBasis basis,
  required DateTime today,
  BasePrice? base,
}) {
  PriceObservation? cheapest;
  double? cheapestCents;
  for (final price in paid) {
    if (price.basis != basis) continue;
    if (!inShopPriceWindow(price.purchasedAt, today: today)) continue;
    final cents = switch (price.per100) {
      Ok(:final value) => value.cents,
      Err() => null,
    };
    if (cents == null) continue;
    final lower = cheapestCents == null || cents < cheapestCents;
    // Equal figures: the later receipt wins; on the same date, the earlier in
    // [paid], which is the newer line.
    final newerTie =
        cents == cheapestCents &&
        price.purchasedAt.isAfter(cheapest!.purchasedAt);
    if (lower || newerTie) {
      cheapest = price;
      cheapestCents = cents;
    }
  }
  if (cheapest != null) {
    return ShopPrice(cheapest, ShopPriceChoice.cheapestSeen);
  }
  final fallback = costPriceOf(paid: paid.firstOrNull, base: base);
  return fallback == null
      ? null
      : ShopPrice(fallback, ShopPriceChoice.costPrice);
}
