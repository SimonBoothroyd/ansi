import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/default_amount.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

/// A protein bar: counted in pieces, one weighs 60 g, and its word for one
/// is `bar`.
const _bar = Ingredient(
  id: 'i-bar',
  canonicalName: 'Protein bar',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
  pieceBasisAmount: 60,
  allowedUnits: [g, pieces],
);

const _barWord = Measure(id: 'm-bar', label: 'bar', amount: 60);
const _twoBars = Measure(id: 'm-two', label: 'twin pack', amount: 120);

/// Skyr from a tub: weighed in grams, with no piece and no word for one.
const _skyr = Ingredient(
  id: 'i-skyr',
  canonicalName: 'Skyr',
  defaultUnit: g,
  status: IngredientStatus.complete,
  allowedUnits: [g],
);

void main() {
  test('nothing said before: one of its word for one', () {
    final d = defaultAmountFor(_bar, const [_twoBars, _barWord])!;
    expect(d.quantity, 1);
    expect(d.choice, const MeasureOption(_barWord));
    expect(d.source, DefaultAmountSource.wholeMeasure);
  });

  test('a weighed piece with no word for it: one piece', () {
    final d = defaultAmountFor(_bar, const [])!;
    expect(d.choice, const UnitOption(pieces));
    expect(d.source, DefaultAmountSource.piece);
  });

  test('last time wins, in its own measure or unit', () {
    final measured = defaultAmountFor(
      _bar,
      const [_barWord, _twoBars],
      last: (quantity: 1, unit: pieces, measureId: 'm-two'),
    )!;
    expect(measured.choice, const MeasureOption(_twoBars));
    expect(measured.source, DefaultAmountSource.lastTime);

    final weighed = defaultAmountFor(
      _skyr,
      const [],
      last: (quantity: 170, unit: g, measureId: null),
    )!;
    expect(weighed.quantity, 170);
    expect(weighed.choice, const UnitOption(g));
  });

  test('a remembered measure or unit the row no longer offers is passed '
      'over', () {
    final gone = defaultAmountFor(
      _bar,
      const [_barWord],
      last: (quantity: 1, unit: pieces, measureId: 'deleted'),
    )!;
    expect(gone.source, DefaultAmountSource.wholeMeasure);
    expect(
      defaultAmountFor(
        _skyr,
        const [],
        last: (quantity: 1, unit: cup, measureId: null),
      ),
      isNull,
    );
  });

  test('a tub with no history has no default: the sheet opens empty', () {
    expect(defaultAmountFor(_skyr, const []), isNull);
  });
}
