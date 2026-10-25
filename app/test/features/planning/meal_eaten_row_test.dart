/// How the sheet prints when a meal was eaten.
library;

import 'package:ansi/features/planning/presentation/meal_eaten_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final thursday = DateTime(2026, 8, 27);

  group('eatenAtLabel', () {
    test('the clock alone on the meal’s day, the weekday otherwise', () {
      expect(
        eatenAtLabel(DateTime(2026, 8, 27, 19, 42), mealDay: thursday),
        '19:42',
      );
      expect(
        eatenAtLabel(DateTime(2026, 8, 28, 0, 5), mealDay: thursday),
        'Fri 00:05',
      );
    });
  });
}
