import 'package:ansi/core/units/portions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wholeBelow / wholeAbove — a part steps to a whole first', () {
    const cases = <({double from, double down, double up})>[
      (from: 1.75, down: 1, up: 2),
      (from: 0.75, down: 0, up: 1),
      (from: 2.5, down: 2, up: 3),
      (from: 2, down: 1, up: 3),
      (from: 1, down: 0, up: 2),
      // Float noise on a whole is the whole.
      (from: 0.1 + 0.2 + 0.7, down: 0, up: 2),
    ];
    for (final c in cases) {
      test('${c.from}: − ${c.down}, + ${c.up}', () {
        expect(wholeBelow(c.from), c.down);
        expect(wholeAbove(c.from), c.up);
      });
    }
  });

  group('formatFraction', () {
    test('a whole number prints plain, never with a .0', () {
      expect(formatFraction(1), '1');
      expect(formatFraction(4), '4');
      expect(formatFraction(0), '0');
    });

    test('a quarter prints as its glyph, with the whole part in front', () {
      expect(formatFraction(0.25), '¼');
      expect(formatFraction(0.5), '½');
      expect(formatFraction(0.75), '¾');
      expect(formatFraction(1.75), '1¾');
      expect(formatFraction(2.25), '2¼');
      expect(formatFraction(2.5), '2½');
    });

    test('float noise on a whole or a quarter is absorbed', () {
      expect(formatFraction(0.1 + 0.2 + 0.7), '1');
      expect(formatFraction(3 * 0.25), '¾');
      expect(formatFraction(4 - 1.75), '2¼');
    });

    test('a value that is not a quarter falls through to the amount rule', () {
      // Jun's share of an override of 3 between a 1 and a ¾ eater.
      expect(formatFraction(3 * 0.75 / 1.75), '1.29');
      expect(formatFraction(1.2), '1.2');
      // A third is not one of the quarters this rule keeps of its own, but
      // it is still a fraction a kitchen says, and the amount rule prints it.
      expect(formatFraction(1 / 3), '⅓');
    });
  });

  group('formatPortions', () {
    test('one and less than one are singular, more than one plural', () {
      expect(formatPortions(1), '1 portion');
      expect(formatPortions(0.75), '¾ portion');
      expect(formatPortions(0.5), '½ portion');
      expect(formatPortions(1.75), '1¾ portions');
      expect(formatPortions(2), '2 portions');
      expect(formatPortions(4), '4 portions');
      expect(formatPortions(0), '0 portions');
    });
  });
}
