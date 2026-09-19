import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeMeasure _m(
  String label,
  double amount, {
  Unit unit = g,
  String id = 'm1',
}) => RecipeMeasure(
  id: id,
  recipeId: 'aioli',
  label: label,
  amount: amount,
  unit: unit,
);

void main() {
  group('a measure is a named amount', () {
    test('a line multiplies by it — `3 blob` of a 15 g blob is 45 g', () {
      final total = _m('blob', 15).totalFor(3);
      expect(total!.amount, closeTo(45, 1e-12));
      expect(total.unit, g);
    });

    test('it keeps its own unit, whichever family that is', () {
      expect(_m('ladle', 180, unit: ml).totalFor(2)!.unit, ml);
      expect(_m('patty', 1, unit: pieces).totalFor(4)!.amount, 4);
      expect(_m('loaf', 0.9, unit: kg).totalFor(1)!.unit, kg);
    });

    test('scaling moves the LINE, never the measure', () {
      // A parent cooked twice asks for `6 blob`; a blob is still 15 g.
      final blob = _m('blob', 15);
      expect(blob.totalFor(6)!.amount, closeTo(90, 1e-12));
      expect(blob.amount, 15);
    });

    test('the word is whatever they typed — nothing is special-cased', () {
      for (final word in ['blob', 'ladle', 'patty', 'schmear', 'глыба']) {
        expect(_m(word, 4).totalFor(2)!.amount, 8, reason: word);
      }
    });
  });

  group('a number that says nothing about a size', () {
    test('zero, negative and NaN convert nothing rather than fabricating', () {
      for (final bad in [0.0, -3.0, double.nan, double.infinity]) {
        final measure = _m('blob', bad);
        expect(measure.saysAnAmount, isFalse, reason: '$bad');
        expect(measure.totalFor(3), isNull, reason: '$bad');
      }
    });

    test('a positive finite number does', () {
      expect(_m('blob', 0.5).saysAnAmount, isTrue);
    });
  });

  group('a unit that cannot measure says nothing either', () {
    test('`batch` is refused — a word defined in batches is circular', () {
      final measure = _m('blob', 0.05, unit: batches);
      expect(measure.saysAnAmount, isFalse);
      expect(measure.totalFor(3), isNull);
    });

    test('an imprecise word is refused — convert will not carry one', () {
      for (final bad in [pinch, dash, handful, toTaste]) {
        expect(_m('blob', 1, unit: bad).saysAnAmount, isFalse, reason: bad.id);
      }
    });

    test('mass, volume and count are the three that do', () {
      expect(kRecipeMeasureFamilies, {
        UnitFamily.mass,
        UnitFamily.volume,
        UnitFamily.count,
      });
      for (final unit in [g, kg, oz, ml, cup, tbsp, pieces]) {
        expect(_m('blob', 2, unit: unit).saysAnAmount, isTrue, reason: unit.id);
      }
    });
  });

  group('recipeMeasureById', () {
    final blob = _m('blob', 15);
    final ladle = _m('ladle', 180, unit: ml, id: 'm2');

    test('finds the row a line points at', () {
      expect(recipeMeasureById('m2', [blob, ladle]), ladle);
    });

    test('an id nothing carries is not found', () {
      expect(recipeMeasureById('gone', [blob, ladle]), isNull);
      expect(recipeMeasureById('m1', const []), isNull);
    });

    test('a row whose amount says nothing is not found either', () {
      // It names a word, but it cannot say what one of it comes to — which is
      // the only thing a caller is here for.
      expect(recipeMeasureById('m1', [_m('blob', 0)]), isNull);
      expect(recipeMeasureById('m1', [_m('blob', 1, unit: batches)]), isNull);
    });
  });

  test('value equality and copyWith', () {
    expect(_m('blob', 15), _m('blob', 15));
    expect(_m('blob', 15), isNot(_m('blob', 18)));
    // The unit is part of the fact: 15 g and 15 ml are not the same blob.
    expect(_m('blob', 15), isNot(_m('blob', 15, unit: ml)));
    expect(_m('blob', 15).copyWith(amount: 18), _m('blob', 18));
    expect(_m('blob', 15).copyWith(unit: ml), _m('blob', 15, unit: ml));
    expect(_m('blob', 15).copyWith().hashCode, _m('blob', 15).hashCode);
    expect(_m('blob', 15).toString(), contains('blob = 15.0 g'));
  });
}
