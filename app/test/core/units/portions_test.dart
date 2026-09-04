import 'package:ansi/core/units/portions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    test('a value that is not a quarter prints as a trimmed decimal', () {
      // Jun's share of an override of 3 between a 1 and a ¾ eater.
      expect(formatFraction(3 * 0.75 / 1.75), '1.29');
      expect(formatFraction(1 / 3), '0.33');
      expect(formatFraction(1.2), '1.2');
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
