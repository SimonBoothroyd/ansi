import 'package:ansi/features/shopping/presentation/shopping_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("formatItemCount (the Shop tab's menu row, in its own words)", () {
    test('counts rolled-up items, never meals', () {
      expect(formatItemCount(0), 'nothing to buy');
      expect(formatItemCount(1), '1 item');
      expect(formatItemCount(6), '6 items');
    });
  });
}
