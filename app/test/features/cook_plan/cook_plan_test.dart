import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recipe with [days] as (dayOfWeek → portions) meals, all on Dinner.
PlannedRecipe _recipe(
  Map<int, num> days, {
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
      CoveredMeal(
        dayOfWeek: e.key,
        mealSlot: 'Dinner',
        portions: e.value.toDouble(),
      ),
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

  group('wholeBatchNudgeFor', () {
    CookSession session({double servings = 4, double portions = 3}) =>
        clusterSessions(_recipe({0: portions}, servings: servings)).single;

    test('a fractional factor nudges up to the next whole batch', () {
      // 3 portions of a serves-4 recipe: ×0.75 → cook ×1, 1 left over.
      final nudge = wholeBatchNudgeFor(session());
      expect(nudge, isNotNull);
      expect(nudge!.factor, 1);
      expect(nudge.batchPortions, 4);
      expect(nudge.leftoverPortions, 1);
    });

    test('rounds up past one whole batch too (×1.5 → ×2)', () {
      // 3 portions (the default) of a serves-2 recipe.
      final nudge = wholeBatchNudgeFor(session(servings: 2));
      expect(nudge!.factor, 2);
      expect(nudge.batchPortions, 4);
      expect(nudge.leftoverPortions, 1);
    });

    test('a whole factor needs no nudge', () {
      expect(wholeBatchNudgeFor(session(servings: 2, portions: 4)), isNull);
      // 3 portions (the default) of a serves-3 recipe: exactly ×1.
      expect(wholeBatchNudgeFor(session(servings: 3)), isNull);
    });

    test('float noise on a whole factor is not a nudge', () {
      // 0.1 + 0.2 style noise: 4.5 servings × (9/4.5 = 2.0000…) stays whole.
      final s = clusterSessions(_recipe({0: 9}, servings: 4.5)).single;
      expect(wholeBatchNudgeFor(s), isNull);
    });

    test('a fractional demand is scaled and nudged exactly as a whole one — '
        'never rounded up first', () {
      // A 1 and a ¾ eater of a serves-4 recipe: ×0.4375 → cook ×1, 2¼ over.
      final s = session(portions: 1.75);
      expect(s.totalPortions, 1.75);
      expect(s.scaleFactor, 0.4375);
      final nudge = wholeBatchNudgeFor(s);
      expect(nudge!.factor, 1);
      expect(nudge.batchPortions, 4);
      expect(nudge.leftoverPortions, 2.25);
    });

    test('fractional servings_base yields honest fractional leftovers', () {
      // serves 2.5, 2 portions wanted: ×0.8 → cook ×1 = 2.5, 0.5 left over.
      final nudge = wholeBatchNudgeFor(session(servings: 2.5, portions: 2));
      expect(nudge!.factor, 1);
      expect(nudge.batchPortions, 2.5);
      expect(nudge.leftoverPortions, closeTo(0.5, 1e-9));
    });

    test('degenerate inputs never nudge (invariant 3: no invented factor)', () {
      // servings_base 0 → scaleFactor 0; nothing honest to suggest.
      const zeroServings = CookSession(
        recipeId: 'r',
        recipeTitle: 'Dish',
        servingsBase: 0,
        cookDay: 0,
        covers: [CoveredMeal(dayOfWeek: 0, mealSlot: 'Dinner', portions: 2)],
      );
      expect(wholeBatchNudgeFor(zeroServings), isNull);
      // No covered portions → factor 0.
      const noPortions = CookSession(
        recipeId: 'r',
        recipeTitle: 'Dish',
        servingsBase: 2,
        cookDay: 0,
      );
      expect(wholeBatchNudgeFor(noPortions), isNull);
    });
  });

  group('component expansion', () {
    // Sausage Sliders (serves 8) with "¼ cup Romesco Aioli"; the aioli makes
    // 1 cup and keeps 5 days. The exec plan's own worked example.
    ComponentRecipe sliders({List<ComponentLine> components = const []}) => (
      title: 'Sausage Sliders',
      servingsBase: 8,
      keepsForDays: 3,
      freezable: false,
      freezerDays: null,
      measures: const <RecipeMeasure>[],
      yields: const <YieldDenomination>[],
      components: components,
    );
    ComponentRecipe aioli({
      List<YieldDenomination> yields = const [(qty: 1.0, unit: cup)],
      int? keeps = 5,
      bool freezable = false,
      int? freezerDays,
      List<ComponentLine> components = const [],
    }) => (
      title: 'Romesco Aioli',
      servingsBase: 4,
      keepsForDays: keeps,
      freezable: freezable,
      freezerDays: freezerDays,
      measures: const <RecipeMeasure>[],
      yields: yields,
      components: components,
    );

    const quarterCup = (
      id: 'li-aioli',
      subRecipeId: 'aioli',
      quantity: 0.25,
      unit: cup,
      recipeMeasureId: null,
      optional: false,
    );

    test('a planned parent derives a batch-denominated component session', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'aioli': aioli(),
        },
      );

      final derived = plan.recipes.firstWhere((r) => r.recipeId == 'aioli');
      final session = derived.sessions.single;
      expect(session.isComponent, isTrue);
      // Parent scale ×1 (8 portions of a serves-8 recipe) × ¼ batch.
      expect(session.batchesToCook, closeTo(0.25, 1e-12));
      expect(session.scaleFactor, closeTo(0.25, 1e-12));
      // Cook on or before the demanding parent's cook day.
      expect(session.cookDay, 5);
      expect(session.demandedBy, ['Sausage Sliders']);
      // Portions are not its denomination.
      expect(session.totalPortions, 0);
      expect(plan.gaps, isEmpty);
    });

    test(
      'the parent session scale multiplies through: 16 sliders wants ½ cup',
      () {
        final plan = buildCookPlan(
          [
            _recipe(
              {5: 16},
              id: 'sliders',
              title: 'Sausage Sliders',
              servings: 8,
            ),
          ],
          components: {
            'sliders': sliders(components: const [quarterCup]),
            'aioli': aioli(),
          },
        );
        expect(
          plan.recipes
              .firstWhere((r) => r.recipeId == 'aioli')
              .sessions
              .single
              .batchesToCook,
          closeTo(0.5, 1e-12),
        );
      },
    );

    test(
      'demands from TWO parents cluster into one batch, labelled with both',
      () {
        final plan = buildCookPlan(
          [
            _recipe(
              {5: 8},
              id: 'sliders',
              title: 'Sausage Sliders',
              servings: 8,
            ),
            _recipe({6: 2}, id: 'toasts', title: 'Romesco Toasts'),
          ],
          components: {
            'sliders': sliders(components: const [quarterCup]),
            'toasts': (
              title: 'Romesco Toasts',
              servingsBase: 2,
              keepsForDays: null,
              freezable: false,
              freezerDays: null,
              measures: const <RecipeMeasure>[],
              yields: const <YieldDenomination>[],
              components: const [
                (
                  id: 'li-aioli',
                  subRecipeId: 'aioli',
                  quantity: 1.0,
                  unit: batches,
                  recipeMeasureId: null,
                  optional: false,
                ),
              ],
            ),
            'aioli': aioli(),
          },
        );

        final derived = plan.recipes.firstWhere((r) => r.recipeId == 'aioli');
        // One cook: Saturday and Sunday are inside the aioli's 5-day window.
        expect(derived.sessions, hasLength(1));
        final session = derived.sessions.single;
        expect(session.batchesToCook, closeTo(1.25, 1e-12));
        expect(session.cookDay, 5);
        expect(session.demandedBy, ['Sausage Sliders', 'Romesco Toasts']);
        expect(session.coveredDays, [5, 6]);
      },
    );

    test("the sub-recipe's OWN shelf life splits the component sessions", () {
      final plan = buildCookPlan(
        [
          _recipe({0: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
          _recipe({6: 2}, id: 'toasts', title: 'Romesco Toasts'),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'toasts': (
            title: 'Romesco Toasts',
            servingsBase: 2,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const <YieldDenomination>[],
            components: const [
              (
                id: 'li-aioli',
                subRecipeId: 'aioli',
                quantity: 1.0,
                unit: batches,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'aioli': aioli(),
        },
      );
      final derived = plan.recipes.firstWhere((r) => r.recipeId == 'aioli');
      // Mon → Sun is 6 days, past the aioli's 5-day fridge window.
      expect(derived.sessions, hasLength(2));
      expect(derived.sessions.map((s) => s.cookDay), [0, 6]);
    });

    test('a freezable sub-recipe folds the far demand into one batch', () {
      final plan = buildCookPlan(
        [
          _recipe({0: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
          _recipe({6: 2}, id: 'toasts', title: 'Romesco Toasts'),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'toasts': (
            title: 'Romesco Toasts',
            servingsBase: 2,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const <YieldDenomination>[],
            components: const [
              (
                id: 'li-aioli',
                subRecipeId: 'aioli',
                quantity: 1.0,
                unit: batches,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'aioli': aioli(freezable: true, freezerDays: 30),
        },
      );
      final session = plan.recipes
          .firstWhere((r) => r.recipeId == 'aioli')
          .sessions
          .single;
      expect(session.batchesToCook, closeTo(1.25, 1e-12));
      expect(session.hasFreezerRescue, isTrue);
      expect(session.frozenDays, [6]);
    });

    test('recursion multiplies through a component of a component', () {
      final plan = buildCookPlan(
        [
          _recipe({3: 4}, id: 'top', title: 'Top', servings: 4),
        ],
        components: {
          'top': (
            title: 'Top',
            servingsBase: 4,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const <YieldDenomination>[],
            components: const [
              (
                id: 'li-mid',
                subRecipeId: 'mid',
                quantity: 2.0,
                unit: batches,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'mid': (
            title: 'Middle Sauce',
            servingsBase: 2,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const [(qty: 1.0, unit: cup)],
            components: const [
              (
                id: 'li-aioli',
                subRecipeId: 'aioli',
                quantity: 0.5,
                unit: cup,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'aioli': aioli(),
        },
      );
      final deep = plan.recipes
          .firstWhere((r) => r.recipeId == 'aioli')
          .sessions
          .single;
      // 2 batches of the sauce × ½ cup of a 1-cup aioli = 1 batch.
      expect(deep.batchesToCook, closeTo(1, 1e-12));
      // Labelled with the PLANNED parent (what a person recognises), with the
      // intermediate carried alongside.
      expect(deep.demandedBy, ['Top']);
      expect(deep.demands.single.via, 'Middle Sauce');
    });

    test('a cycle stops and flags instead of looping', () {
      final plan = buildCookPlan(
        [
          _recipe({0: 4}, id: 'a', title: 'A', servings: 4),
        ],
        components: {
          'a': (
            title: 'A',
            servingsBase: 4,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const [(qty: 1.0, unit: cup)],
            components: const [
              (
                id: 'li-b',
                subRecipeId: 'b',
                quantity: 1.0,
                unit: batches,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'b': (
            title: 'B',
            servingsBase: 4,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const [(qty: 1.0, unit: cup)],
            components: const [
              (
                id: 'li-a',
                subRecipeId: 'a',
                quantity: 1.0,
                unit: batches,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
        },
      );
      final gap = plan.gaps.single;
      expect(gap.recipeId, 'a');
      expect(gap.reason, const ComponentCycle());
      expect(gap.demandedBy.single.recipeId, 'a');
      // B still got its (one, non-looping) session.
      expect(
        plan.recipes
            .firstWhere((r) => r.recipeId == 'b')
            .sessions
            .single
            .batchesToCook,
        1,
      );
    });

    test('an unresolved yield is a named GAP, never a ×1 assumption', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'aioli': aioli(yields: const []),
        },
      );
      // No session at all for the aioli — nothing was invented to make one.
      expect(plan.recipes.any((r) => r.recipeId == 'aioli'), isFalse);
      final gap = plan.gaps.single;
      expect(gap.recipeId, 'aioli');
      expect(gap.title, 'Romesco Aioli');
      expect(gap.reason, const ComponentYieldMissing());
      expect(gap.demandedBy.single.title, 'Sausage Sliders');
      expect(gap.demandedBy.single.cookDay, 5);
      // Frame (f) quotes what the PAGE printed, so the source carries the
      // demanding line's own amount — unscaled, un-converted.
      expect(gap.demandedBy.single.quantity, 0.25);
      expect(gap.demandedBy.single.unit, cup);
      expect(plan.unresolvedComponentsByParent, {'sliders': 1});
    });

    test('the gap source quotes the printed amount, NOT the parent-scaled one '
        '— the scaling is exactly what cannot be done here', () {
      final plan = buildCookPlan(
        [
          // 16 sliders of a serves-8 recipe: the parent session is ×2.
          _recipe(
            {5: 16},
            id: 'sliders',
            title: 'Sausage Sliders',
            servings: 8,
          ),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'aioli': aioli(yields: const []),
        },
      );
      expect(plan.gaps.single.demandedBy.single.quantity, 0.25);
    });

    test('a numberless component line carries no amount to quote', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: {
          'sliders': sliders(
            components: const [
              (
                id: 'li-aioli',
                subRecipeId: 'aioli',
                quantity: null,
                unit: cup,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'aioli': aioli(),
        },
      );
      final source = plan.gaps.single.demandedBy.single;
      expect(plan.gaps.single.reason, const ComponentAmountMissing());
      expect(source.quantity, isNull);
      expect(source.unit, cup);
    });

    test('a family mismatch is its own gap, carrying both families', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: {
          'sliders': sliders(
            components: const [
              (
                id: 'li-aioli',
                subRecipeId: 'aioli',
                quantity: 2.0,
                unit: tbsp,
                recipeMeasureId: null,
                optional: false,
              ),
            ],
          ),
          'aioli': aioli(yields: const [(qty: 250.0, unit: g)]),
        },
      );
      expect(
        plan.gaps.single.reason,
        const ComponentFamilyMismatch(
          lineFamily: UnitFamily.volume,
          yieldFamilies: [UnitFamily.mass],
        ),
      );
    });

    test('one gap, two demanding parents — not two cards saying the same', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
          _recipe({6: 2}, id: 'toasts', title: 'Romesco Toasts'),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'toasts': (
            title: 'Romesco Toasts',
            servingsBase: 2,
            keepsForDays: null,
            freezable: false,
            freezerDays: null,
            measures: const <RecipeMeasure>[],
            yields: const <YieldDenomination>[],
            components: const [quarterCup],
          ),
          'aioli': aioli(yields: const []),
        },
      );
      expect(plan.gaps, hasLength(1));
      expect(plan.gaps.single.demandedBy.map((s) => s.title), [
        'Sausage Sliders',
        'Romesco Toasts',
      ]);
      // Each source carries its OWN line's printed amount.
      expect(plan.gaps.single.demandedBy.map((s) => (s.quantity, s.unit)), [
        (0.25, cup),
        (0.25, cup),
      ]);
      expect(plan.unresolvedComponentsByParent, {'sliders': 1, 'toasts': 1});
    });

    test('a dangling link derives nothing AND flags nothing', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
        },
      );
      expect(plan.gaps, isEmpty);
      expect(plan.recipes, hasLength(1));
    });

    test('a sub-recipe that is ALSO planned keeps both session flavours on one '
        'card, never summed into one number', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
          _recipe({5: 4}, id: 'aioli', title: 'Romesco Aioli', servings: 4),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'aioli': aioli(),
        },
      );
      final card = plan.recipes.firstWhere((r) => r.recipeId == 'aioli');
      expect(card.mealSessions, hasLength(1));
      expect(card.componentSessions, hasLength(1));
      expect(card.mealSessions.single.scaleFactor, 1);
      expect(card.componentSessions.single.scaleFactor, closeTo(0.25, 1e-12));
      // Portions stay the meal sessions' denomination alone.
      expect(card.totalPortions, 4);
    });

    test('passing no component graph derives exactly what it always did', () {
      final plan = buildCookPlan([
        _recipe({0: 4, 2: 4}, keeps: 3),
      ]);
      expect(plan.recipes.single.sessions.single.covers, hasLength(2));
      expect(plan.gaps, isEmpty);
    });

    test('a component session gets no whole-batch nudge — its scale is already '
        'in batches', () {
      final plan = buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: {
          'sliders': sliders(components: const [quarterCup]),
          'aioli': aioli(),
        },
      );
      final session = plan.recipes
          .firstWhere((r) => r.recipeId == 'aioli')
          .sessions
          .single;
      expect(wholeBatchNudgeFor(session), isNull);
    });

    group('the week filters the graph before a demand is derived', () {
      const optionalCup = (
        id: 'li-aioli',
        subRecipeId: 'aioli',
        quantity: 0.25,
        unit: cup,
        recipeMeasureId: null,
        optional: true,
      );

      CookPlan planWith(
        List<ComponentLine> components, [
        Map<String, List<LineOverride>> overrides = const {},
      ]) => buildCookPlan(
        [
          _recipe({5: 8}, id: 'sliders', title: 'Sausage Sliders', servings: 8),
        ],
        components: componentGraphForWeek({
          'sliders': sliders(components: components),
          'aioli': aioli(),
        }, overrides),
      );

      List<CookSession> aioliSessions(CookPlan plan) => [
        for (final r in plan.recipes)
          if (r.recipeId == 'aioli') ...r.sessions,
      ];

      test('an optional component with no include row is not cooked', () {
        final plan = planWith(const [optionalCup]);
        expect(aioliSessions(plan), isEmpty);
        expect(plan.gaps, isEmpty);
      });

      test("the week's include row is what opens the session", () {
        final plan = planWith(
          const [optionalCup],
          const {
            'sliders': [
              LineOverride(
                action: LineOverrideAction.include,
                recipeLineItemId: 'li-aioli',
              ),
            ],
          },
        );
        expect(aioliSessions(plan).single.batchesToCook, closeTo(0.25, 1e-12));
      });

      test('a component line the week EXCLUDES is not cooked either', () {
        final plan = planWith(
          const [quarterCup],
          const {
            'sliders': [
              LineOverride(
                action: LineOverrideAction.exclude,
                recipeLineItemId: 'li-aioli',
              ),
            ],
          },
        );
        expect(aioliSessions(plan), isEmpty);
      });

      test("a replace cooks the week's amount, not the recipe's", () {
        final plan = planWith(
          const [quarterCup],
          const {
            'sliders': [
              LineOverride(
                action: LineOverrideAction.replace,
                recipeLineItemId: 'li-aioli',
                subRecipeId: 'aioli',
                quantity: 0.5,
                unit: cup,
              ),
            ],
          },
        );
        expect(aioliSessions(plan).single.batchesToCook, closeTo(0.5, 1e-12));
      });

      test('a DERIVED sub-recipe is filtered too — its own optional component '
          'waits for an include', () {
        ComponentRecipe mid({required List<ComponentLine> components}) => (
          title: 'Romesco Base',
          servingsBase: 4,
          keepsForDays: 5,
          freezable: false,
          freezerDays: null,
          measures: const <RecipeMeasure>[],
          yields: const [(qty: 1.0, unit: cup)],
          components: components,
        );
        CookPlan planFor(Map<String, List<LineOverride>> overrides) =>
            buildCookPlan(
              [
                _recipe(
                  {5: 8},
                  id: 'sliders',
                  title: 'Sausage Sliders',
                  servings: 8,
                ),
              ],
              components: componentGraphForWeek({
                'sliders': sliders(
                  components: const [
                    (
                      id: 'li-mid',
                      subRecipeId: 'mid',
                      quantity: 1.0,
                      unit: batches,
                      recipeMeasureId: null,
                      optional: false,
                    ),
                  ],
                ),
                'mid': mid(components: const [optionalCup]),
                'aioli': aioli(),
              }, overrides),
            );

        expect(aioliSessions(planFor(const {})), isEmpty);
        expect(
          aioliSessions(
            planFor(const {
              'mid': [
                LineOverride(
                  action: LineOverrideAction.include,
                  recipeLineItemId: 'li-aioli',
                ),
              ],
            }),
          ),
          hasLength(1),
        );
      });

      test('a week with no variant at all leaves every line where it was', () {
        final graph = {
          'sliders': sliders(components: const [quarterCup]),
          'aioli': aioli(),
        };
        expect(componentGraphForWeek(graph, const {})['sliders']!.components, [
          quarterCup,
        ]);
      });
    });
  });
}
