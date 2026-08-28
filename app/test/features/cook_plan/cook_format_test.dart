import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/cook_plan/domain/cook_plan.dart';
import 'package:mise/features/cook_plan/presentation/cook_format.dart';

CookSession _session({
  required int cookDay,
  required List<CoveredMeal> covers,
  int? keeps,
  bool freezable = false,
  int? freezerDays,
  double servings = 2,
}) => CookSession(
  recipeId: 'r',
  recipeTitle: 'Dish',
  servingsBase: servings,
  cookDay: cookDay,
  keepsForDays: keeps,
  freezable: freezable,
  freezerDays: freezerDays,
  covers: covers,
);

CoveredMeal _meal(int day, String slot, int portions) =>
    CoveredMeal(dayOfWeek: day, mealSlot: slot, portions: portions);

void main() {
  group('formatScale', () {
    test('trims trailing zeros', () {
      expect(formatScale(1), '×1');
      expect(formatScale(1.5), '×1.5');
      expect(formatScale(0.75), '×0.75');
      expect(formatScale(2), '×2');
    });
  });

  group('formatPortions', () {
    test('pluralizes properly', () {
      expect(formatPortions(1), '1 portion');
      expect(formatPortions(2), '2 portions');
    });
  });

  group('coversLine', () {
    test('a single portion reads singular', () {
      final s = _session(
        cookDay: 0,
        keeps: 3,
        covers: [_meal(0, 'Dinner', 1)],
      );
      expect(coversLine(s), 'covers Mon dinner · 1 portion');
    });

    test('collapses a shared slot to one label', () {
      final s = _session(
        cookDay: 1,
        keeps: 6,
        covers: [_meal(1, 'Dinner', 2), _meal(5, 'Dinner', 2)],
      );
      expect(coversLine(s), 'covers Tue + Sat dinner · 4 portions');
    });

    test('spells out mixed slots', () {
      final s = _session(
        cookDay: 0,
        keeps: 6,
        covers: [_meal(0, 'Dinner', 2), _meal(3, 'Lunch', 1)],
      );
      expect(coversLine(s), 'covers Mon dinner + Thu lunch · 3 portions');
    });
  });

  group('recipeSummaryLine', () {
    test('lists portions and shelf-life descriptors', () {
      const recipe = RecipeCookPlan(
        recipeId: 'r',
        title: 'Ragù',
        servingsBase: 2,
        keepsForDays: 4,
        freezable: true,
        sessions: [
          CookSession(
            recipeId: 'r',
            recipeTitle: 'Ragù',
            servingsBase: 2,
            cookDay: 1,
            keepsForDays: 4,
            freezable: true,
            covers: [
              CoveredMeal(dayOfWeek: 1, mealSlot: 'Dinner', portions: 4),
            ],
          ),
        ],
      );
      expect(
        recipeSummaryLine(recipe),
        '4 portions across the week · keeps 4 d · freezable',
      );
    });
  });

  group('freezerNoteFor', () {
    test('names the frozen day and the cook day', () {
      final s = _session(
        cookDay: 1,
        keeps: 3,
        freezable: true,
        covers: [_meal(1, 'Dinner', 2), _meal(5, 'Dinner', 2)],
      );
      expect(
        freezerNoteFor('Ragù', s),
        'Saturday is far off, but Ragù freezes — cook once Tuesday, freeze '
        "Saturday's share.",
      );
    });
  });

  group('CookTimelineSpec', () {
    test('a frozen session has an amber tail (to Sat), no gone tail', () {
      // Cook Tue(1), keeps 3 → fresh to Fri(4); Sat(5) frozen → amber Fri→Sat.
      final s = _session(
        cookDay: 1,
        keeps: 3,
        freezable: true,
        covers: [_meal(1, 'Dinner', 2), _meal(5, 'Dinner', 2)],
      );
      final spec = CookTimelineSpec.of(s);
      expect(spec.cookDay, 1);
      expect(spec.coveredDays, [1, 5]);
      expect(spec.freshTo, 4);
      expect(spec.frozenTo, 5); // amber reaches Saturday
      expect(spec.hasGone, isFalse);
    });

    test('a fresh session shows a gone tail where the window runs out', () {
      // Cook Mon(0), keeps 4 → fresh to Fri(4), then hatched to Sunday.
      final s = _session(
        cookDay: 0,
        keeps: 4,
        covers: [_meal(0, 'Dinner', 2), _meal(3, 'Dinner', 2)],
      );
      final spec = CookTimelineSpec.of(s);
      expect(spec.freshTo, 4);
      expect(spec.frozenTo, 4); // no amber
      expect(spec.hasGone, isTrue);
      expect(spec.coveredDays, [0, 3]);
    });

    test('a window reaching Sunday shows no gone tail', () {
      // Cook Fri(4), keeps 3 → fresh to Sun(6+ clamps to 6): no gone.
      final s = _session(cookDay: 4, keeps: 3, covers: [_meal(4, 'Dinner', 2)]);
      final spec = CookTimelineSpec.of(s);
      expect(spec.freshTo, 6);
      expect(spec.hasGone, isFalse);
    });

    test('unknown shelf life spans to the last meal, no tail', () {
      final s = _session(
        cookDay: 0,
        covers: [_meal(0, 'Dinner', 2), _meal(6, 'Dinner', 2)],
      );
      final spec = CookTimelineSpec.of(s);
      expect(spec.freshTo, 6);
      expect(spec.frozenTo, 6);
      expect(spec.hasGone, isFalse);
    });
  });
}
