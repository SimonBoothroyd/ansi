import 'dart:convert';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ask/presentation/ask_figures.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/planning/domain/week_macros.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _json(String s) => jsonDecode(s) as Map<String, Object?>;

const _perServing = Macros(kcal: 285, protein: 21, carb: 30.4, fat: 9.6);

void main() {
  group('nutrition', () {
    test('a recipe per serving, and at the servings on screen', () {
      final json = _json(
        recipeNutritionResult(
          'Tofu Scramble',
          const RecipeMacroSummary(perServing: _perServing),
          servings: 2,
        ),
      );
      expect(json['per_serving'], {
        'kcal': '285 kcal',
        'protein': '21 g',
        'carbs': '30 g',
        'fat': '10 g',
      });
      expect((json['for_those_servings']! as Map)['kcal'], '570 kcal');
    });

    test('an incomplete recipe has no figure, only what it waits on', () {
      final json = _json(
        recipeNutritionResult(
          'Ragù',
          const RecipeMacroSummary(
            stubLines: 1,
            notes: [
              (
                lineId: 'l1',
                name: 'Skyr',
                reason: MacroLineReason.stubIngredient,
                unit: null,
              ),
            ],
          ),
        ),
      );
      expect(json.containsKey('per_serving'), isFalse);
      expect(json['no_figure'], '1 stub line');
      expect(json['waiting_on'], ['Skyr · stub ingredient']);
    });

    test('a week is its per-day average, and names the meals left out', () {
      final json = _json(
        planNutritionResult(
          const MealSetMacros(
            total: Macros(kcal: 3680, protein: 200, carb: 400, fat: 120),
            counted: 4,
            considered: 5,
            daysContributing: 2,
            excluded: [
              (
                entryId: 'e5',
                label: 'Office lunch',
                reason: MealExclusion.outNotStated,
                summary: null,
                lineReason: null,
              ),
            ],
          ),
          scope: 'the week of Sun 18 Oct',
          forWhom: 'Simon',
          isDay: false,
        ),
      );
      expect((json['per_day_average']! as Map)['kcal'], '1840 kcal');
      expect(json['over_days'], 2);
      expect(json['meals'], '4 of 5 meals');
      expect(json['left_out'], 'Office lunch · macros not stated');
      expect(json['for'], 'Simon');
    });

    test('a day is its total; nothing planned says so', () {
      final day = _json(
        planNutritionResult(
          const MealSetMacros(
            total: _perServing,
            counted: 1,
            considered: 1,
            daysContributing: 1,
          ),
          scope: 'Tue 20 Oct',
          forWhom: 'Simon',
          isDay: true,
        ),
      );
      expect((day['total']! as Map)['kcal'], '285 kcal');
      expect(day.containsKey('per_day_average'), isFalse);
      final empty = _json(
        planNutritionResult(
          const MealSetMacros(),
          scope: 'Tue 20 Oct',
          forWhom: 'Simon',
          isDay: true,
        ),
      );
      expect(empty['meals'], 'no meals for Simon');
    });
  });

  group('cost', () {
    test('a recipe per serving and whole, at the latest prices', () {
      final json = _json(
        recipeCostResult(
          'Ragù',
          const RecipeCostSummary(totalCents: 1316, perServingCents: 329),
          servings: 6,
        ),
      );
      expect(json['per_serving'], r'$3.29');
      expect(json['whole_recipe'], r'$13.16');
      expect(json['for_those_servings'], r'$19.74');
    });

    test('a recipe with an unpriced line is a floor, the line named', () {
      final json = _json(
        recipeCostResult(
          'Ragù',
          const RecipeCostSummary(
            pricedCents: 660,
            pricedPerServingCents: 165,
            lineCosts: {'l1': CostLine(cents: 660)},
            unpriced: [
              (
                lineId: 'l2',
                name: 'Tamari',
                reason: CostLineReason.noPrice,
                unit: null,
              ),
            ],
          ),
        ),
      );
      expect(json.containsKey('whole_recipe'), isFalse);
      expect(json['no_figure'], '1 line unpriced');
      expect(
        json['at_least'],
        r'at least $1.65 a serving · at least $6.60 the recipe',
      );
      expect(json['unpriced'], 'Tamari · no price yet');
    });

    test('a week: the cost to cook, and what was spent, never reconciled', () {
      final json = _json(
        planCostResult(
          (cents: 7100, counted: 3, considered: 4, unpriced: ['Tamari']),
          scope: 'the week of Sun 18 Oct',
          forWhom: 'everyone',
          spent: r"$84.12 spent · 1 receipt · TJ's, Sun",
          isDay: false,
        ),
      );
      expect(json['to_cook'], r'at least $71 to cook · 1 line unpriced');
      expect(json['meals_priced'], '3 of 4');
      expect(json['spent'], r"$84.12 spent · 1 receipt · TJ's, Sun");
      // A day is a cost to cook alone: receipts are filed by week.
      final day = _json(
        planCostResult(
          (cents: 1200, counted: 1, considered: 1, unpriced: const []),
          scope: 'Tue 20 Oct',
          forWhom: 'Simon',
          spent: null,
          isDay: true,
        ),
      );
      expect(day.containsKey('spent'), isFalse);
    });

    test('the trip: what is still to buy', () {
      expect(
        _json(tripCostResult((cents: 5800, unpriced: 2)))['still_to_buy'],
        r'at least $58 at the cheapest · 2 rows unpriced',
      );
      // Ansi is told which price the trip reads, since every other cost
      // reads the latest.
      expect(
        _json(tripCostResult((cents: 5800, unpriced: 0)))['prices'],
        contains('cheapest price seen on a receipt in the last 90 days'),
      );
      expect(
        _json(tripCostResult((cents: null, unpriced: 3)))['still_to_buy'],
        'nothing on the list can be priced',
      );
    });
  });

  test('prices: the latest purchases, newest first, and the cost price', () {
    PriceObservation bought(int day, int cents) => PriceObservation(
      lineId: 'l$day',
      receiptId: 'r$day',
      cents: cents,
      packBasisAmount: 296,
      basis: MacrosBasis.perMl,
      store: "TJ's",
      purchasedAt: DateTime.utc(2026, 10, day),
      packLabel: 'bottle (10 fl oz)',
      packAmount: 10,
      packUnit: flOz,
    );
    final json = _json(
      pricesResult(
        'Tamari',
        bought: [bought(2, 349), bought(16, 379)],
        costPrice: bought(16, 379),
      ),
    );
    final first = (json['bought']! as List).first as Map;
    expect(first['when'], '16 Oct');
    expect(first['paid'], r'$3.79');
    expect(first['price'], r'$3.79 a bottle (10 fl oz)');
    expect(json['costed_at'], startsWith(r'$3.79 a bottle (10 fl oz)'));
  });
}
