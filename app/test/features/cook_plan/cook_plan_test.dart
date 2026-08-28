import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/cook_plan/domain/cook_plan.dart';

/// A recipe with [days] as (dayOfWeek → portions) meals, all on Dinner.
PlannedRecipe _recipe(
  Map<int, int> days, {
  String id = 'r',
  String title = 'Dish',
  double servings = 2,
  int? keeps,
  bool freezable = false,
  int? freezerDays,
}) => PlannedRecipe(
  recipeId: id,
  title: title,
  servingsBase: servings,
  keepsForDays: keeps,
  freezable: freezable,
  freezerDays: freezerDays,
  meals: [
    for (final e in days.entries)
      CoveredMeal(dayOfWeek: e.key, mealSlot: 'Dinner', portions: e.value),
  ],
);

void main() {
  group('clusterSessions — fridge window', () {
    test('an empty recipe yields no sessions', () {
      expect(clusterSessions(_recipe(const {})), isEmpty);
    });

    test('a single meal is one session cooked that day', () {
      final s = clusterSessions(_recipe({0: 2}, keeps: 4));
      expect(s, hasLength(1));
      expect(s.single.cookDay, 0);
      expect(s.single.totalPortions, 2);
      expect(s.single.coveredDays, [0]);
    });

    test('meals within the window stay in one session', () {
      // Mon + Thu, keeps 4 → gap 3 ≤ 4, one batch cooked Monday.
      final s = clusterSessions(_recipe({0: 2, 3: 2}, keeps: 4));
      expect(s, hasLength(1));
      expect(s.single.cookDay, 0);
      expect(s.single.coveredDays, [0, 3]);
      expect(s.single.totalPortions, 4);
      expect(s.single.frozenDays, isEmpty);
    });

    test('a meal past the window opens a second session (split)', () {
      // Mon + Sat, keeps 3 → gap 5 > 3, not freezable → two batches.
      final s = clusterSessions(_recipe({0: 2, 5: 2}, keeps: 3));
      expect(s, hasLength(2));
      expect(s[0].cookDay, 0);
      expect(s[0].coveredDays, [0]);
      expect(s[1].cookDay, 5);
      expect(s[1].coveredDays, [5]);
    });

    test('the window is measured from the cook day, not the previous meal', () {
      // Mon, Wed, Fri; keeps 3. Wed gap 2 ≤ 3, Fri gap 4 > 3 → split at Fri
      // (even though Fri is only 2 days after Wed).
      final s = clusterSessions(_recipe({0: 2, 2: 2, 4: 2}, keeps: 3));
      expect(s, hasLength(2));
      expect(s[0].coveredDays, [0, 2]);
      expect(s[1].coveredDays, [4]);
    });
  });

  group('clusterSessions — freezer merge', () {
    test('a freezable far meal merges as a frozen share, not a split', () {
      // Tue(1) + Sat(5), keeps 3, freezable no limit → gap 4 > 3 but freezer
      // rescues → one batch cooked Tuesday, Saturday served frozen.
      final s = clusterSessions(
        _recipe({1: 2, 5: 2}, keeps: 3, freezable: true),
      );
      expect(s, hasLength(1));
      expect(s.single.cookDay, 1);
      expect(s.single.coveredDays, [1, 5]);
      expect(s.single.frozenDays, [5]);
      expect(s.single.hasFreezerRescue, isTrue);
      expect(s.single.totalPortions, 4);
    });

    test('a meal past the freezer window still splits', () {
      // Mon + Sun(6), keeps 2, freezable but freezerDays 4 → gap 6 > 4 → split.
      final s = clusterSessions(
        _recipe({0: 2, 6: 2}, keeps: 2, freezable: true, freezerDays: 4),
      );
      expect(s, hasLength(2));
      expect(s[0].coveredDays, [0]);
      expect(s[1].coveredDays, [6]);
    });

    test('a within-fridge meal is not counted as frozen', () {
      // Mon + Wed, keeps 4, freezable → all fresh, nothing frozen.
      final s = clusterSessions(
        _recipe({0: 2, 2: 2}, keeps: 4, freezable: true),
      );
      expect(s.single.frozenDays, isEmpty);
      expect(s.single.hasFreezerRescue, isFalse);
    });
  });

  group('clusterSessions — window boundaries', () {
    test('a gap exactly equal to keeps stays one session', () {
      // Mon + Thu, keeps 3 → gap 3 ≤ 3: the boundary day is still fresh.
      final s = clusterSessions(_recipe({0: 2, 3: 2}, keeps: 3));
      expect(s, hasLength(1));
      expect(s.single.coveredDays, [0, 3]);
    });

    test('a gap of keeps + 1 splits', () {
      // Mon + Fri, keeps 3 → gap 4 > 3 → two batches.
      final s = clusterSessions(_recipe({0: 2, 4: 2}, keeps: 3));
      expect(s, hasLength(2));
      expect(s[0].coveredDays, [0]);
      expect(s[1].coveredDays, [4]);
    });

    test('a gap exactly equal to freezerDays merges frozen', () {
      // Mon + Fri, keeps 2, freezerDays 4 → gap 4 ≤ 4: freezer just reaches.
      final s = clusterSessions(
        _recipe({0: 2, 4: 2}, keeps: 2, freezable: true, freezerDays: 4),
      );
      expect(s, hasLength(1));
      expect(s.single.coveredDays, [0, 4]);
      expect(s.single.frozenDays, [4]);
    });

    test('a gap of freezerDays + 1 splits', () {
      // Mon + Sat, keeps 2, freezerDays 4 → gap 5 > 4 → the freezer cannot
      // rescue it.
      final s = clusterSessions(
        _recipe({0: 2, 5: 2}, keeps: 2, freezable: true, freezerDays: 4),
      );
      expect(s, hasLength(2));
      expect(s[0].coveredDays, [0]);
      expect(s[1].coveredDays, [5]);
    });

    test('a negative keeps_for_days is clamped to 0 (same-day still one '
        'cook)', () {
      // Bad data must not split two Monday meals into two cooks of the same
      // dish on the same day.
      final s = clusterSessions(
        _recipe(const {}, keeps: -2).copyWith(
          meals: const [
            CoveredMeal(dayOfWeek: 0, mealSlot: 'Lunch', portions: 1),
            CoveredMeal(dayOfWeek: 0, mealSlot: 'Dinner', portions: 2),
          ],
        ),
      );
      expect(s, hasLength(1));
      expect(s.single.totalPortions, 3);
      // The clamped value rides on the session, so frozenDays stays sane too.
      expect(s.single.keepsForDays, 0);
      expect(s.single.frozenDays, isEmpty);

      // Clamped to 0, not further: a next-day meal is past the window.
      final split = clusterSessions(_recipe({0: 2, 1: 2}, keeps: -2));
      expect(split, hasLength(2));
    });
  });

  group('clusterSessions — edge cases', () {
    test('unknown shelf life never splits', () {
      // No keeps → one session even for far-apart meals (never a made-up
      // window).
      final s = clusterSessions(_recipe({0: 2, 6: 2}));
      expect(s, hasLength(1));
      expect(s.single.coveredDays, [0, 6]);
      expect(s.single.frozenDays, isEmpty);
    });

    test('two meals on the same day sum portions in one session', () {
      // Mon lunch (1) + Mon dinner (2) → one session, 3 portions, one day.
      final s = clusterSessions(
        _recipe(const {}, keeps: 4).copyWith(
          meals: const [
            CoveredMeal(dayOfWeek: 0, mealSlot: 'Lunch', portions: 1),
            CoveredMeal(dayOfWeek: 0, mealSlot: 'Dinner', portions: 2),
          ],
        ),
      );
      expect(s, hasLength(1));
      expect(s.single.coveredDays, [0]);
      expect(s.single.totalPortions, 3);
    });
  });

  group('CookSession.scaleFactor', () {
    test('is total portions over base servings', () {
      // servings defaults to 2 → 3 portions is ×1.5.
      final s = clusterSessions(_recipe({0: 3}, keeps: 4)).single;
      expect(s.scaleFactor, 1.5);
    });

    test('is zero when base servings is zero (never divides by zero)', () {
      final s = clusterSessions(_recipe({0: 3}, servings: 0, keeps: 4)).single;
      expect(s.scaleFactor, 0);
    });
  });

  group('buildCookPlan', () {
    test('orders recipes by earliest cook day then title', () {
      final plan = buildCookPlan([
        _recipe({3: 2}, id: 'b', title: 'Zuppa', keeps: 4),
        _recipe({0: 2}, id: 'a', title: 'Curry', keeps: 4),
        _recipe({0: 2}, id: 'c', title: 'Apple', keeps: 4),
      ]);
      // Day 0 recipes first, ties broken by title (Apple, Curry); Zuppa last.
      expect(plan.recipes.map((r) => r.title), ['Apple', 'Curry', 'Zuppa']);
    });

    test('surfaces split and freezer rollups per recipe', () {
      final plan = buildCookPlan([
        _recipe({0: 2, 5: 2}, id: 'split', title: 'Split', keeps: 3),
        _recipe(
          {1: 2, 5: 2},
          id: 'frz',
          title: 'Frozen',
          keeps: 3,
          freezable: true,
        ),
      ]);
      final split = plan.recipes.firstWhere((r) => r.recipeId == 'split');
      final frozen = plan.recipes.firstWhere((r) => r.recipeId == 'frz');
      expect(split.isSplit, isTrue);
      expect(split.usesFreezer, isFalse);
      expect(split.totalPortions, 4);
      expect(frozen.isSplit, isFalse);
      expect(frozen.usesFreezer, isTrue);
      expect(frozen.days, [1, 5]);
    });

    test('an empty week is an empty plan', () {
      expect(buildCookPlan(const []).isEmpty, isTrue);
    });
  });

  group('batchHintFor', () {
    test('no existing meals → no hint', () {
      expect(
        batchHintFor(plannedDays: const [], newDay: 3, keepsForDays: 4),
        isNull,
      );
    });

    test('a meal within the fridge window joins that batch', () {
      // Curry already Monday; adding Thursday, keeps 4 → same batch, cook Mon.
      final hint = batchHintFor(
        plannedDays: const [0],
        newDay: 3,
        keepsForDays: 4,
      );
      expect(hint, isNotNull);
      expect(hint!.withDay, 0);
      expect(hint.frozen, isFalse);
    });

    test('a second meal on an already-planned day shares that batch', () {
      // Curry already Monday; adding another Monday meal → same batch, same
      // day (clusterSessions merges same-day meals — the hint must agree).
      final hint = batchHintFor(
        plannedDays: const [0],
        newDay: 0,
        keepsForDays: 4,
      );
      expect(hint, isNotNull);
      expect(hint!.withDay, 0);
      expect(hint.frozen, isFalse);
    });

    test('a meal past the window is its own cook (no hint)', () {
      expect(
        batchHintFor(plannedDays: const [0], newDay: 5, keepsForDays: 3),
        isNull,
      );
    });

    test('a freezable far meal joins the batch as a frozen share', () {
      // Ragù Tuesday; adding Saturday, keeps 3, freezable → frozen share.
      final hint = batchHintFor(
        plannedDays: const [1],
        newDay: 5,
        keepsForDays: 3,
        freezable: true,
      );
      expect(hint, isNotNull);
      expect(hint!.withDay, 1);
      expect(hint.frozen, isTrue);
    });
  });
}
