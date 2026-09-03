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

  group('demandPortions (plan 0027 P-D1)', () {
    const ada = Member(id: 'ada', displayName: 'Ada');
    const jun = Member(id: 'jun', displayName: 'Jun', portionFactor: 0.75);
    const roster = {'ada': ada, 'jun': jun};

    PlanEntry entry({
      List<String> eaters = const ['ada', 'jun'],
      int? portions,
    }) => PlanEntry(
      id: 'e',
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'r',
      eaterIds: eaters,
      portions: portions,
    );

    test('a member eats one portion unless the household says otherwise', () {
      expect(ada.portionFactor, 1);
    });

    test('demand is the sum of the eaters’ factors — 1¾ for a 1 and a ¾', () {
      expect(demandPortions(entry(), roster), 1.75);
      expect(demandPortions(entry(eaters: ['jun']), roster), 0.75);
    });

    test('the whole-number override still wins, whoever is eating', () {
      expect(demandPortions(entry(portions: 3), roster), 3);
      // An override with nobody down to eat is still a real demand.
      expect(demandPortions(entry(eaters: const [], portions: 3), roster), 3);
    });

    test('with every factor at 1 it is the head-count to the digit (P-D6)', () {
      final e = entry();
      expect(demandPortions(e, const {}), e.portionsOrDefault);
      expect(demandPortions(e, {'ada': ada}), e.portionsOrDefault);
    });

    test('an eater the roster no longer holds counts one, as the head-count '
        'did', () {
      expect(demandPortions(entry(eaters: ['ada', 'gone']), roster), 2);
    });

    test('no eaters and no override is no demand', () {
      expect(demandPortions(entry(eaters: const []), roster), 0);
    });
  });

  group('isValidPortionFactor (P-D2)', () {
    test('accepts the picks and every quarter step in range', () {
      for (final pick in kPortionFactorPicks) {
        expect(isValidPortionFactor(pick), isTrue, reason: '$pick');
      }
      expect(isValidPortionFactor(0.25), isTrue);
      expect(isValidPortionFactor(1.75), isTrue);
      expect(isValidPortionFactor(3), isTrue);
    });

    test('refuses out-of-range and off-step values (the 0026 check)', () {
      expect(isValidPortionFactor(0), isFalse);
      expect(isValidPortionFactor(3.25), isFalse);
      expect(isValidPortionFactor(0.83), isFalse);
      expect(isValidPortionFactor(1.1), isFalse);
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
