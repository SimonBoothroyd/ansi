import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mondayOf', () {
    test("a mid-week date resolves to that week's Monday", () {
      // 2026-08-27 is a Thursday → Monday of that week is 2026-08-24.
      expect(mondayOf(DateTime(2026, 8, 27)), DateTime.utc(2026, 8, 24));
    });

    test('a Monday resolves to itself (date-only)', () {
      expect(
        mondayOf(DateTime(2026, 8, 24, 13, 30)),
        DateTime.utc(2026, 8, 24),
      );
    });

    test("a Sunday resolves back to the week's Monday", () {
      // 2026-08-30 is a Sunday → still the Aug 24 week.
      expect(mondayOf(DateTime(2026, 8, 30)), DateTime.utc(2026, 8, 24));
    });
  });

  group('mealSlotRank', () {
    test('orders the known slots in meal order', () {
      expect(mealSlotRank('Breakfast'), lessThan(mealSlotRank('Lunch')));
      expect(mealSlotRank('Lunch'), lessThan(mealSlotRank('Dinner')));
    });

    test('is case-insensitive', () {
      expect(mealSlotRank('dinner'), mealSlotRank('Dinner'));
    });

    test('ranks a custom slot after every known one', () {
      expect(mealSlotRank('Midnight snack'), kDefaultMealSlots.length);
      expect(mealSlotRank('Dinner'), lessThan(mealSlotRank('Brunch')));
    });
  });

  group('PlanEntry.portionsOrDefault', () {
    test('falls back to the eater count when portions is null', () {
      const e = PlanEntry(
        id: 'e',
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r',
        eaterIds: ['a', 'b'],
      );
      expect(e.portionsOrDefault, 2);
    });

    test('uses the override when set', () {
      const e = PlanEntry(
        id: 'e',
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r',
        eaterIds: ['a', 'b'],
        portions: 4,
      );
      expect(e.portionsOrDefault, 4);
    });
  });

  group('WeekPlan.entriesForDay', () {
    PlanEntry entry(String id, int day, String slot) =>
        PlanEntry(id: id, dayOfWeek: day, mealSlot: slot, recipeId: 'r');

    test('filters to the day and sorts by slot, stable within a slot', () {
      final week = WeekPlan(
        id: 'w',
        weekStart: DateTime.utc(2026, 8, 24),
        entries: [
          entry('a', 0, 'Dinner'),
          entry('b', 0, 'Breakfast'),
          entry('c', 0, 'Lunch'), // second lunch, added after b's breakfast
          entry('d', 0, 'Lunch'),
          entry('e', 1, 'Dinner'), // a different day, excluded
        ],
      );

      final monday = week.entriesForDay(0).map((e) => e.id).toList();
      // Breakfast, then the two Lunches in insertion order, then Dinner.
      expect(monday, ['b', 'c', 'd', 'a']);
      expect(week.entriesForDay(1).map((e) => e.id), ['e']);
    });
  });

  group('formatWeekOf', () {
    test('renders the Monday as "Week of Mon D"', () {
      expect(formatWeekOf(DateTime.utc(2026, 8, 24)), 'Week of Aug 24');
    });
  });
}
