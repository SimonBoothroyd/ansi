/// When a tick says a meal was eaten, and how the sheet prints it.
library;

import 'package:ansi/features/planning/presentation/meal_eaten_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final thursday = DateTime(2026, 8, 27);

  group('defaultEatenAt', () {
    test('a tick on the meal’s day is the moment of the tick', () {
      final now = DateTime(2026, 8, 27, 19, 42, 10);
      expect(defaultEatenAt(mealDay: thursday, now: now), now);
    });

    test('a later tick keeps the meal’s day at the tick’s clock', () {
      expect(
        defaultEatenAt(mealDay: thursday, now: DateTime(2026, 8, 29, 9, 15)),
        DateTime(2026, 8, 27, 9, 15),
      );
    });
  });

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
