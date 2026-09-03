/// P-D6, as a test: with every portion factor at its default of 1, the
/// fractional derivations (plan 0027 front P) give EXACTLY what the head-count
/// gave — the same demand, the same macro totals under every lens, the same
/// cook sessions, scale factors and nudges, and the same printed strings.
///
/// The fixtures are the shapes the week already ships: two eaters and no
/// override, one eater, an override above and below the head-count, an
/// override with nobody eating, an eater the roster no longer holds, a
/// recipe whose macros refuse, and a batch spanning days. Each is run twice —
/// through the factor-aware code with a roster of default members, and
/// through the same code with NO roster (where every eater counts 1 by the
/// documented fallback) — and the two runs must be byte-identical, with the
/// head-count `portionsOrDefault` as the third witness.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/portions.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/presentation/cook_format.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/week_macros.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';

const _roster = {
  'ada': Member(id: 'ada', displayName: 'Ada'),
  'jun': Member(id: 'jun', displayName: 'Jun'),
};

const _hundred = RecipeMacroSummary(
  perServing: Macros(kcal: 100, protein: 10, carb: 20, fat: 5),
);
const _stub = RecipeMacroSummary(stubLines: 1);

RecipeMacroSummary? _summaries(String id) => switch (id) {
  'curry' => _hundred,
  'sliders' => _stub,
  _ => null,
};

PlanEntry _entry(
  String id, {
  required int day,
  String recipeId = 'curry',
  String? title = 'Curry',
  List<String> eaters = const ['ada', 'jun'],
  int? portions,
}) => PlanEntry(
  id: id,
  dayOfWeek: day,
  mealSlot: 'Dinner',
  recipeId: recipeId,
  recipeTitle: title,
  eaterIds: eaters,
  portions: portions,
);

/// Today's week, every shape at once.
final _week = <PlanEntry>[
  _entry('a', day: 0),
  _entry('b', day: 1, eaters: ['jun']),
  _entry('c', day: 2, portions: 3),
  _entry('d', day: 2, portions: 1),
  _entry('e', day: 3, eaters: const [], portions: 2),
  _entry('f', day: 3, eaters: const []),
  _entry('g', day: 4, eaters: ['ada', 'gone']),
  _entry('h', day: 5, recipeId: 'sliders', title: 'Sliders'),
  _entry('i', day: 6, recipeId: 'gone', title: null),
  _entry('j', day: 2),
];

/// The week's curry meals as the cook plan sees them, demand derived by
/// [demandPortions] over [roster].
PlannedRecipe _curry(Map<String, Member> roster) => PlannedRecipe(
  recipeId: 'curry',
  title: 'Curry',
  servingsBase: 4,
  keepsForDays: 3,
  meals: [
    for (final e in _week)
      if (e.recipeId == 'curry')
        CoveredMeal(
          dayOfWeek: e.dayOfWeek,
          mealSlot: e.mealSlot,
          portions: demandPortions(e, roster),
        ),
  ],
);

void main() {
  test('demand: the factor-aware figure IS the head-count for every shape', () {
    for (final e in _week) {
      expect(demandPortions(e, _roster), e.portionsOrDefault, reason: e.id);
      expect(demandPortions(e, const {}), e.portionsOrDefault, reason: e.id);
    }
  });

  test('macros: every lens, every day and the week are byte-identical with '
      'and without the roster', () {
    for (final lens in [null, 'ada', 'jun']) {
      for (var day = -1; day < 7; day++) {
        final entries = day < 0
            ? _week
            : _week.where((e) => e.dayOfWeek == day).toList();
        final withRoster = sumPlannedMacros(
          entries,
          summaryFor: _summaries,
          lensMemberId: lens,
          membersById: _roster,
        );
        final without = sumPlannedMacros(
          entries,
          summaryFor: _summaries,
          lensMemberId: lens,
        );
        expect(
          withRoster.toString(),
          without.toString(),
          reason: 'lens $lens day $day',
        );
        expect(withRoster.excluded, without.excluded);
      }
    }
  });

  test('macros: the lens share under default factors is the even split it '
      'always was', () {
    // Entry c: an override of 3 between two eaters → 1.5 each; entry a: one
    // each. That is the figure the week showed before the factor existed.
    final jun = sumPlannedMacros(
      [_week[0], _week[2]],
      summaryFor: _summaries,
      lensMemberId: 'jun',
      membersById: _roster,
    );
    expect(jun.total!.kcal, 250);
    expect(jun.servings, 2.5);
    expect(jun.demand, 5);
  });

  test('cook plan: sessions, scale factors, nudges and their printed words '
      'are byte-identical with and without the roster', () {
    final withRoster = buildCookPlan([_curry(_roster)]);
    final without = buildCookPlan([_curry(const {})]);
    expect(withRoster, without);

    final plan = withRoster.recipes.single;
    // A whole-number demand prints as it always did — no glyph, no ".0".
    expect(recipeSummaryLine(plan), '13 portions across the week · keeps 3 d');
    for (final (i, session) in plan.sessions.indexed) {
      final twin = without.recipes.single.sessions[i];
      expect(session.totalPortions, twin.totalPortions);
      expect(session.scaleFactor, twin.scaleFactor);
      expect(coversLine(session), coversLine(twin));
      final nudge = wholeBatchNudgeFor(session);
      expect(nudge, wholeBatchNudgeFor(twin));
      if (nudge != null) {
        expect(
          wholeBatchNudgeLine(nudge, rawFactor: session.scaleFactor),
          wholeBatchNudgeLine(nudge, rawFactor: twin.scaleFactor),
        );
      }
      final marker = cookMarkerFor(
        withRoster,
        recipeId: 'curry',
        dayOfWeek: session.cookDay,
        mealSlot: 'Dinner',
      );
      if (marker != null) {
        expect(
          cookMarkerLabel(marker),
          'cooks ${kWeekdayShort[session.cookDay]} · '
          'batch of ${session.totalPortions.toInt()}',
        );
      }
    }
  });

  test('the printed count of a whole number has no fraction glyph and no '
      'decimal — today’s strings, exactly', () {
    for (final n in [0, 1, 2, 3, 4, 9]) {
      expect(formatFraction(n.toDouble()), '$n');
      expect(formatPortions(n.toDouble()), '$n portion${n == 1 ? '' : 's'}');
    }
  });
}
