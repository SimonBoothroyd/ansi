/// What this phone's member ate, as Health Connect is told it, and the
/// difference from what was last sent.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/health/domain/health_meal.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';

const _members = {
  'ada': Member(id: 'ada', displayName: 'Ada'),
  'jun': Member(id: 'jun', displayName: 'Jun', portionFactor: 0.75),
};

/// 400 kcal / 30 P / 40 C / 10 F per serving.
const _curry = RecipeMacroSummary(
  perServing: Macros(kcal: 400, protein: 30, carb: 40, fat: 10),
);

RecipeMacroSummary? _summaries(String id) => id == 'curry' ? _curry : null;

final _weekStart = DateTime.utc(2026, 10, 19);
final _wednesdayEvening = DateTime(2026, 10, 21, 19, 42);

PlanEntry _dinner({
  String id = 'e1',
  String recipeId = 'curry',
  Map<String, DateTime> eatenAt = const {},
  Map<String, PlanEntry> had = const {},
}) => PlanEntry(
  id: id,
  dayOfWeek: 2,
  mealSlot: 'Dinner',
  recipeId: recipeId,
  recipeTitle: recipeId == 'curry' ? 'Curry' : 'Stub stew',
  eaterIds: const ['ada', 'jun'],
  eatenAt: eatenAt,
  had: had,
);

({List<HealthMeal> meals, List<String> notSent}) _for(
  List<PlanEntry> entries, {
  String me = 'jun',
}) => healthMealsIn(
  WeekPlan(id: 'w', weekStart: _weekStart, entries: entries),
  memberId: me,
  membersById: _members,
  summaryFor: _summaries,
);

void main() {
  group('mealTypeOf', () {
    test('reads the four default slots, and anything else as unknown', () {
      expect(mealTypeOf('Breakfast'), HealthMealType.breakfast);
      expect(mealTypeOf('dinner'), HealthMealType.dinner);
      expect(mealTypeOf('Snacks'), HealthMealType.snack);
      expect(mealTypeOf('Post-run'), HealthMealType.unknown);
    });
  });

  group('healthMealsIn', () {
    test('a ticked meal goes at its tick’s time, as my share', () {
      final found = _for([
        _dinner(eatenAt: {'jun': _wednesdayEvening}),
      ]);
      final meal = found.meals.single;
      expect(meal.id, healthMealId('e1', 'jun'));
      expect(meal.at, _wednesdayEvening);
      expect(meal.day, DateTime(2026, 10, 21));
      expect(meal.mealType, HealthMealType.dinner);
      // Jun's usual portion is ¾ of a serving.
      expect(meal.macros.kcal, closeTo(300, 1e-9));
    });

    test('only my own: a partner’s tick is never sent from here', () {
      expect(
        _for([
          _dinner(eatenAt: {'ada': _wednesdayEvening}),
        ]).meals,
        isEmpty,
      );
    });

    test('what I had instead goes under the planned meal’s id', () {
      final pizza = PlanEntry(
        id: 's1',
        dayOfWeek: 2,
        mealSlot: 'Dinner',
        label: 'Pizza with work',
        macros: const Macros(kcal: 1150, protein: 44, carb: 130, fat: 46),
        eaterIds: const ['jun'],
        insteadOf: 'e1',
        createdAt: DateTime(2026, 10, 22, 9, 15),
      );
      final meal = _for([
        _dinner(had: {'jun': pizza}),
      ]).meals.single;
      expect(meal.id, healthMealId('e1', 'jun'));
      expect(meal.name, 'Pizza with work');
      // Said the next morning: the meal's own day, at that clock time.
      expect(meal.at, DateTime(2026, 10, 21, 9, 15));
      expect(meal.macros.kcal, closeTo(1150 * 0.75, 1e-9));
    });

    test('what I had instead goes at the time I gave it, once I give one', () {
      final pizza = PlanEntry(
        id: 's1',
        dayOfWeek: 2,
        mealSlot: 'Dinner',
        label: 'Pizza with work',
        macros: const Macros(kcal: 1150, protein: 44, carb: 130, fat: 46),
        eaterIds: const ['jun'],
        insteadOf: 'e1',
        eatenAt: {'jun': DateTime(2026, 10, 21, 13, 5)},
        createdAt: DateTime(2026, 10, 22, 9, 15),
      );
      final meal = _for([
        _dinner(had: {'jun': pizza}),
      ]).meals.single;
      expect(meal.at, DateTime(2026, 10, 21, 13, 5));
    });

    test('a meal whose macros do not resolve is named, never sent', () {
      final found = _for([
        _dinner(recipeId: 'stub', eatenAt: {'jun': _wednesdayEvening}),
      ]);
      expect(found.meals, isEmpty);
      expect(found.notSent, ['Stub stew']);
    });
  });

  group('diffHealth', () {
    HealthMeal meal(String id, {double kcal = 400, int day = 21}) => HealthMeal(
      id: id,
      name: 'Curry',
      day: DateTime(2026, 10, day),
      at: DateTime(2026, 10, day, 19),
      mealType: HealthMealType.dinner,
      macros: Macros(kcal: kcal, protein: 30, carb: 40, fat: 10),
    );
    final window = DateTime.utc(2026, 10, 12);

    test('writes what is new or changed, and nothing unchanged', () {
      final same = meal('a');
      final plan = diffHealth(
        [same, meal('b', kcal: 500)],
        {'a': same.contentKey, 'b': meal('b').contentKey},
        windowStart: window,
      );
      expect(plan.write.map((m) => m.id), ['b']);
      expect(plan.delete, isEmpty);
    });

    test('takes back what is no longer eaten', () {
      final plan = diffHealth(const [], {
        'a': meal('a').contentKey,
      }, windowStart: window);
      expect(plan.delete, ['a']);
      expect(plan.keep, isEmpty);
    });

    test('never takes back a meal that has merely left the window', () {
      final plan = diffHealth(const [], {
        'old': meal('old', day: 5).contentKey,
      }, windowStart: window);
      expect(plan.delete, isEmpty);
    });
  });
}
