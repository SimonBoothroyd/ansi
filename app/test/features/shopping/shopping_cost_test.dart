import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_cost.dart';
import 'package:ansi/features/shopping/presentation/shopping_format.dart';
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

IngredientPricing _pricing({
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
  price: price,
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
    test('costs its total at the latest price', () {
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
    test('sums the rows it can price and ignores the rest', () {
      final cents = tripCostCents([
        _item(),
        _item(name: 'Broccoli', ingredientId: 'i2'),
      ], (id) => id == 'i1' ? _pricing(price: _price()) : _pricing());
      expect(cents, closeTo(242, 1e-9));
    });

    test('nothing priceable is no figure, never a free trip', () {
      expect(tripCostCents([_item()], (_) => _pricing()), isNull);
      expect(tripCostCents(const [], (_) => _pricing()), isNull);
    });
  });

  group('the row line', () {
    test('the estimate rides under the grams', () {
      expect(
        itemSecondaryWithCost(
          ShoppingItem(
            name: 'Yellow onion',
            ingredientId: 'i1',
            totals: [Quantity(550, g)],
            pieceTotal: const (count: 5, approx: true),
          ),
          cents: 242,
        ),
        '550 g · ≈ \$2.42',
      );
    });

    test('a row with no price says so rather than leaving a gap', () {
      expect(
        itemSecondaryWithCost(
          ShoppingItem(
            name: 'Charred broccoli',
            ingredientId: 'i2',
            totals: [Quantity(350, g)],
            pieceTotal: const (count: 1, approx: true),
          ),
          cents: null,
          anyPriced: true,
        ),
        '350 g · no price yet',
      );
    });

    test('a free-text item says nothing about money', () {
      expect(
        itemSecondaryWithCost(
          const ShoppingItem(name: 'Paper towels'),
          anyPriced: true,
        ),
        '',
      );
    });

    test('a household that has priced nothing is not nagged', () {
      expect(
        itemSecondaryWithCost(
          ShoppingItem(
            name: 'Charred broccoli',
            ingredientId: 'i2',
            totals: [Quantity(350, g)],
            pieceTotal: const (count: 1, approx: true),
          ),
        ),
        '350 g',
      );
    });
  });
}
