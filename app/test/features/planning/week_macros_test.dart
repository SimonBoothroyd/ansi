/// D4, one rule at every scope: sum what resolved, state the denominator,
/// name every exclusion — and refuse rather than invent.
///
/// Mirrors `recipe_macros_test.dart`'s shape: one test per rule, and the
/// invariant-3 cases (nothing resolved, nothing in scope, nobody to divide by)
/// get their own.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/week_macros.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';

/// 100 kcal / 10 P / 20 C / 5 F per serving.
const _hundred = RecipeMacroSummary(
  perServing: Macros(kcal: 100, protein: 10, carb: 20, fat: 5),
);

/// A recipe whose own summary refuses — one stub line.
const _stub = RecipeMacroSummary(stubLines: 1);

PlanEntry _entry({
  required String id,
  String recipeId = 'ok',
  String? title = 'Curry',
  int day = 0,
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

RecipeMacroSummary? _summaries(String id) => switch (id) {
  'ok' => _hundred,
  'stub' => _stub,
  _ => null,
};

MealSetMacros _sum(List<PlanEntry> entries, {String? lens}) =>
    sumPlannedMacros(entries, summaryFor: _summaries, lensMemberId: lens);

/// A snack meal: a bare ingredient with a stated amount (step 8.14). The vocab
/// row's numbers ride on the entry, exactly as `recipeTitle` does.
PlanEntry _snack({
  required String id,
  String? name = 'Protein bar',
  double? quantity = 60,
  Unit? unit = g,
  Measure? measure,
  String? measureId,
  Macros? macros = const Macros(kcal: 350, protein: 33, carb: 30, fat: 11),
  MacrosBasis basis = MacrosBasis.perG,
  double? density,
  double? pieceBasisAmount,
  bool knownRow = true,
  int day = 0,
  List<String> eaters = const ['ada', 'jun'],
  int? portions,
}) => PlanEntry(
  id: id,
  dayOfWeek: day,
  mealSlot: 'Snack',
  ingredientId: 'i1',
  ingredientName: name,
  quantity: quantity,
  unit: unit,
  measureId: measureId ?? measure?.id,
  measure: measure,
  nutrition: knownRow
      ? (
          macros: macros,
          basis: basis,
          densityGPerMl: density,
          pieceBasisAmount: pieceBasisAmount,
        )
      : null,
  eaterIds: eaters,
  portions: portions,
);

void main() {
  test('every meal complete: the total is whole and nothing is excluded', () {
    final macros = _sum([_entry(id: 'a'), _entry(id: 'b', day: 1)]);
    // Two meals × two eaters × 100 kcal/serving.
    expect(macros.total!.kcal, 400);
    expect(macros.counted, 2);
    expect(macros.considered, 2);
    expect(macros.excluded, isEmpty);
    expect(macros.isPartial, isFalse);
    expect(macros.daysContributing, 2);
  });

  test('one incomplete meal: the rest still sums, and the excluded meal '
      'carries its own summary so the UI prints incompleteNote', () {
    final macros = _sum([
      _entry(id: 'a'),
      _entry(id: 'b', recipeId: 'stub', title: 'Sausage Sliders'),
    ]);
    expect(macros.total!.kcal, 200);
    expect(macros.counted, 1);
    expect(macros.considered, 2); // the denominator the label must state
    expect(macros.isPartial, isTrue);
    final left = macros.excluded.single;
    expect(left.label, 'Sausage Sliders');
    expect(left.reason, MealExclusion.incomplete);
    // The reason WORDS are not invented here — the summary rides along.
    expect(left.summary, _stub);
  });

  test('nothing resolves: no total at all, and every reason is named', () {
    final macros = _sum([
      _entry(id: 'a', recipeId: 'stub', title: 'Sausage Sliders'),
      _entry(id: 'b', recipeId: 'stub', title: 'Pancakes'),
    ]);
    expect(macros.total, isNull, reason: 'never a partial standing in');
    expect(macros.isRefused, isTrue);
    expect(macros.isEmpty, isFalse);
    expect(macros.excluded.map((e) => e.label), [
      'Sausage Sliders',
      'Pancakes',
    ]);
  });

  test('no meals at all is a THIRD state — never 0 kcal', () {
    final macros = _sum(const []);
    expect(macros.isEmpty, isTrue);
    expect(macros.isRefused, isFalse);
    expect(macros.total, isNull);
    expect(macros.considered, 0);
  });

  test('a lens under which this person eats nothing is empty, not refused and '
      'not zero', () {
    final macros = _sum([
      _entry(id: 'a', eaters: ['jun']),
    ], lens: 'ada');
    expect(macros.isEmpty, isTrue);
    expect(macros.total, isNull);
    // Jun's meal was never Ada's to count, so it is not an "exclusion" either.
    expect(macros.excluded, isEmpty);
  });

  test('a person gets an even split; a portions override IS eating more', () {
    final entries = [_entry(id: 'a', portions: 3)];
    // Everyone: the household figure, 3 servings.
    expect(_sum(entries).total!.kcal, 300);
    // Ada: 3 portions between 2 eaters is 1.5 each — the only figure `eaters`
    // + `portions` can honestly state.
    expect(_sum(entries, lens: 'ada').total!.kcal, 150);
  });

  test('an entry with no eaters is excluded, never divided by zero', () {
    final macros = _sum([_entry(id: 'a', eaters: const [])], lens: 'ada');
    expect(macros.considered, 1, reason: 'it might be theirs — still in scope');
    expect(macros.total, isNull);
    expect(macros.excluded.single.reason, MealExclusion.noEaters);
  });

  test('an entry with no eaters and no override has no demand under Everyone '
      'either', () {
    final macros = _sum([_entry(id: 'a', eaters: const [])]);
    expect(macros.total, isNull);
    expect(macros.excluded.single.reason, MealExclusion.noEaters);
    // …but an explicit override is a real demand, eaters or not.
    final withOverride = _sum([_entry(id: 'a', eaters: const [], portions: 2)]);
    expect(withOverride.total!.kcal, 200);
  });

  test('a deleted recipe is excluded, never counted as zero', () {
    final macros = _sum([
      _entry(id: 'a'),
      _entry(id: 'b', title: null, recipeId: 'gone'),
    ]);
    expect(macros.total!.kcal, 200);
    expect(macros.excluded.single.reason, MealExclusion.recipeMissing);
    expect(macros.excluded.single.label, '(deleted recipe)');
  });

  test('the week is the same function over a wider set, never a sum of rounded '
      'days', () {
    final week = [
      _entry(id: 'a'),
      _entry(id: 'b', day: 1, portions: 3),
      _entry(id: 'c', day: 1),
    ];
    final whole = _sum(week);
    var byDay = 0.0;
    for (var d = 0; d < 7; d++) {
      final day = _sum(week.where((e) => e.dayOfWeek == d).toList());
      byDay += day.total?.kcal ?? 0;
    }
    expect(whole.total!.kcal, byDay);
  });

  test('daysContributing counts only the days that put something in', () {
    final macros = _sum([
      _entry(id: 'a'),
      _entry(id: 'b', day: 1, recipeId: 'stub', title: 'Sliders'),
      _entry(id: 'c', day: 2),
      _entry(id: 'd', day: 2),
    ]);
    // Monday and Wednesday counted; Tuesday's only meal was excluded.
    expect(macros.daysContributing, 2);
    expect(macros.counted, 3);
    expect(macros.considered, 4);
  });

  test('the per-day average divides by the days that counted, not by 7', () {
    final macros = _sum([_entry(id: 'a'), _entry(id: 'b', day: 3)]);
    expect(macros.total!.kcal, 400);
    expect(macros.daysContributing, 2);
    expect(macros.perDayAverage!.kcal, 200);
  });

  test('there is no average without a total', () {
    expect(_sum(const []).perDayAverage, isNull);
    expect(_sum([_entry(id: 'a', recipeId: 'stub')]).perDayAverage, isNull);
  });

  test('an empty roster falls back to one portion per eater — the documented '
      'default a device with no members synced yet still has to answer', () {
    for (final entry in [
      _entry(id: 'a'),
      _entry(id: 'b', eaters: const ['ada']),
      _entry(id: 'c', portions: 3),
      _entry(id: 'd', eaters: const []),
    ]) {
      expect(
        demandPortions(entry, const {}),
        entry.portionsOrDefault,
        reason: entry.id,
      );
    }
  });

  group('the portion factor', () {
    // Ada eats a portion, Jun three-quarters of one.
    const roster = {
      'ada': Member(id: 'ada', displayName: 'Ada'),
      'jun': Member(id: 'jun', displayName: 'Jun', portionFactor: 0.75),
    };
    MealSetMacros sum(List<PlanEntry> entries, {String? lens}) =>
        sumPlannedMacros(
          entries,
          summaryFor: _summaries,
          lensMemberId: lens,
          membersById: roster,
        );

    test('Everyone sums the fractional demand — 1¾ servings, not 2', () {
      final macros = sum([_entry(id: 'a')]);
      expect(macros.total!.kcal, 175);
      expect(macros.servings, 1.75);
      expect(macros.demand, 1.75);
    });

    test(
      'a person’s lens weights by their factor and names the denominator',
      () {
        final jun = sum([_entry(id: 'a')], lens: 'jun');
        expect(jun.total!.kcal, 75);
        expect(jun.servings, 0.75);
        expect(jun.demand, 1.75);
        expect(
          portionShareLine(jun, lensName: 'Jun'),
          'Jun · ¾ of 1¾ portions',
        );
        final ada = sum([_entry(id: 'a')], lens: 'ada');
        expect(ada.total!.kcal, 100);
        expect(
          portionShareLine(ada, lensName: 'Ada'),
          'Ada · 1 of 1¾ portions',
        );
      },
    );

    test('an override is shared out in the same proportions — 3 × ¾ ⁄ 1¾', () {
      final entries = [_entry(id: 'a', portions: 3)];
      expect(sum(entries).total!.kcal, 300);
      final jun = sum(entries, lens: 'jun');
      expect(jun.total!.kcal, closeTo(3 * 0.75 / 1.75 * 100, 1e-9));
      expect(
        portionShareLine(jun, lensName: 'Jun'),
        'Jun · 1.29 of 3 portions',
      );
      final ada = sum(entries, lens: 'ada');
      expect(ada.total!.kcal, closeTo(3 / 1.75 * 100, 1e-9));
    });

    test('an override with no eaters stays unattributable under a lens', () {
      final macros = sum([
        _entry(id: 'a', eaters: const [], portions: 3),
      ], lens: 'jun');
      expect(macros.total, isNull);
      expect(macros.excluded.single.reason, MealExclusion.noEaters);
      expect(portionShareLine(macros, lensName: 'Jun'), isNull);
    });

    test('Everyone has no share line — the whole needs no second number', () {
      expect(portionShareLine(sum([_entry(id: 'a')]), lensName: null), isNull);
    });

    test(
      'the share line sums across meals, so a day reads as one fraction',
      () {
        final jun = sum([_entry(id: 'a'), _entry(id: 'b')], lens: 'jun');
        expect(
          portionShareLine(jun, lensName: 'Jun'),
          'Jun · 1½ of 3½ portions',
        );
      },
    );
  });

  // --- A slot takes an ingredient (step 8.14) --------------------------------

  group('a bare INGREDIENT meal', () {
    test('counts, and multiplies by its eaters like any other entry', () {
      // 60 g of a 350 kcal/100 g bar is 210 kcal per PORTION; two eaters each
      // have one (A-D3 — a snack is shared, so it multiplies).
      final macros = _sum([_snack(id: 'a')]);
      expect(macros.total!.kcal, closeTo(420, 1e-9));
      expect(macros.total!.protein, closeTo(39.6, 1e-9));
      expect(macros.counted, 1);
      expect(macros.excluded, isEmpty);
      expect(macros.demand, 2);
    });

    test('a measure-quantified amount is priced through its stored weight', () {
      const bar = Measure(id: 'm1', label: 'bar', amount: 60);
      final macros = _sum([
        _snack(id: 'a', quantity: 1, unit: pieces, measure: bar),
      ]);
      expect(macros.total!.kcal, closeTo(420, 1e-9));
    });

    test('it sums BESIDE recipes — one week, one total', () {
      final macros = _sum([_entry(id: 'a'), _snack(id: 'b', day: 1)]);
      expect(macros.total!.kcal, closeTo(200 + 420, 1e-9));
      expect(macros.counted, 2);
      expect(macros.considered, 2);
      expect(macros.daysContributing, 2);
    });

    test('a STUB row contributes nothing, in a stub LINE’s own words', () {
      final macros = _sum([_snack(id: 'a', macros: null)]);
      expect(macros.total, isNull);
      expect(macros.isRefused, isTrue);
      final left = macros.excluded.single;
      expect(left.label, 'Protein bar');
      expect(left.reason, MealExclusion.ingredientNotCounted);
      expect(left.lineReason, MacroLineReason.stubIngredient);
    });

    test('a row this device has never synced is named apart from a stub', () {
      final left = _sum([
        _snack(id: 'a', name: null, knownRow: false),
      ]).excluded.single;
      expect(left.label, '(deleted ingredient)');
      expect(left.lineReason, MacroLineReason.unknownIngredient);
    });

    test('no amount is a refusal with its own reason, never a zero', () {
      final left = _sum([
        _snack(id: 'a', quantity: null, unit: null),
      ]).excluded.single;
      expect(left.lineReason, MacroLineReason.noAmount);
    });

    test('a bare count with nothing weighing it asks for a weight', () {
      final left = _sum([
        _snack(id: 'a', quantity: 1, unit: pieces),
      ]).excluded.single;
      expect(left.lineReason, MacroLineReason.needsWeight);
    });

    test('a cross-basis amount without a density asks for one', () {
      final left = _sum([
        _snack(id: 'a', quantity: 200, unit: ml),
      ]).excluded.single;
      expect(left.lineReason, MacroLineReason.needsDensity);
    });

    test('a cross-basis amount WITH a density resolves', () {
      final macros = _sum([
        _snack(
          id: 'a',
          quantity: 200,
          unit: ml,
          density: 1.03,
          eaters: ['ada'],
        ),
      ]);
      expect(macros.total!.kcal, closeTo(350 * 2.06, 1e-6));
    });

    test('an unresolved measure waits rather than degrading to a count', () {
      final left = _sum([
        _snack(id: 'a', quantity: 1, unit: pieces, measureId: 'gone'),
      ]).excluded.single;
      expect(left.lineReason, MacroLineReason.needsWeight);
    });

    test('a snack nobody is eating is excluded for that, not for its row', () {
      final left = _sum([_snack(id: 'a', eaters: const [])]).excluded.single;
      expect(left.reason, MealExclusion.noEaters);
    });
  });

  // --- ADR-0015: the piece weight, at the plan's scale -----------------------
  // The same row fact the recipe summation converts a bare `piece` line
  // through. A snack states an amount, so `2 piece` of a weighed row is a
  // weight — and of an unweighed one it is still a question.

  group('a bare count snack, and the row that weighs it', () {
    test('2 piece on a weighed row weighs, and multiplies by its eaters', () {
      final macros = _sum([
        _snack(id: 'a', quantity: 2, unit: pieces, pieceBasisAmount: 110),
      ]);
      // 2 × 110 g = 220 g → 770 kcal per PORTION, and two eaters have one each.
      expect(macros.total!.kcal, closeTo(1540, 1e-6));
      expect(macros.counted, 1);
      expect(macros.excluded, isEmpty);
    });

    test('the weight is stated in the row basis — a per-100 ml row counts in '
        'millilitres, with no density', () {
      final macros = _sum([
        _snack(
          id: 'a',
          quantity: 2,
          unit: pieces,
          basis: MacrosBasis.perMl,
          pieceBasisAmount: 25,
          eaters: ['ada'],
        ),
      ]);
      // 2 × 25 ml = 50 ml → half the per-100 ml macros, for one eater.
      expect(macros.total!.kcal, closeTo(175, 1e-9));
    });

    test('with no weight the same snack is still needsWeight — the fix is one '
        'number on the ingredient, not a different amount', () {
      final left = _sum([
        _snack(id: 'a', quantity: 2, unit: pieces),
      ]).excluded.single;
      expect(left.reason, MealExclusion.ingredientNotCounted);
      expect(left.lineReason, MacroLineReason.needsWeight);
    });

    test('an unresolved measure still waits: the entry claimed a bar, not a '
        'piece, whatever one of the row weighs', () {
      final left = _sum([
        _snack(
          id: 'a',
          quantity: 1,
          unit: pieces,
          measureId: 'gone',
          pieceBasisAmount: 110,
        ),
      ]).excluded.single;
      expect(left.lineReason, MacroLineReason.needsWeight);
    });

    test('a RESOLVED measure still wins over the piece weight', () {
      const bar = Measure(id: 'm1', label: 'bar', amount: 60);
      final macros = _sum([
        _snack(
          id: 'a',
          quantity: 1,
          unit: pieces,
          measure: bar,
          pieceBasisAmount: 110,
        ),
      ]);
      expect(macros.total!.kcal, closeTo(420, 1e-9));
    });

    test('a stub row is a stub however much one of it weighs', () {
      final left = _sum([
        _snack(
          id: 'a',
          quantity: 2,
          unit: pieces,
          macros: null,
          pieceBasisAmount: 110,
        ),
      ]).excluded.single;
      expect(left.lineReason, MacroLineReason.stubIngredient);
    });
  });
}
