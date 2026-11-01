import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/spare_offer.dart';
import 'package:flutter_test/flutter_test.dart';

const _grams = (
  basis: MacrosBasis.perG,
  densityGPerMl: null,
  pieceBasisAmount: null,
);

const _onion = (
  basis: MacrosBasis.perG,
  densityGPerMl: null,
  pieceBasisAmount: 150.0,
);

ShoppingItem _row(
  List<Quantity> totals, {
  bool checked = false,
  MeasureAmount? measureTotal,
}) => ShoppingItem(
  name: 'Spinach',
  ingredientId: 'spinach',
  checked: checked,
  totals: totals,
  measureTotal: measureTotal,
);

void main() {
  test('offers the spare, never more than the row still buys', () {
    expect(spareOfferFor(_row([Quantity(500, g)]), spare: 300, row: _grams), (
      quantity: 300.0,
      unit: g,
      measure: null,
    ));
    expect(
      spareOfferFor(
        _row([Quantity(200, g)]),
        spare: 300,
        row: _grams,
      )?.quantity,
      200,
    );
  });

  test('a counted row is offered a count, in its own words', () {
    // 3½ pieces of a 150 g onion; 75 g spare is half of one.
    expect(
      spareOfferFor(_row([Quantity(3.5, pieces)]), spare: 75, row: _onion),
      (quantity: 0.5, unit: pieces, measure: null),
    );
    // Counted in a measure, the offer is a count of the same measure.
    const medium = Measure(id: 'm-medium', label: 'onion, medium', amount: 150);
    final offer = spareOfferFor(
      _row([Quantity(525, g)], measureTotal: (amount: 3.5, measure: medium)),
      spare: 75,
      row: _onion,
    );
    expect(offer?.quantity, 0.5);
    expect(offer?.measure, medium);
  });

  test('a count comes down to the quarter below, never up past the spare', () {
    // 100 g of a 150 g onion is two thirds: offered a half.
    expect(
      spareOfferFor(
        _row([Quantity(3, pieces)]),
        spare: 100,
        row: _onion,
      )?.quantity,
      0.5,
    );
    // Under a quarter of one is nothing to offer.
    expect(
      spareOfferFor(_row([Quantity(3, pieces)]), spare: 30, row: _onion),
      isNull,
    );
  });

  test('a count that will not weigh is offered nothing', () {
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
