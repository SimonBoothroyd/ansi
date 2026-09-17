import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mealSlotRank', () {
    test('orders the known slots in meal order', () {
      expect(mealSlotRank('Breakfast'), lessThan(mealSlotRank('Lunch')));
      expect(mealSlotRank('Lunch'), lessThan(mealSlotRank('Dinner')));
    });

    test('is case-insensitive', () {
      expect(mealSlotRank('dinner'), mealSlotRank('Dinner'));
    });

    test(
      'ranks Snack after Dinner, and a custom slot after every known one',
      () {
        expect(mealSlotRank('Dinner'), lessThan(mealSlotRank('Snack')));
        expect(mealSlotRank('Midnight snack'), kDefaultMealSlots.length);
        expect(mealSlotRank('Snack'), lessThan(mealSlotRank('Brunch')));
      },
    );
  });

  group('defaultMealSlot', () {
    PlanEntry entry(String slot) =>
        PlanEntry(id: slot, dayOfWeek: 0, mealSlot: slot, recipeId: 'r');

    test('an empty day starts at Breakfast', () {
      expect(defaultMealSlot(const []), 'Breakfast');
    });

    test('the first default the day has not filled, in day order', () {
      expect(defaultMealSlot([entry('Breakfast')]), 'Lunch');
      expect(defaultMealSlot([entry('Breakfast'), entry('Lunch')]), 'Dinner');
      expect(
        defaultMealSlot([entry('Breakfast'), entry('Lunch'), entry('Dinner')]),
        'Snack',
      );
    });

    test('a day holding only a dinner still starts at Breakfast', () {
      expect(defaultMealSlot([entry('Dinner')]), 'Breakfast');
    });

    test('Dinner once all four are filled', () {
      expect(
        defaultMealSlot([for (final s in kDefaultMealSlots) entry(s)]),
        'Dinner',
      );
    });

    test('a typed lower-case slot fills the default it names', () {
      expect(defaultMealSlot([entry('breakfast')]), 'Lunch');
      expect(defaultMealSlot([entry(' LUNCH '), entry('breakfast')]), 'Dinner');
    });

    test('a custom slot fills none of the defaults', () {
      expect(defaultMealSlot([entry('Brunch')]), 'Breakfast');
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

  group('demandPortions', () {
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

    test('with every factor at 1 it is the head-count to the digit', () {
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

  group('isValidPortionFactor', () {
    test('accepts the picks and every quarter step in range', () {
      for (final pick in kPortionFactorPicks) {
        expect(isValidPortionFactor(pick), isTrue, reason: '$pick');
      }
      expect(isValidPortionFactor(0.25), isTrue);
      expect(isValidPortionFactor(1.75), isTrue);
      expect(isValidPortionFactor(3), isTrue);
    });

    test('refuses out-of-range and off-step values', () {
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

  group('PlanEntry.kind', () {
    test('each of the three columns names its own kind', () {
      const dish = PlanEntry(
        id: 'a',
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
        recipeTitle: 'Curry',
      );
      const snack = PlanEntry(
        id: 'b',
        dayOfWeek: 0,
        mealSlot: 'Snack',
        ingredientId: 'i1',
        ingredientName: 'Protein bar',
      );
      const out = PlanEntry(
        id: 'c',
        dayOfWeek: 0,
        mealSlot: 'Lunch',
        label: 'Office lunch',
      );

      expect(dish.kind, PlanEntryKind.recipe);
      expect(snack.kind, PlanEntryKind.ingredient);
      expect(out.kind, PlanEntryKind.out);

      // The title is the thing each one names.
      expect(dish.title, 'Curry');
      expect(snack.title, 'Protein bar');
      expect(out.title, 'Office lunch');
    });

    test('a target that is GONE has its own sentence per kind, and a meal '
        'eaten out cannot lose one', () {
      const deletedDish = PlanEntry(
        id: 'a',
        dayOfWeek: 0,
        mealSlot: 'Dinner',
        recipeId: 'r1',
      );
      const unsyncedRow = PlanEntry(
        id: 'b',
        dayOfWeek: 0,
        mealSlot: 'Snack',
        ingredientId: 'i1',
      );
      const out = PlanEntry(
        id: 'c',
        dayOfWeek: 0,
        mealSlot: 'Lunch',
        label: 'Office lunch',
      );

      expect(deletedDish.title, isNull);
      expect(deletedTargetLabel(deletedDish), '(deleted recipe)');
      expect(unsyncedRow.title, isNull);
      expect(deletedTargetLabel(unsyncedRow), '(deleted ingredient)');
      // Its words ARE its target, so there is nothing for it to lose.
      expect(out.title, 'Office lunch');
    });

    test('a meal eaten out carries eaters and portions like any other', () {
      const out = PlanEntry(
        id: 'c',
        dayOfWeek: 0,
        mealSlot: 'Lunch',
        label: 'Office lunch',
        eaterIds: ['m1', 'm2'],
      );
      expect(out.portionsOrDefault, 2);
      expect(demandPortions(out, const {}), 2);
      // And it fills its slot, so the next add starts on the one after it.
      expect(defaultMealSlot([out]), 'Breakfast');
      expect(
        defaultMealSlot([
          out,
          const PlanEntry(id: 'd', dayOfWeek: 0, mealSlot: 'Breakfast'),
        ]),
        'Dinner',
      );
    });
  });

  group('formatWeekOf', () {
    test('renders the Monday as "Week of Mon D"', () {
      expect(formatWeekOf(DateTime.utc(2026, 8, 24)), 'Week of Aug 24');
    });
  });
}
