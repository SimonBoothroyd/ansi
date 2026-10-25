/// What Ansi's `nutrition`, `cost` and `prices` tools answer: the figures the
/// recipe panel, the Week band and the Shop already print, written by their
/// own formatters, so an answer can never disagree with a screen. Pure Dart.
///
/// **Honest numbers.** A summary with no figure answers with the reason the
/// panel gives; a total that left meals or lines out names them; a cost with
/// a gap reads `at least`. Macros and money are written by separate functions
/// and never share a result (`cost_and_macros_stay_apart_test.dart`).
library;

import 'dart:convert';

import '../../../core/money.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/number_format.dart';
import '../../../core/words.dart';
import '../../../shared/cost_words.dart';
import '../../../shared/incomplete_macros.dart';
import '../../ingredients/domain/cost_price.dart';
import '../../ingredients/domain/price.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../../planning/domain/week_cost.dart';
import '../../planning/domain/week_macros.dart';
import '../../planning/presentation/week_macro_widgets.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../shopping/domain/shopping_cost.dart';

/// `{kcal: "285 kcal", protein: "21 g", …}`, fibre only when stated.
Map<String, String> _macros(Macros m) => {
  'kcal': '${formatKcal(m.kcal)} kcal',
  'protein': '${formatGrams(m.protein)} g',
  'carbs': '${formatGrams(m.carb)} g',
  'fat': '${formatGrams(m.fat)} g',
  if (m.fiber != null) 'fibre': '${formatGrams(m.fiber!)} g',
};

/// `nutrition` for one recipe: per serving, and for [servings] when asked.
String recipeNutritionResult(
  String title,
  RecipeMacroSummary summary, {
  double? servings,
  String? basis,
}) {
  final per = summary.perServing;
  final byRule = [
    ?impreciseNotCountedNames(summary.notes),
    ?optionalNotCountedNames(summary.notes),
  ];
  return jsonEncode({
    'recipe': title,
    'basis': ?basis,
    if (per == null) ...{
      'no_figure': incompleteNote(summary),
      'waiting_on': [
        for (final n in fixableNotes(summary))
          '${n.name} · ${incompleteLineNote(n.reason)}',
      ],
    } else ...{
      'per_serving': _macros(per),
      if (servings != null) ...{
        'servings': formatAmount(servings),
        'for_those_servings': _macros(per.scaledBy(servings)),
      },
      if (byRule.isNotEmpty) 'not_counted_by_rule': byRule.join(', '),
      'fibre_note': ?fiberNotCountedNote(summary),
    },
  });
}

/// `nutrition` for a day or a week of the plan: the Week band's own total
/// under the same lens, a week as its per-day average beside the whole.
String planNutritionResult(
  MealSetMacros macros, {
  required String scope,
  required String forWhom,
  required bool isDay,
}) {
  final total = macros.total;
  final average = macros.perDayAverage;
  return jsonEncode({
    'scope': scope,
    'for': forWhom,
    if (macros.isEmpty)
      'meals': forWhom == 'everyone' ? 'no meals' : 'no meals for $forWhom'
    else
      'meals': mealDenominator(macros),
    if (total == null && !macros.isEmpty)
      'no_figure': 'no meal in scope could be counted',
    if (total != null && isDay) 'total': _macros(total),
    if (total != null && !isDay) ...{
      'per_day_average': _macros(average!),
      'over_days': macros.daysContributing,
      'week_total': _macros(total),
    },
    if (macros.excluded.isNotEmpty) 'left_out': excludedLine(macros),
  });
}

/// `cost` for one recipe at the latest prices: per serving and whole, or the
/// floor and the lines without a price.
String recipeCostResult(
  String title,
  RecipeCostSummary summary, {
  double? servings,
  String? basis,
}) {
  final per = summary.perServingCents;
  final total = summary.totalCents;
  final byRule = [?impreciseCostNames(summary), ?optionalCostNames(summary)];
  return jsonEncode({
    'recipe': title,
    'basis': ?basis,
    if (total == null) ...{
      'no_figure': costRefusal(summary),
      'at_least': ?costFloor(summary),
      'unpriced': ?unpricedNames(summary),
    } else ...{
      'per_serving': ?(per == null ? null : formatMoneyRounded(per)),
      'whole_recipe': formatMoneyRounded(total),
      if (servings != null && per != null) ...{
        'servings': formatAmount(servings),
        'for_those_servings': formatMoneyRounded(per * servings),
      },
      if (byRule.isNotEmpty) 'not_counted_by_rule': byRule.join(', '),
    },
  });
}

/// `cost` for a day or a week of the plan: the band's cost to cook, what it
/// could not price, and for a week — never reconciled with it — what the
/// receipts say was spent.
String planCostResult(
  PlannedCost cost, {
  required String scope,
  required String forWhom,
  required String? spent,
  required bool isDay,
}) => jsonEncode({
  'scope': scope,
  'for': forWhom,
  'to_cook':
      weekCostLine(cents: cost.cents, unpriced: cost.unpriced.length) ??
      'nothing priced',
  'meals_priced': '${cost.counted} of ${cost.considered}',
  if (cost.unpriced.isNotEmpty) 'unpriced': cost.unpriced.join(', '),
  'meals_out': 'meals eaten out are not costed',
  if (!isDay) 'spent': spent ?? 'no receipts dated in this week',
});

/// `cost` with `trip`: the Shop's estimate of what is left to buy, the figure
/// on its sync line, read at the Shop's prices rather than the latest.
String tripCostResult(TripCost trip) => jsonEncode({
  'still_to_buy': tripEstimate(trip) ?? 'nothing on the list can be priced',
  'prices':
      'each row at the cheapest price seen on a receipt in the last '
      '$shopPriceWindowDays days, else its latest price; a row that rounds '
      'up is priced on the whole count bought',
  if (trip.unpriced > 0)
    'unpriced_rows': '${trip.unpriced} ${plural(trip.unpriced, 'row')}',
});

/// The most purchases [pricesResult] lists.
const kAskPriceHistory = 3;

/// `prices`: the latest purchases of one ingredient, newest first, and the
/// price every cost reads for it.
String pricesResult(
  String name, {
  required List<PriceObservation> bought,
  required UnitPrice? costPrice,
}) {
  final newest = [...bought]
    ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
  return jsonEncode({
    'ingredient': name,
    'bought': [
      for (final o in newest.take(kAskPriceHistory))
        {
          'where': o.store,
          'when': formatDayMonth(o.purchasedAt),
          'paid': formatMoney(o.paidCents),
          'price': unitPriceWord(o),
        },
    ],
    if (newest.isEmpty) 'note': 'no receipt has bought it',
    if (costPrice != null)
      'costed_at': '${unitPriceWord(costPrice)} · ${priceProvenance(costPrice)}'
    else
      'costed_at': 'no price yet',
  });
}
