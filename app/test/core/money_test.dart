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

  group('formatMoneyWhole', () {
    test('a list-scale estimate reads to the dollar', () {
      expect(formatMoneyWhole(7134), r'$71');
      expect(formatMoneyWhole(7150), r'$72');
      expect(formatMoneyWhole(5800), r'$58');
      expect(formatMoneyWhole(-812), r'-$8');
    });

    test('under a dollar it keeps the cents spelling, never \$0', () {
      expect(formatMoneyWhole(76.4), '76¢');
      expect(formatMoneyWhole(99.6), r'$1');
      expect(formatMoneyWhole(0), '0¢');
    });
  });

  group('parseMoney', () {
    test('dollars and cents become whole cents', () {
      expect(parseMoney('3.49'), 349);
      expect(parseMoney('0.77'), 77);
      expect(parseMoney('12'), 1200);
      expect(parseMoney('1.1'), 110);
      expect(parseMoney('.5'), 50);
      expect(parseMoney('0'), 0);
    });

    test('a comma reads as the decimal separator', () {
      expect(parseMoney('3,49'), 349);
    });

    test('the symbol the field already prints is tolerated', () {
      expect(parseMoney(r'$3.49'), 349);
      expect(parseMoney(r'  $ 3.49 '), 349);
    });

    test('a third decimal is money that does not exist — refused', () {
      expect(parseMoney('3.499'), isNull);
    });

    test('a fraction is a typo in a price field, not two thirds', () {
      expect(parseMoney('2/3'), isNull);
      expect(parseMoney('½'), isNull);
    });

    test('nothing typed is not zero', () {
      expect(parseMoney(''), isNull);
      expect(parseMoney('   '), isNull);
      expect(parseMoney('.'), isNull);
    });

    test('a price is what was paid — nothing negative', () {
      expect(parseMoney('-3.49'), isNull);
    });

    test('what it reads, formatMoney prints back', () {
      for (final typed in ['3.49', '0.77', '12', '1.10']) {
        final cents = parseMoney(typed)!;
        expect(parseMoney(formatMoney(cents).replaceAll('¢', '')), isNotNull);
      }
    });
  });
}
