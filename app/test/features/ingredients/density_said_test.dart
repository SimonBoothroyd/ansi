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

  group('densitySentenceOf — as said, else worked out', () {
    test('a stored sentence that still states the number is shown as said', () {
      final shown = densitySentenceOf(
        _row(density: _thirdCup.gPerMl, said: _thirdCup),
      );
      expect(shown?.sentence, _thirdCup);
      expect(shown?.derived, isFalse);
    });

    test('a number with no sentence is worded in the cup, weight rounded', () {
      final shown = densitySentenceOf(_row(density: 0.66))!;
      expect(shown.derived, isTrue);
      expect(shown.sentence.sentence, '1 cup weighs 156 g');
    });

    test('a stale sentence (an older build moved the number) is replaced by '
        'the worked-out one', () {
      final shown = densitySentenceOf(_row(density: 0.9, said: _thirdCup))!;
      expect(shown.derived, isTrue);
      expect(shown.sentence.sentence, '1 cup weighs 213 g');
    });

    test('a volume default unit is the word it is worked out in', () {
      final oil = _row(density: 0.92).copyWith(defaultUnit: tbsp);
      expect(densitySentenceOf(oil)!.sentence.sentence, '1 tbsp weighs 13.6 g');
    });

    test('no density, no sentence', () {
      expect(densitySentenceOf(_row()), isNull);
    });
  });

  test('kitchenGrams reads as a scale does', () {
    expect(kitchenGrams(156.1482), 156);
    expect(kitchenGrams(13.617), 13.6);
    expect(kitchenGrams(6.5078), 6.51);
    expect(kitchenGrams(0.9243), 0.92);
    expect(kitchenGrams(1234.56), 1235);
  });
}
