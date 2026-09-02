import 'package:ansi/core/units/units.dart';
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
      final s = _session(cookDay: 0, keeps: 3, covers: [_meal(0, 'Dinner', 1)]);
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

  group('formatPortionsAmount', () {
    test('trims whole and fractional counts, with the right plural', () {
      expect(formatPortionsAmount(4), '4 portions');
      expect(formatPortionsAmount(1), '1 portion');
      expect(formatPortionsAmount(2.5), '2.5 portions');
      expect(formatPortionsAmount(0.5), '0.5 portions');
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
        'shopping still buys ×0.75',
      );
      expect(
        wholeBatchNudgeLine((
          factor: 2,
          batchPortions: 5.0,
          leftoverPortions: 0.5,
        ), rawFactor: 1.25),
        'cook ×2 instead — covers 5 portions · 0.5 portions left over · '
        'shopping still buys ×1.25',
      );
    });
  });

  test('a component session covers plans, not portions (step 8.6 / D3)', () {
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
    expect(coversLine(session), 'covers Sausage Sliders');
  });

  group('the component card (step 8.6 / D3, board frame f)', () {
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
      expect(componentScaleLabel(session), '×0.25 batch');
    });

    test('it is cooked BY the demanding day, not on one of its own', () {
      expect(componentWhenLabel(const [5]), 'Cook by Sat');
      expect(componentWhenLabel(const [5, 2, 5]), 'Cook by Wed + Sat');
    });

    test('the covers line closes with the batch arithmetic', () {
      expect(
        componentCoversLine(session, denomination: (qty: 1, unit: cup)),
        'covers Sausage Sliders · cook Sat — makes 1 cup, you need 0.25',
      );
    });

    test('with no yield to quote, the clause is dropped, not guessed', () {
      expect(componentCoversLine(session), 'covers Sausage Sliders · cook Sat');
    });

    test('a part-batch demand says what is left over, and what is not '
        'tracked', () {
      expect(
        componentLeftoverNote(session, denomination: (qty: 1, unit: cup)),
        'A batch makes 1 cup and Saturday needs 0.25 — the rest is yours. '
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
        componentLeftoverNote(whole, denomination: (qty: 1, unit: cup)),
        isNull,
      );
      expect(componentLeftoverNote(session), isNull);
    });
  });

  group('the gap card (step 8.6 / D3)', () {
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
        gapCoversLine(missing),
        'covers Sausage Sliders · cook Sat — the line asks for 0.25 cup',
      );
    });

    test('the quoted amount is the printed one, in the line’s own unit', () {
      expect(
        gapCoversLine(
          gap(const ComponentYieldMissing(), quantity: 8, unit: pieces),
        ),
        // A count prints bare, the way the recipe page says it.
        'covers Sausage Sliders · cook Sat — the line asks for 8',
      );
      expect(
        gapCoversLine(
          gap(const ComponentYieldMissing(), quantity: 2, unit: tbsp),
        ),
        'covers Sausage Sliders · cook Sat — the line asks for 2 tbsp',
      );
    });

    test('a numberless line drops the clause rather than filling it', () {
      expect(
        gapCoversLine(gap(const ComponentAmountMissing(), quantity: null)),
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
        gapCoversLine(shared),
        'covers Sausage Sliders + Romesco Toasts · cook Sat + Sun — '
        'Sausage Sliders asks for 0.25 cup · Romesco Toasts asks for 1 batch',
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
}
