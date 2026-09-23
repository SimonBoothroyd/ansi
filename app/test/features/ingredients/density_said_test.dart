/// A density as it was said: the sentence, the number derived from it, and the
/// rule that a sentence no longer stating the stored number is not shown.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/density_said.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

const _thirdCup = DensitySaid(
  amount: 1 / 3,
  unit: cup,
  weighs: 40,
  weighsUnit: g,
);

Ingredient _row({double? density, DensitySaid? said}) => Ingredient(
  id: 'x',
  canonicalName: 'Granola',
  defaultUnit: g,
  status: IngredientStatus.stub,
  densityGPerMl: density,
  densitySaid: said,
);

void main() {
  test('the number is derived from the sentence, either way round', () {
    expect(_thirdCup.gPerMl, closeTo(40 / (236.5882365 / 3), 1e-12));
    const weightFirst = DensitySaid(
      amount: 1,
      unit: oz,
      weighs: 30,
      weighsUnit: ml,
    );
    expect(weightFirst.gPerMl, closeTo(28.349523125 / 30, 1e-12));
    expect(weightFirst.sentence, '1 oz weighs 30 ml');
  });

  test('it reads back as said', () {
    expect(_thirdCup.sentence, '⅓ cup weighs 40 g');
  });

  test('the four columns come back only whole and meaningful', () {
    expect(
      DensitySaid.fromColumns(
        amount: 1 / 3,
        unit: 'cup',
        weighs: 40,
        weighsUnit: 'g',
      ),
      _thirdCup,
    );
    expect(
      DensitySaid.fromColumns(
        amount: null,
        unit: 'cup',
        weighs: 40,
        weighsUnit: 'g',
      ),
      isNull,
    );
    // An id this build does not know, and two weights, say nothing.
    expect(
      DensitySaid.fromColumns(
        amount: 1,
        unit: 'gill',
        weighs: 40,
        weighsUnit: 'g',
      ),
      isNull,
    );
    expect(
      DensitySaid.fromColumns(
        amount: 1,
        unit: 'kg',
        weighs: 40,
        weighsUnit: 'g',
      ),
      isNull,
    );
  });

  test('a row shows its sentence only while it states the stored number', () {
    final gPerMl = _thirdCup.gPerMl;
    expect(densitySaidOf(_row(density: gPerMl, said: _thirdCup)), _thirdCup);
    // The number moved without the sentence (an older build's write).
    expect(densitySaidOf(_row(density: 0.9, said: _thirdCup)), isNull);
    expect(densitySaidOf(_row(said: _thirdCup)), isNull);
    expect(densitySaidOf(_row(density: 0.66)), isNull);
  });
}
