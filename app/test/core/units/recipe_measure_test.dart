import 'package:ansi/core/units/recipe_measure.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeMeasure _m(String label, double perBatch, {String id = 'm1'}) =>
    RecipeMeasure(id: id, recipeId: 'aioli', label: label, perBatch: perBatch);

void main() {
  group('a measure is a count per batch', () {
    test('a line divides by it — `3 blob` of a batch that makes 20', () {
      expect(_m('blob', 20).batchesFor(3), closeTo(0.15, 1e-12));
      expect(_m('ladle', 6).batchesFor(3), closeTo(0.5, 1e-12));
    });

    test('scaling moves the LINE, never the measure', () {
      // A parent cooked twice asks for `6 blob`; the batch still makes 20.
      final blob = _m('blob', 20);
      expect(blob.batchesFor(6), closeTo(0.3, 1e-12));
      expect(blob.perBatch, 20);
    });

    test('a batch that makes one of something is one batch', () {
      expect(_m('loaf', 1).batchesFor(1), 1.0);
    });

    test('the word is whatever they typed — nothing is special-cased', () {
      for (final word in ['blob', 'ladle', 'patty', 'schmear', 'глыба']) {
        expect(_m(word, 4).batchesFor(2), 0.5, reason: word);
      }
    });
  });

  group('a number that says nothing about a share', () {
    test('zero, negative and NaN convert nothing rather than fabricating', () {
      for (final bad in [0.0, -3.0, double.nan, double.infinity]) {
        final measure = _m('blob', bad);
        expect(measure.saysAShare, isFalse, reason: '$bad');
        expect(measure.batchesFor(3), isNull, reason: '$bad');
      }
    });

    test('a positive finite number does', () {
      expect(_m('blob', 0.5).saysAShare, isTrue);
    });
  });

  group('recipeMeasureById', () {
    final blob = _m('blob', 20);
    final ladle = _m('ladle', 6, id: 'm2');

    test('finds the row a line points at', () {
      expect(recipeMeasureById('m2', [blob, ladle]), ladle);
    });

    test('an id nothing carries is not found', () {
      expect(recipeMeasureById('gone', [blob, ladle]), isNull);
      expect(recipeMeasureById('m1', const []), isNull);
    });

    test('a row whose number says nothing is not found either', () {
      // It names a word, but it cannot turn a number into a share — which is
      // the only thing a caller is here for.
      expect(recipeMeasureById('m1', [_m('blob', 0)]), isNull);
    });
  });

  test('value equality and copyWith', () {
    expect(_m('blob', 20), _m('blob', 20));
    expect(_m('blob', 20), isNot(_m('blob', 24)));
    expect(_m('blob', 20).copyWith(perBatch: 24), _m('blob', 24));
    expect(_m('blob', 20).copyWith().hashCode, _m('blob', 20).hashCode);
    expect(_m('blob', 20).toString(), contains('a batch makes 20.0 blob'));
  });
}
