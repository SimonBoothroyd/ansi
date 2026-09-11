import 'package:ansi/core/aisles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('aisleKey', () {
    test('trims and lower-cases a stored category', () {
      expect(aisleKey('  Produce '), 'produce');
      expect(aisleKey('Spices & Seasoning'), 'spices & seasoning');
    });

    test('a row that names none groups under the uncategorised key', () {
      expect(aisleKey(null), kUncategorisedAisle);
      expect(aisleKey('   '), kUncategorisedAisle);
    });
  });

  group('aisleLabel', () {
    test('title-cases for display', () {
      expect(aisleLabel('spices & seasoning'), 'Spices & Seasoning');
      expect(aisleLabel('produce'), 'Produce');
    });

    test('the uncategorised key reads "Other"', () {
      expect(aisleLabel(kUncategorisedAisle), 'Other');
    });
  });

  group('compareAisles', () {
    test('the known aisles keep shop-walk order, not alphabetical', () {
      final keys = ['pantry', 'dairy', 'produce', 'baking']
        ..sort(compareAisles);
      expect(keys, ['produce', 'dairy', 'baking', 'pantry']);
    });

    test('a coined category sorts after every known aisle', () {
      final keys = ['condiments', 'produce', 'bakery']..sort(compareAisles);
      expect(keys, ['produce', 'bakery', 'condiments']);
    });

    test('"Other" lands ahead of the coined ones, after the known', () {
      final keys = [kUncategorisedAisle, 'condiments', 'meat']
        ..sort(compareAisles);
      expect(keys, ['meat', kUncategorisedAisle, 'condiments']);
    });
  });
}
