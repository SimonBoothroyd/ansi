import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/cost_price.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_cost.dart';
import 'package:flutter_test/flutter_test.dart';

PriceObservation _price({
  int cents = 440,
  double pack = 1000,
  MacrosBasis basis = MacrosBasis.perG,
}) => PriceObservation(
  lineId: 'rl-1',
  receiptId: 'r-1',
  cents: cents,
  packBasisAmount: pack,
  basis: basis,
  store: "TJ's",
  purchasedAt: DateTime.utc(2026, 9, 3),
);

ShopPricing _pricing({
  MacrosBasis basis = MacrosBasis.perG,
  double? density,
  double? pieceBasisAmount,
  PriceObservation? price,
}) => (
  row: (
    basis: basis,
    densityGPerMl: density,
    pieceBasisAmount: pieceBasisAmount,
  ),
  price: price == null ? null : ShopPrice(price, ShopPriceChoice.cheapestSeen),
);

ShoppingItem _item({
  String name = 'Yellow onion',
  String? ingredientId = 'i1',
  List<Quantity>? totals,
  bool checked = false,
}) => ShoppingItem(
  name: name,
  ingredientId: ingredientId,
  totals: totals ?? [Quantity(550, g)],
  checked: checked,
);

void main() {
  group('one row', () {
    test("costs its total at the Shop's price", () {
      // 44¢ / 100 g × 550 g = $2.42.
      expect(
        shoppingItemCostCents(_item(), _pricing(price: _price())),
        closeTo(242, 1e-9),
      );
    });

    test('a count total converts through the piece weight', () {
      expect(
        shoppingItemCostCents(
          _item(totals: [Quantity(5, pieces)]),
          _pricing(pieceBasisAmount: 110, price: _price()),
        ),
        closeTo(242, 1e-9),
      );
    });

    test('a row with no price has none — never a zero', () {
      expect(shoppingItemCostCents(_item(), _pricing()), isNull);
      expect(shoppingItemCostCents(_item(), null), isNull);
    });

    test('a free-text item has nothing to price', () {
      expect(
        shoppingItemCostCents(
          _item(name: 'Paper towels', ingredientId: null, totals: const []),
          _pricing(price: _price()),
        ),
        isNull,
      );
    });

    test('a subtotal that cannot reach the basis prices nothing at all', () {
      // Mass and volume with no density between them: pricing the half that
      // converts would print a figure smaller than the thing being bought.
      expect(
        shoppingItemCostCents(
          _item(totals: [Quantity(200, g), Quantity(100, ml)]),
          _pricing(price: _price()),
        ),
        isNull,
      );
    });

    test('a price against another basis is refused', () {
      expect(
        shoppingItemCostCents(
          _item(),
          _pricing(price: _price(basis: MacrosBasis.perMl)),
        ),
        isNull,
      );
    });
  });

  group('the trip', () {
    test('sums the rows it can price and COUNTS the rest (owner)', () {
      final trip = tripCostCents([
        _item(),
        _item(name: 'Broccoli', ingredientId: 'i2'),
      ], (id) => id == 'i1' ? _pricing(price: _price()) : _pricing());
      expect(trip.cents, closeTo(242, 1e-9));
      // A row that adds nothing is what makes the figure a floor, so the line
      // that prints it has to be told there was one.
      expect(trip.unpriced, 1);
    });

    test('nothing priceable is no figure, never a free trip', () {
      expect(tripCostCents([_item()], (_) => _pricing()).cents, isNull);
      final empty = tripCostCents(const [], (_) => _pricing());
      expect(empty.cents, isNull);
      expect(empty.unpriced, 0);
    });

    test('a free-text row is neither priced nor a gap — there is nothing to '
        'go and fix', () {
      final trip = tripCostCents([
        _item(),
        _item(name: 'Foil', ingredientId: null),
      ], (_) => _pricing(price: _price()));
      expect(trip.unpriced, 0);
    });
  });

  /// A row that rounds up is bought whole, so it is priced whole: the figure
  /// is for what goes in the basket, which is what the headline says.
  group('a rounded row is priced on what you buy', () {
    // 67 g a lime at 44¢ / 100 g.
    const whole = Measure(id: 'm-lime', label: 'lime, whole', amount: 67);
    const threeLimes = 0.44 * 67 * 3;

    test('a fractional measure count: 3 limes, not 2½', () {
      final lime = _item(
        name: 'Lime',
        totals: [Quantity(167.5, g)],
      ).copyWith(measureTotal: (amount: 2.5, measure: whole));
      expect(
        shoppingItemCostCents(lime, _pricing(price: _price())),
        closeTo(threeLimes, 1e-9),
      );
    });

    test('a fractional piece count', () {
      final lime = _item(
        name: 'Lime',
        totals: [Quantity(167.5, g)],
      ).copyWith(pieceTotal: (count: 2.5, approx: true));
      expect(
        shoppingItemCostCents(
          lime,
          _pricing(pieceBasisAmount: 67, price: _price()),
        ),
        closeTo(threeLimes, 1e-9),
      );
    });

    test('a whole-unit hint on a mass total', () {
      final potato = _item(name: 'Potato', totals: [Quantity(600, g)]).copyWith(
        wholeUnitHint: (
          count: 2.25,
          buy: 3,
          unitLabel: 'potato, large',
          approx: true,
        ),
      );
      // Three potatoes at 600 g / 2.25 each.
      expect(
        shoppingItemCostCents(potato, _pricing(price: _price())),
        closeTo(0.44 * 800, 1e-9),
      );
    });

    test('a whole-unit hint on a count total', () {
      final egg = _item(name: 'Egg', totals: [Quantity(2.5, pieces)]).copyWith(
        wholeUnitHint: (count: 2.5, buy: 3, unitLabel: 'piece', approx: false),
      );
      expect(
        shoppingItemCostCents(
          egg,
          _pricing(pieceBasisAmount: 50, price: _price()),
        ),
        closeTo(0.44 * 150, 1e-9),
      );
    });

    test('a whole count is priced as it stands', () {
      final lime = _item(
        name: 'Lime',
        totals: [Quantity(134, g)],
      ).copyWith(measureTotal: (amount: 2, measure: whole));
      expect(roundedBuy(lime), isNull);
      expect(
        shoppingItemCostCents(lime, _pricing(price: _price())),
        closeTo(0.44 * 134, 1e-9),
      );
    });

    test('a part-have is priced on what is left, rounded the same way', () {
      // The week needs 4½ limes and 2 are at home: 2½ are left, so 3 are
      // bought. The totals and the count are already what is left.
      final lime = _item(name: 'Lime', totals: [Quantity(167.5, g)]).copyWith(
        measureTotal: (amount: 2.5, measure: whole),
        atHome: (
          need: (
            totals: [Quantity(301.5, g)],
            measureTotal: (amount: 4.5, measure: whole),
            pieceTotal: null,
          ),
          quantity: 2,
          unit: null,
          measure: whole,
          measureId: 'm-lime',
          all: false,
          refusal: null,
        ),
      );
      expect(roundedBuy(lime), (need: 2.5, buy: 3));
      expect(
        shoppingItemCostCents(lime, _pricing(price: _price())),
        closeTo(threeLimes, 1e-9),
      );
    });

    test('the trip is the sum of the figures the rows print', () {
      final lime = _item(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(167.5, g)],
      ).copyWith(measureTotal: (amount: 2.5, measure: whole));
      final onion = _item();
      final pricing = _pricing(price: _price());
      final trip = tripCostCents([lime, onion], (_) => pricing);
      expect(
        trip.cents,
        closeTo(
          shoppingItemCostCents(lime, pricing)! +
              shoppingItemCostCents(onion, pricing)!,
          1e-9,
        ),
      );
      expect(trip.cents, closeTo(threeLimes + 242, 1e-9));
    });
  });
}
