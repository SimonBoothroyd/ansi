/// The serving kept as one named measure: the label it is written under, and
/// the amount and unit read back out of it.
///
/// The round trip is what lets the reading posture print the pack's own line —
/// `190 kcal per 2 tbsp` — so it has to survive every phrase this app writes
/// and refuse everything it did not.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/serving_measure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the label', () {
    test('is the reserved prefix and the serving as the pack says it', () {
      expect(servingMeasureLabel(2, tbsp), 'serving · 2 tbsp');
      expect(servingMeasureLabel(0.25, cup), 'serving · ¼ cup');
      expect(servingMeasureLabel(28, g), 'serving · 28 g');
    });

    test('a metric serving reads off a scale, a kitchen one off a cook', () {
      expect(servingMeasureLabel(212.5, g), 'serving · 212.5 g');
      expect(servingMeasureLabel(1.5, ml), 'serving · 1.5 ml');
      expect(servingMeasureLabel(0.5, cup), 'serving · ½ cup');
      expect(servingMeasureLabel(0.25, flOz), 'serving · ¼ fl oz');
    });

    test('round-trips through the parse, whatever the app wrote', () {
      for (final (amount, unit) in [
        (2.0, tbsp),
        (0.25, cup),
        (28.0, g),
        (212.5, g),
        (1.0, flOz),
        (0.25, flOz),
        (1.5, flOz),
        (236.59, ml),
      ]) {
        final read = servingFromMeasureLabel(servingMeasureLabel(amount, unit));
        expect(read, (amount: amount, unit: unit));
      }
    });

    test('refuses a label this file did not write', () {
      // A household can rename or bin the serving like any other measure; a
      // label that stops parsing stops being read as one, rather than
      // becoming a second source of truth.
      expect(servingFromMeasureLabel('medium'), isNull);
      expect(servingFromMeasureLabel('serving · a spoonful'), isNull);
      expect(servingFromMeasureLabel('serving · 2 slices'), isNull);
      expect(servingFromMeasureLabel('2 tbsp'), isNull);
    });
  });

  group('the phrase', () {
    test('reads a decimal, a fraction and a capitalised unit', () {
      expect(parseServingPhrase('0.25 cup'), (amount: 0.25, unit: cup));
      expect(parseServingPhrase('1/4 cup'), (amount: 0.25, unit: cup));
      expect(parseServingPhrase('1 1/2 fl oz'), (amount: 1.5, unit: flOz));
      expect(parseServingPhrase('2/3 cup'), (amount: 2 / 3, unit: cup));
      expect(parseServingPhrase(' 1 Cup '), (amount: 1.0, unit: cup));
      expect(parseServingPhrase('2 Tbsp'), (amount: 2.0, unit: tbsp));
      expect(parseServingPhrase('237 mL'), (amount: 237.0, unit: ml));
    });

    test('refuses a word that is not a kitchen unit, and a zero amount', () {
      // Never approximated into a unit — the unit table's own rule.
      expect(parseServingPhrase('1 serving'), isNull);
      expect(parseServingPhrase('2 pieces'), isNull);
      expect(parseServingPhrase('0 tbsp'), isNull);
      expect(parseServingPhrase('tbsp'), isNull);
      expect(parseServingPhrase('1/0 cup'), isNull);
    });
  });

  group('both readings of a printed serving line', () {
    test('a US label states a spoon and its weight — and both come back', () {
      expect(readPrintedServing('2 tbsp (7 g)'), (
        said: (amount: 2.0, unit: tbsp),
        bracketed: (amount: 7.0, unit: g),
      ));
      expect(readPrintedServing('0.25 cup (28 g)'), (
        said: (amount: 0.25, unit: cup),
        bracketed: (amount: 28.0, unit: g),
      ));
      expect(readPrintedServing('1 Cup (237 mL)'), (
        said: (amount: 1.0, unit: cup),
        bracketed: (amount: 237.0, unit: ml),
      ));
      // A fraction is as ordinary in the bracket as it is outside it.
      expect(readPrintedServing('1/4 cup (1/2 oz)'), (
        said: (amount: 0.25, unit: cup),
        bracketed: (amount: 0.5, unit: oz),
      ));
    });

    test('each half stands alone — a line with only one reading this app '
        'knows returns only that one', () {
      // "1 serving" is no unit, so the bracket is the whole reading.
      expect(readPrintedServing('1 serving (16 fl oz)'), (
        said: null,
        bracketed: (amount: 16.0, unit: flOz),
      ));
      expect(readPrintedServing('32 g'), (
        said: (amount: 32.0, unit: g),
        bracketed: null,
      ));
      expect(readPrintedServing('2 pieces (30 g)'), (
        said: null,
        bracketed: (amount: 30.0, unit: g),
      ));
      // Nothing to read, and nothing invented from it.
      expect(readPrintedServing('1 bar'), (said: null, bracketed: null));
      expect(readPrintedServing(null), (said: null, bracketed: null));
      expect(readPrintedServing('2 tbsp (about a spoonful'), (
        said: (amount: 2.0, unit: tbsp),
        bracketed: null,
      ));
    });
  });

  test('the row’s serving is found among its measures, and only it', () {
    const measures = [
      Measure(id: 'a', label: 'medium', amount: 110),
      Measure(id: 'b', label: 'serving · 2 tbsp', amount: 29.57),
      Measure(id: 'c', label: 'pack', amount: 400, basis: MacrosBasis.perMl),
    ];
    expect(servingMeasureOf(measures)!.id, 'b');
    expect(servingMeasureOf(measures.where((m) => m.id != 'b')), isNull);
    expect(servingMeasureOf(const <Measure>[]), isNull);
    // The same question, asked of one row — what every list of measures uses
    // to leave the serving out.
    expect(measures.map(isServingMeasure), [false, true, false]);
  });

  test(
    'a serving chip says what one serving comes to, not the pack’s words',
    () {
      const serving = Measure(
        id: 'b',
        label: 'serving · 1 cup',
        amount: 236.5882365,
        basis: MacrosBasis.perMl,
      );
      expect(measureChipLabel(serving), 'serving (236.59 ml)');
      // Everything else keeps the word the household gave it.
      expect(
        measureChipLabel(const Measure(id: 'a', label: 'clove', amount: 3)),
        'clove',
      );
    },
  );
}
