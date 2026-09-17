import 'package:ansi/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('under a dollar reads in cents, the way a shelf tag does', () {
      expect(formatMoney(77), '77¢');
      expect(formatMoney(5), '5¢');
      expect(formatMoney(99), '99¢');
    });

    test('nothing is 0¢, not an empty string', () {
      expect(formatMoney(0), '0¢');
    });

    test('a dollar and up reads in dollars, with both places', () {
      expect(formatMoney(100), r'$1.00');
      expect(formatMoney(349), r'$3.49');
      expect(formatMoney(110), r'$1.10');
      expect(formatMoney(1200), r'$12.00');
      expect(formatMoney(1205), r'$12.05');
    });

    test('a big figure keeps its cents rather than rounding away', () {
      expect(formatMoney(123456), r'$1234.56');
    });

    test('the sign leads the whole figure — it is a deduction', () {
      expect(formatMoney(-50), '-50¢');
      expect(formatMoney(-100), r'-$1.00');
      expect(formatMoney(-349), r'-$3.49');
    });
  });

  group('formatMoneyRounded', () {
    test('a derived figure rounds to the nearest whole cent', () {
      // $3.49 for a 454 g bag is 76.87…¢ per 100 g.
      expect(formatMoneyRounded(76.872), '77¢');
      expect(formatMoneyRounded(110.4), r'$1.10');
      expect(formatMoneyRounded(109.5), r'$1.10');
    });

    test('a whole number of cents prints exactly as the integer form', () {
      for (final cents in [0, 7, 99, 100, 349, 1200]) {
        expect(formatMoneyRounded(cents.toDouble()), formatMoney(cents));
      }
    });
  });
}
