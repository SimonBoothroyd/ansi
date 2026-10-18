/// The size a receipt's printed name states, read off the owner's own
/// Whole Foods order.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/receipts/domain/printed_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a name that states its size', () {
    for (final (name, amount, unit) in [
      (
        '365 by Whole Foods Market, Organic Unsweetened Soymilk, 64 fl oz',
        64.0,
        flOz,
      ),
      ('Beyond Meat Beyond Beef Plant Based Ground Brick, 12 Ounce', 12.0, oz),
      (
        '365 by Whole Foods Market, Unsalted Garbanzo Beans, 15.5 Ounce',
        15.5,
        oz,
      ),
      ('Non Dairy Mozzarella Cheese Shreds, 8 OZ', 8.0, oz),
      ('SUNSET Flavor Bombs Tomatoes On-The-Vine, 12oz', 12.0, oz),
      ('Olive Oil, 500 ml', 500.0, ml),
      ('Basmati Rice 1kg', 1.0, kg),
      ('Ground Coffee, 1-lb', 1.0, lb),
      ('Oat Drink 32 fl. oz', 32.0, flOz),
    ]) {
      test(name, () {
        final size = sizeInPrintedName(name);
        expect(size?.amount, amount);
        expect(size?.unit, unit);
      });
    }

    test('a nutrition claim is not the size', () {
      final size = sizeInPrintedName(
        'Icelandic Provisions Oatmilk Skyr Yogurt, Vanilla Bean, 5oz | Thick & '
        'Creamy Non-Dairy Yogurt, 12g Protein',
      );
      expect(size?.amount, 5);
      expect(size?.unit, oz);
      expect(sizeInPrintedName('Protein Bar, 20g Protein'), isNull);
    });
  });

  group('a name that states none says nothing', () {
    for (final name in [
      null,
      'Organic Cucumber',
      'Lemon, 1 Each',
      'Greens Kale Green Organic, 1 Bunch',
      'Brami Italian Protein Cubetti Pasta',
      // One of several: the count is not on the line.
      'Sparkling Water, 12 fl oz (Pack of 8)',
      'Yogurt 4 ct, 5.3 oz',
      'Cola 6 x 330 ml',
    ]) {
      test('$name', () => expect(sizeInPrintedName(name), isNull));
    }
  });
}
