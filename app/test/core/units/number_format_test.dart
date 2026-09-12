/// The one printing rule and the one reading rule, table-driven.
///
/// The pair has to round-trip in the direction that matters: what
/// [formatAmount] prints, [parseAmount] must read back to the same value —
/// otherwise opening a field and closing it untouched is a silent edit.
library;

import 'package:ansi/core/units/number_format.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatNumber — the fallback', () {
    const cases = <({double value, String prints})>[
      (value: 1, prints: '1'),
      (value: 0, prints: '0'),
      (value: 12.75, prints: '12.75'),
      (value: 0.3333333333333333, prints: '0.33'),
      (value: 1.5, prints: '1.5'),
      (value: 1.005, prints: '1'),
      (value: -2.5, prints: '-2.5'),
    ];
    for (final c in cases) {
      test('${c.value} prints ${c.prints}', () {
        expect(formatNumber(c.value), c.prints);
      });
    }
  });

  group('formatAmount — halves, thirds, quarters, eighths', () {
    final cases = <({double value, String prints})>[
      // The fractions themselves, whole-less and with a whole in front.
      (value: 0.5, prints: '½'),
      (value: 1.5, prints: '1½'),
      (value: 0.25, prints: '¼'),
      (value: 0.75, prints: '¾'),
      (value: 2.75, prints: '2¾'),
      (value: 12.75, prints: '12¾'),
      (value: 0.125, prints: '⅛'),
      (value: 1.125, prints: '1⅛'),
      (value: 0.375, prints: '⅜'),
      (value: 0.625, prints: '⅝'),
      (value: 0.875, prints: '⅞'),
      (value: 1 / 3, prints: '⅓'),
      (value: 2 / 3, prints: '⅔'),
      (value: 4 / 3, prints: '1⅓'),
      // A value already rounded on its way in still reads as what it was.
      (value: 0.67, prints: '⅔'),
      (value: 0.33, prints: '⅓'),
      (value: 0.13, prints: '⅛'),
      (value: 0.5075, prints: '½'),
      // …and a number somebody meant survives.
      (value: 0.26, prints: '0.26'),
      (value: 0.1, prints: '0.1'),
      (value: 0.9, prints: '0.9'),
      (value: 0.2, prints: '0.2'),
      // Whole numbers never grow a fraction.
      (value: 0, prints: '0'),
      (value: 1, prints: '1'),
      (value: 12, prints: '12'),
      // A fraction is offered in its lowest terms: 2/4 is a half.
      (value: 2.5, prints: '2½'),
      // The sign rides in front of the whole thing.
      (value: -0.5, prints: '-½'),
      (value: -1.25, prints: '-1¼'),
      // Nothing a kitchen says — the fallback answers.
      (value: 12.4, prints: '12.4'),
      (value: 236.59, prints: '236.59'),
    ];
    for (final c in cases) {
      test('${c.value} prints ${c.prints}', () {
        expect(formatAmount(c.value), c.prints);
      });
    }

    test('a glyph sits tight against its whole — never a slash, never a '
        'space', () {
      for (var i = 1; i <= 40; i++) {
        final printed = formatAmount(i / 8);
        expect(printed, isNot(contains('/')));
        expect(printed, isNot(contains(' ')));
      }
      expect(formatAmount(9 / 8), '1⅛');
    });
  });

  group('parseAmount', () {
    final cases = <({String text, double? reads})>[
      (text: '1', reads: 1),
      (text: '1.5', reads: 1.5),
      (text: '1,5', reads: 1.5),
      (text: '  2 ', reads: 2),
      (text: '0.26', reads: 0.26),
      (text: '1/2', reads: 0.5),
      (text: '3/4', reads: 0.75),
      (text: '1 1/2', reads: 1.5),
      (text: '10 3/8', reads: 10.375),
      (text: '1 / 2', reads: 0.5),
      (text: '½', reads: 0.5),
      (text: '1½', reads: 1.5),
      (text: '1 ½', reads: 1.5),
      (text: '¾', reads: 0.75),
      (text: '⅛', reads: 0.125),
      (text: '⅔', reads: 2 / 3),
      (text: '-1/2', reads: -0.5),
      (text: '-1 1/2', reads: -1.5),
      // The refusal path.
      (text: '', reads: null),
      (text: '   ', reads: null),
      (text: 'a lot', reads: null),
      (text: '1/0', reads: null),
      (text: '1/', reads: null),
      (text: '/2', reads: null),
      (text: '1 2', reads: null),
      (text: '½½', reads: null),
    ];
    for (final c in cases) {
      test('"${c.text}" reads as ${c.reads}', () {
        final parsed = parseAmount(c.text);
        final expected = c.reads;
        if (expected == null) {
          expect(parsed, isNull);
        } else {
          expect(parsed, closeTo(expected, 1e-12));
        }
      });
    }

    test('a fraction stores its own value, not its printed rounding', () {
      expect(parseAmount('2/3'), closeTo(2 / 3, 1e-12));
      expect(parseAmount('2/3'), isNot(0.67));
      expect(parseAmount('⅓'), closeTo(1 / 3, 1e-12));
    });
  });

  group('formatAmountIn — the unit decides which rule', () {
    test('a scale and a jug read decimals, never halves', () {
      expect(formatAmountIn(213.5, g), '213.5');
      expect(formatAmountIn(1.5, l), '1.5');
      expect(formatAmountIn(0.25, kg), '0.25');
      expect(formatAmountIn(672.75, g), '672.75');
      expect(formatAmountIn(236.59, ml), '236.59');
    });

    test('a whole metric figure still drops its .0', () {
      expect(formatAmountIn(400, g), '400');
      expect(formatAmountIn(2, l), '2');
    });

    test("a cook's own units keep their fractions", () {
      expect(formatAmountIn(2 / 3, cup), '⅔');
      expect(formatAmountIn(0.5, tbsp), '½');
      expect(formatAmountIn(2.25, pieces), '2¼');
      expect(formatAmountIn(1.5, flOz), '1½');
      expect(formatAmountIn(0.25, lb), '¼');
      expect(formatAmountIn(0.5, oz), '½');
      expect(formatAmountIn(0.75, batches), '¾');
    });

    test('every catalog unit agrees with one rule or the other', () {
      for (final unit in kAllUnits) {
        expect(
          formatAmountIn(0.5, unit),
          unit.isMetric ? formatNumber(0.5) : formatAmount(0.5),
          reason: '${unit.id} printed through the wrong rule',
        );
      }
    });
  });

  test('what formatAmount prints, parseAmount reads back — and so does the '
      'ASCII a person types', () {
    expect(parseAmount('1 1/2'), parseAmount(formatAmount(1.5)));
    expect(parseAmount('2/3'), closeTo(parseAmount('⅔')!, 1e-12));
    for (var eighths = 0; eighths <= 64; eighths++) {
      final value = eighths / 8;
      expect(
        parseAmount(formatAmount(value)),
        closeTo(value, 1e-9),
        reason: 'round trip broke at $value ("${formatAmount(value)}")',
      );
    }
    for (final value in [1 / 3, 2 / 3, 4 / 3, 12.75, 236.59, 0.26]) {
      expect(
        parseAmount(formatAmount(value)),
        closeTo(value, 0.005),
        reason: 'round trip broke at $value ("${formatAmount(value)}")',
      );
    }
  });
}
