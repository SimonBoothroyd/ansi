import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/domain/cost_price.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:flutter_test/flutter_test.dart';

PriceObservation _paid(String lineId, {DateTime? on}) => PriceObservation(
  lineId: lineId,
  receiptId: 'r-$lineId',
  cents: 349,
  packBasisAmount: 454,
  basis: MacrosBasis.perG,
  store: "TJ's",
  purchasedAt: on ?? DateTime.utc(2026, 8, 2),
);

BasePrice _base(String id, {DateTime? on}) => BasePrice(
  ingredientId: id,
  cents: 199,
  packBasisAmount: 60,
  basis: MacrosBasis.perG,
  setAt: on ?? DateTime.utc(2026, 9, 20),
);

void main() {
  group('costPriceOf — the one rule a cost reads by', () {
    test('a price paid wins, even over a base price set after it', () {
      final paid = _paid('l1');
      expect(costPriceOf(paid: paid, base: _base('i1')), same(paid));
    });

    test('with nothing paid, the base price stands in', () {
      final base = _base('i1');
      expect(costPriceOf(base: base), same(base));
    });

    test('with neither, the row is unpriced', () {
      expect(costPriceOf(), isNull);
    });
  });

  group('costPrices — every row at once', () {
    test('each row takes its own answer, and a row with none is absent', () {
      final prices = costPrices(
        latestPaid: {'butter': _paid('l1'), 'rice': _paid('l2')},
        base: {'butter': _base('butter'), 'parsley': _base('parsley')},
      );
      expect(prices.keys, unorderedEquals(['butter', 'rice', 'parsley']));
      expect(prices['butter'], isA<PriceObservation>());
      expect(prices['rice'], isA<PriceObservation>());
      expect(prices['parsley'], isA<BasePrice>());
      expect(prices.containsKey('cumin'), isFalse);
    });
  });

  /// The Shop's own rule: the cheapest paid in the last 90 days, else exactly
  /// what every other cost reads.
  group('shopPriceOf — the cheapest seen, for the Shop', () {
    final today = DateTime(2026, 10, 25);
    DateTime daysAgo(int n) =>
        DateTime.utc(2026, 10, 25, 17, 20).subtract(Duration(days: n));

    PriceObservation line(
      String id, {
      required DateTime on,
      int cents = 349,
      double pack = 454,
      int count = 1,
      int discount = 0,
      MacrosBasis basis = MacrosBasis.perG,
      String store = "TJ's",
    }) => PriceObservation(
      lineId: id,
      receiptId: 'r-$id',
      cents: cents,
      discountCents: discount,
      packBasisAmount: pack,
      count: count,
      basis: basis,
      store: store,
      purchasedAt: on,
    );

    ShopPrice? read(List<PriceObservation> paid, {BasePrice? base}) =>
        shopPriceOf(
          paid: paid,
          basis: MacrosBasis.perG,
          today: today,
          base: base,
        );

    test('day 90 is in the window and day 91 is out', () {
      final in90 = read([line('l90', on: daysAgo(90))]);
      expect(in90!.choice, ShopPriceChoice.cheapestSeen);
      expect(in90.price.key, 'l90');
      final out91 = read([line('l91', on: daysAgo(91))]);
      expect(out91!.choice, ShopPriceChoice.costPrice);
      expect(out91.price.key, 'l91');
      // Today is day 0, and a receipt another clock dated tomorrow is today's.
      expect(
        read([line('l0', on: daysAgo(0))])!.choice,
        ShopPriceChoice.cheapestSeen,
      );
      expect(
        read([line('lt', on: daysAgo(-1))])!.choice,
        ShopPriceChoice.cheapestSeen,
      );
    });

    test('the cheapest per 100 wins, not the cheapest pack', () {
      // $4.00 for 1 kg is 40¢ / 100 g; $2.50 for 500 g is 50¢ / 100 g.
      final price = read([
        line('small', on: daysAgo(2), cents: 250, pack: 500),
        line('big', on: daysAgo(30), cents: 400, pack: 1000, store: 'Aldi'),
      ]);
      expect(price!.price.key, 'big');
    });

    test('a count line divides by what it rang up', () {
      // 3 × 500 g for $5.40 is 36¢ / 100 g, under the 40¢ bag.
      final price = read([
        line('bag', on: daysAgo(2), cents: 400, pack: 1000),
        line('three', on: daysAgo(40), cents: 540, pack: 500, count: 3),
      ]);
      expect(price!.price.key, 'three');
    });

    test('a discount counts: what was paid can be the cheapest', () {
      // $5.00 less $2.00 for 1 kg is 30¢ / 100 g.
      final price = read([
        line('full', on: daysAgo(2), cents: 400, pack: 1000),
        line('sale', on: daysAgo(10), cents: 500, pack: 1000, discount: 200),
      ]);
      expect(price!.price.key, 'sale');
    });

    test('a price in another basis is skipped', () {
      final price = read([
        line(
          'ml',
          on: daysAgo(2),
          cents: 1,
          pack: 1000,
          basis: MacrosBasis.perMl,
        ),
        line('g', on: daysAgo(5), cents: 400, pack: 1000),
      ]);
      expect(price!.price.key, 'g');
    });

    test('a tie goes to the newest', () {
      final price = read([
        line('newer', on: daysAgo(3), cents: 400, pack: 1000),
        line('older', on: daysAgo(20), cents: 200, pack: 500),
      ]);
      expect(price!.price.key, 'newer');
      // On the same day the list's own order holds: newest line first.
      final sameDay = read([
        line('first', on: daysAgo(3), cents: 400, pack: 1000),
        line('second', on: daysAgo(3), cents: 400, pack: 1000),
      ]);
      expect(sameDay!.price.key, 'first');
    });

    test('nothing in the window: the newest receipt, over a base price', () {
      final price = read([
        line('jun', on: daysAgo(130)),
        line('may', on: daysAgo(160)),
      ], base: _base('i1'));
      expect(price!.choice, ShopPriceChoice.costPrice);
      expect(price.price.key, 'jun');
    });

    test('nothing paid at all: the base price', () {
      final base = _base('i1');
      final price = read(const [], base: base);
      expect(price!.choice, ShopPriceChoice.costPrice);
      expect(price.price, same(base));
    });

    test('neither: unpriced', () {
      expect(read(const []), isNull);
    });

    test('past the window it reads exactly what every other cost reads', () {
      final paid = [line('jun', on: daysAgo(130))];
      final base = _base('i1');
      expect(
        read(paid, base: base)!.price,
        same(costPriceOf(paid: paid.first, base: base)),
      );
    });
  });
}
