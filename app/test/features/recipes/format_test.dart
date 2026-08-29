import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/recipes/presentation/format.dart';

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
  });

  group('formatQuantity', () {
    test('whole numbers drop the point, others cap at two decimals', () {
      expect(formatQuantity(2), '2');
      expect(formatQuantity(2.25), '2.25');
      expect(formatQuantity(2.5), '2.5');
      expect(formatQuantity(null), '');
    });
  });
}
