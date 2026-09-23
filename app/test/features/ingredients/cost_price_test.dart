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
}
