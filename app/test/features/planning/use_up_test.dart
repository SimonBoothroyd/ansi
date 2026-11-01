import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/domain/use_up.dart';
import 'package:flutter_test/flutter_test.dart';

SpareInput _row(
  String id, {
  String category = 'produce',
  double need = 0,
  double? toBuy,
  double bought = 0,
  double used = 0,
  double? cents,
}) => (
  ingredientId: id,
  name: id,
  category: category,
  unit: g,
  need: need,
  toBuy: toBuy ?? need,
  bought: bought,
  usedCooked: used,
  centsPerUnit: cents,
);

void main() {
  group('spareOf', () {
    test('a pack bigger than the need leaves the rest', () {
      // A 500 g bag for 200 g of spinach.
      final spare = spareOf([
        _row('spinach', need: 200, bought: 500, used: 200, cents: 0.7),
      ]);
      expect(spare.single.amount, 300);
      expect(spare.single.bought, 500);
      expect(spare.single.used, 200);
    });

    test('an uncooked batch leaves everything bought for it', () {
      // Needed 500 g of mushrooms, bought them, the batch was never cooked.
      expect(
        spareOf([_row('mushrooms', need: 500, bought: 500)]).single.amount,
        500,
      );
    });

    test('what was already at home counts as in the house', () {
      // 300 g needed, 100 g at home, 200 g bought, 300 g used: none spare.
      expect(
        spareOf([_row('feta', need: 300, toBuy: 200, bought: 200, used: 300)]),
        isEmpty,
      );
    });

    test('only fresh food is offered back', () {
      expect(
        spareOf([
          _row('rice', category: 'grains', bought: 1000),
          _row('tofu', category: 'Proteins', bought: 400),
          _row('salt', category: 'spices & seasoning', bought: 500),
        ]).map((s) => s.ingredientId),
        ['tofu'],
      );
    });

    test('most valuable first', () {
      final spare = spareOf([
        _row('onion', bought: 75, cents: 0.24),
        _row('spinach', bought: 300, cents: 0.7),
      ]);
      expect(spare.map((s) => s.ingredientId), ['spinach', 'onion']);
    });
  });

  group('scoring and ranking', () {
    final spare = spareOf([
      _row('spinach', bought: 300, cents: 0.7), // $2.10
      _row('tofu', category: 'proteins', bought: 150, cents: 1.6), // $2.40
      _row('coriander', bought: 20, cents: 3.3), // $0.66
      _row('garlic', bought: 490, cents: 1.6), // a 500 g jar, $7.84 spare
      _row('onion', bought: 75, cents: 0.24), // half an onion
    ]);

    RecipeUse recipe(String title, Map<String, double> perBatch) =>
        (recipeId: title, title: title, servingsBase: 2, perBatch: perBatch);

    final recipes = [
      recipe('Pie', {'spinach': 300, 'tofu': 150, 'flour': 200}),
      recipe('Shakshuka', {'spinach': 200, 'tofu': 50, 'coriander': 20}),
      recipe('Tikka bowls', {'coriander': 20, 'garlic': 10}),
      recipe('Onion soup', {'onion': 150, 'garlic': 15}),
      recipe('Toast', {'bread': 100}),
    ];

    test('a recipe scores by what the amounts it would use cost', () {
      final scored = scoreUseUp(recipes: recipes, spare: spare, portions: 2);
      expect(scored.map((s) => s.title), [
        'Pie',
        'Shakshuka',
        'Tikka bowls',
        'Onion soup',
      ]);
      expect(scored.first.score, closeTo(300 * 0.7 + 150 * 1.6, 1e-9));
      // The bulk jar adds what ten grams cost, never the jar.
      expect(scored[2].score, closeTo(20 * 3.3 + 10 * 1.6, 1e-9));
      // Half an onion is all that is spare, however much the soup wants.
      expect(
        scored[3].uses.firstWhere((u) => u.ingredientId == 'onion').amount,
        75,
      );
    });

    test('scaled to the meal, never past what is spare', () {
      final pie = scoreUseUp(
        recipes: [recipes.first],
        spare: spare,
        portions: 1,
      ).single;
      expect(pie.uses.map((u) => (u.ingredientId, u.amount)), [
        ('tofu', 75),
        ('spinach', 150),
      ]);
    });

    test('offers at most three, each at least half the best', () {
      final ranked = rankUseUp(
        scoreUseUp(recipes: recipes, spare: spare, portions: 2),
      );
      expect(ranked.map((s) => s.title), ['Pie', 'Shakshuka']);
    });

    test('nothing priced, nothing offered', () {
      final unpriced = spareOf([_row('spinach', bought: 300)]);
      expect(
        rankUseUp(scoreUseUp(recipes: recipes, spare: unpriced, portions: 2)),
        isEmpty,
      );
    });
  });
}
