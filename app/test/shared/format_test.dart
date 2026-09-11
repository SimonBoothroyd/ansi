import 'package:ansi/shared/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDensity (the conversion line citation)', () {
    test('caps at three significant digits', () {
      expect(formatDensity(1.03958), '1.04');
      expect(formatDensity(0.912345), '0.912');
    });

    test('trims trailing zeros and bare points', () {
      expect(formatDensity(0.5), '0.5');
      expect(formatDensity(1), '1');
      expect(formatDensity(1.10), '1.1');
    });

    test('a ≥1000 value never renders scientific notation', () {
      // toStringAsPrecision(3) would say "1.23e+3" — bad stored data still
      // has to read like a number.
      expect(formatDensity(1234.5), '1235');
      expect(formatDensity(1000), '1000');
      expect(formatDensity(999.6), '1000');
      expect(formatDensity(999.4), '999');
    });
  });

  group('formatQuantity', () {
    test('a kitchen fraction where there is one, else the capped decimal', () {
      expect(formatQuantity(2), '2');
      expect(formatQuantity(2.25), '2 1/4');
      expect(formatQuantity(2.5), '2 1/2');
      expect(formatQuantity(2.2), '2.2');
      expect(formatQuantity(null), '');
    });
  });
}
