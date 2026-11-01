import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/spare_offer.dart';
import 'package:flutter_test/flutter_test.dart';

const _grams = (
  basis: MacrosBasis.perG,
  densityGPerMl: null,
  pieceBasisAmount: null,
);

ShoppingItem _row(List<Quantity> totals, {bool checked = false}) =>
    ShoppingItem(
      name: 'Spinach',
      ingredientId: 'spinach',
      checked: checked,
      totals: totals,
    );

void main() {
  test('offers the spare, never more than the row still buys', () {
    expect(
      spareOfferFor(_row([Quantity(500, g)]), spare: 300, row: _grams),
      300,
    );
    expect(
      spareOfferFor(_row([Quantity(200, g)]), spare: 300, row: _grams),
      200,
    );
  });

  test('weighs a count through the row piece weight', () {
    const onion = (
      basis: MacrosBasis.perG,
      densityGPerMl: null,
      pieceBasisAmount: 150.0,
    );
    expect(
      spareOfferFor(_row([Quantity(3.5, pieces)]), spare: 75, row: onion),
      75,
    );
    // No piece weight: the count will not weigh, so nothing is offered.
    expect(
      spareOfferFor(_row([Quantity(3.5, pieces)]), spare: 75, row: _grams),
      isNull,
    );
  });

  test('a ticked row, or one with nothing to buy, is offered nothing', () {
    expect(
      spareOfferFor(
        _row([Quantity(500, g)], checked: true),
        spare: 300,
        row: _grams,
      ),
      isNull,
    );
    expect(
      spareOfferFor(_row([Quantity(0.5, g)]), spare: 300, row: _grams),
      isNull,
    );
  });
}
