import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/presentation/cook_format.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:flutter_test/flutter_test.dart';

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

CoveredMeal _meal(int day, String slot, double portions) =>
    CoveredMeal(dayOfWeek: day, mealSlot: slot, portions: portions);

void main() {
  group('formatScale', () {
    test('trims trailing zeros', () {
      expect(formatScale(1), '×1');
      expect(formatScale(1.5), '×1½');
      expect(formatScale(0.75), '×¾');
      expect(formatScale(2), '×2');
    });
  });

  group('coversLine', () {
    test('a single portion reads singular', () {
      final s = _session(cookDay: 0, keeps: 3, covers: [_meal(0, 'Dinner', 1)]);
      expect(coversLine(s, WeekShape.monday), 'covers Mon dinner · 1 portion');
    });

    test('collapses a shared slot to one label', () {
      final s = _session(
        cookDay: 1,
        keeps: 6,
        covers: [_meal(1, 'Dinner', 2), _meal(5, 'Dinner', 2)],
      );
      expect(
        coversLine(s, WeekShape.monday),
        'covers Tue + Sat dinner · 4 portions',
      );
    });

    test('spells out mixed slots', () {
      final s = _session(
        cookDay: 0,
        keeps: 6,
        covers: [_meal(0, 'Dinner', 2), _meal(3, 'Lunch', 1)],
      );
      expect(
        coversLine(s, WeekShape.monday),
        'covers Mon dinner + Thu lunch · 3 portions',
      );
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
        freezerNoteFor('Ragù', s, WeekShape.monday),
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

  group('cookTrackDays', () {
    test('the cook day takes the tick, the band runs the window, and an eaten '
        'day inside it is a plain dot', () {
      // Cook Tue(1), keeps 3 → the band runs Tue→Fri; Thu is eaten inside it.
      final s = _session(
        cookDay: 1,
        keeps: 3,
        covers: [_meal(1, 'Dinner', 2), _meal(3, 'Dinner', 2)],
      );
      final days = cookTrackDays([(s, '×2')]);
      expect(days[1].cookScale, '×2');
      expect(days[1].dot, CookTrackDot.none);
      expect(
        [for (final d in days) d.keeps],
        [false, true, true, true, true, false, false],
      );
      expect(days[3].dot, CookTrackDot.eaten);
    });

    test('a day past the keep window is the amber one', () {
      // Cook Tue(1), keeps 3, Saturday from the freezer.
      final s = _session(
        cookDay: 1,
        keeps: 3,
        freezable: true,
        covers: [_meal(1, 'Dinner', 2), _meal(5, 'Dinner', 2)],
      );
      final days = cookTrackDays([(s, '×2')]);
      expect(days[5].dot, CookTrackDot.pastWindow);
      expect(days[5].keeps, isFalse);
      expect(days[4].keeps, isTrue);
    });

    test('unknown shelf life marks nothing past a window it does not have', () {
      final s = _session(
        cookDay: 0,
        covers: [_meal(0, 'Dinner', 2), _meal(6, 'Dinner', 2)],
      );
      final days = cookTrackDays([(s, '×2')]);
      expect(days[6].dot, CookTrackDot.eaten);
      expect([for (final d in days) d.keeps], everyElement(isTrue));
    });

    test('two sessions of one recipe fill one track, each its own tick', () {
      final first = _session(cookDay: 0, keeps: 1, covers: [_meal(0, 'D', 2)]);
      final second = _session(cookDay: 5, keeps: 1, covers: [_meal(5, 'D', 2)]);
      final days = cookTrackDays([(first, '×1'), (second, '×1')]);
      expect(
        [for (final d in days) d.cookScale],
        ['×1', null, null, null, null, '×1', null],
      );
      expect(
        [for (final d in days) d.keeps],
        [true, true, false, false, false, true, true],
      );
    });
  });

  group('wholeBatchNudgeLine', () {
    test('spells out the whole-batch advice with honest leftovers', () {
      // The closing clause is honest about the accepted gap (tracker row):
      // the shopping list keeps scaling by the raw factor, nudge or not.
      expect(
        wholeBatchNudgeLine((
          factor: 1,
          batchPortions: 4,
          leftoverPortions: 1,
        ), rawFactor: 0.75),
        'cook ×1 instead — covers 4 portions · 1 portion left over · '
        'shopping still buys ×¾',
      );
      expect(
        wholeBatchNudgeLine((
          factor: 2,
          batchPortions: 5.0,
          leftoverPortions: 0.5,
        ), rawFactor: 1.25),
        'cook ×2 instead — covers 5 portions · ½ portion left over · '
        'shopping still buys ×1¼',
      );
    });

    test('a fractional demand leaves a fractional, glyph-printed leftover', () {
      // 1¾ portions of a serves-4 recipe: ×0.44 → cook ×1, 2¼ left over.
      final nudge = wholeBatchNudgeFor(
        _session(cookDay: 0, covers: [_meal(0, 'Dinner', 1.75)], servings: 4),
      );
      expect(
        wholeBatchNudgeLine(nudge!, rawFactor: 0.4375),
        'cook ×1 instead — covers 4 portions · 2¼ portions left over · '
        'shopping still buys ×0.44',
      );
    });
  });

  test('a component session covers plans, not portions', () {
    const session = CookSession(
      recipeId: 'aioli',
      recipeTitle: 'Romesco Aioli',
      servingsBase: 4,
      cookDay: 5,
      demands: [
        ComponentDemand(
          parentRecipeId: 'sliders',
          parentTitle: 'Sausage Sliders',
          cookDay: 5,
          batches: 0.25,
        ),
      ],
    );
    expect(coversLine(session, WeekShape.monday), 'covers Sausage Sliders');
  });

  group('the component card', () {
    const session = CookSession(
      recipeId: 'aioli',
      recipeTitle: 'Romesco Aioli',
      servingsBase: 4,
      cookDay: 5,
      keepsForDays: 5,
      demands: [
        ComponentDemand(
          parentRecipeId: 'sliders',
          parentTitle: 'Sausage Sliders',
          cookDay: 5,
          batches: 0.25,
        ),
      ],
    );

    test('the title names the plans it answers', () {
      expect(
        componentCardTitle('Romesco Aioli', const ['Sausage Sliders']),
        'Romesco Aioli · for Sausage Sliders',
      );
    });

    test('the scale is in batches, never portions', () {
      expect(componentScaleLabel(session), '×¼ batch');
    });

    test('it is cooked BY the demanding day, not on one of its own', () {
      expect(componentWhenLabel(const [5], WeekShape.monday), 'Cook by Sat');
      expect(
        componentWhenLabel(const [5, 2, 5], WeekShape.monday),
        'Cook by Wed + Sat',
      );
    });

    test('the covers line closes with the batch arithmetic', () {
      expect(
        componentCoversLine(
          session,
          WeekShape.monday,
          denomination: (qty: 1, unit: cup),
        ),
        'covers Sausage Sliders · cook Sat — makes 1 cup, you need ¼',
      );
    });

    test('with no yield to quote, the clause is dropped, not guessed', () {
      expect(
        componentCoversLine(session, WeekShape.monday),
        'covers Sausage Sliders · cook Sat',
      );
    });

    test('a part-batch demand says what is left over, and what is not '
        'tracked', () {
      expect(
        componentLeftoverNote(
          session,
          WeekShape.monday,
          denomination: (qty: 1, unit: cup),
        ),
        'A batch makes 1 cup and Saturday needs ¼ — the rest is yours. '
        'Nothing here tracks the leftover.',
      );
    });

    test('a whole-batch demand leaves nothing over, so it says nothing', () {
      const whole = CookSession(
        recipeId: 'aioli',
        recipeTitle: 'Romesco Aioli',
        servingsBase: 4,
        cookDay: 5,
        demands: [
          ComponentDemand(
            parentRecipeId: 'sliders',
            parentTitle: 'Sausage Sliders',
            cookDay: 5,
            batches: 2,
          ),
        ],
      );
      expect(
        componentLeftoverNote(
          whole,
          WeekShape.monday,
          denomination: (qty: 1, unit: cup),
        ),
        isNull,
      );
      expect(componentLeftoverNote(session, WeekShape.monday), isNull);
    });

    test('a demand said in the recipe’s own word shows its work', () {
      // The card's reader is holding the parent recipe and looking for the word
      // they wrote in it, so the line reads in that order — and the middle
      // step, what a blob IS, is printed rather than elided.
      const said = CookSession(
        recipeId: 'aioli',
        recipeTitle: 'Romesco Aioli',
        servingsBase: 4,
        cookDay: 5,
        demands: [
          ComponentDemand(
            parentRecipeId: 'sliders',
            parentTitle: 'Sausage Sliders',
            cookDay: 5,
            batches: 0.15,
            quantity: 3,
            measure: RecipeMeasure(
              id: 'm-blob',
              recipeId: 'aioli',
              label: 'blob',
              amount: 15,
              unit: g,
            ),
          ),
        ],
      );
      expect(SessionSpeech.of(said, WeekShape.monday).words, [
        '3 blob → 45 g → 0.15 of a batch',
      ]);
    });

    test('a demand said in a catalog unit adds no such line — the card’s own '
        'scale already says the whole of it', () {
      expect(SessionSpeech.of(session, WeekShape.monday).words, isEmpty);
    });
  });

  group('the gap card', () {
    ComponentGap gap(
      UnresolvedComponentAmount reason, {
      double? quantity = 0.25,
      Unit unit = cup,
    }) => ComponentGap(
      recipeId: 'aioli',
      title: 'Romesco Aioli',
      reason: reason,
      demandedBy: [
        ComponentDemandSource(
          recipeId: 'sliders',
          title: 'Sausage Sliders',
          cookDay: 5,
          quantity: quantity,
          unit: unit,
        ),
      ],
    );

    test('a missing yield is named, and offers the one-tap fix', () {
      final missing = gap(const ComponentYieldMissing());
      expect(
        gapSummaryLine(missing),
        'derived from a component line · yield not set',
      );
      expect(
        gapHeadline(missing),
        'Romesco Aioli doesn’t say how much it makes',
      );
      expect(gapBody(missing), startsWith('Set its yield'));
      expect(gapOffersYieldFix(missing), isTrue);
      // Frame (f) verbatim: the one number a gap CAN state is what the line
      // printed.
      expect(
        gapCoversLine(missing, WeekShape.monday),
        'covers Sausage Sliders · cook Sat — the line asks for ¼ cup',
      );
    });

    test('the quoted amount is the printed one, in the line’s own unit', () {
      expect(
        gapCoversLine(
          gap(const ComponentYieldMissing(), quantity: 8, unit: pieces),
          WeekShape.monday,
        ),
        // A count prints bare, the way the recipe page says it.
        'covers Sausage Sliders · cook Sat — the line asks for 8',
      );
      expect(
        gapCoversLine(
          gap(const ComponentYieldMissing(), quantity: 2, unit: tbsp),
          WeekShape.monday,
        ),
        'covers Sausage Sliders · cook Sat — the line asks for 2 tbsp',
      );
    });

    test('a numberless line drops the clause rather than filling it', () {
      expect(
        gapCoversLine(
          gap(const ComponentAmountMissing(), quantity: null),
          WeekShape.monday,
        ),
        'covers Sausage Sliders · cook Sat',
      );
    });

    test('two demanding parents each name their own ask — "the line" would be '
        'ambiguous', () {
      const shared = ComponentGap(
        recipeId: 'aioli',
        title: 'Romesco Aioli',
        reason: ComponentYieldMissing(),
        demandedBy: [
          ComponentDemandSource(
            recipeId: 'sliders',
            title: 'Sausage Sliders',
            cookDay: 5,
            quantity: 0.25,
            unit: cup,
          ),
          ComponentDemandSource(
            recipeId: 'toasts',
            title: 'Romesco Toasts',
            cookDay: 6,
            quantity: 1,
            unit: batches,
          ),
        ],
      );
      expect(
        gapCoversLine(shared, WeekShape.monday),
        'covers Sausage Sliders + Romesco Toasts · cook Sat + Sun — '
        'Sausage Sliders asks for ¼ cup · Romesco Toasts asks for 1 batch',
      );
    });

    test('a family mismatch names both sides and the fix that closes it', () {
      final mismatch = gap(
        const ComponentFamilyMismatch(
          lineFamily: UnitFamily.volume,
          yieldFamilies: [UnitFamily.mass],
        ),
      );
      expect(gapBody(mismatch), contains('The line is in volume'));
      expect(gapBody(mismatch), contains('the yield only says weight'));
      expect(gapBody(mismatch), contains('second denomination'));
      expect(gapOffersYieldFix(mismatch), isTrue);
    });

    test('an amount or a cycle is fixed on the parent, so no yield button', () {
      expect(gapOffersYieldFix(gap(const ComponentAmountMissing())), isFalse);
      expect(gapOffersYieldFix(gap(const ComponentCycle())), isFalse);
      expect(
        gapHeadline(gap(const ComponentCycle())),
        'Romesco Aioli is used inside itself',
      );
    });

    test('no gap copy ever offers a scale', () {
      for (final reason in const <UnresolvedComponentAmount>[
        ComponentAmountMissing(),
        ComponentYieldMissing(),
        ComponentCycle(),
      ]) {
        expect(gapBody(gap(reason)), isNot(contains('×')));
        expect(gapHeadline(gap(reason)), isNot(contains('×')));
      }
    });
  });

  group("formatCookCount (the Cook tab's menu row, in its own words)", () {
    test('counts cook sessions, never meals', () {
      expect(formatCookCount(0), 'nothing to cook');
      expect(formatCookCount(1), '1 cook');
      expect(formatCookCount(2), '2 cooks');
    });
  });
}
