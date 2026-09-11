import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/presentation/shopping_format.dart';
import 'package:flutter_test/flutter_test.dart';

const _can = Measure(id: 'ml', label: 'can (400 g), drained', amount: 240);

void main() {
  group("formatItemCount (the Shop tab's menu row, in its own words)", () {
    test('counts rolled-up items, never meals', () {
      expect(formatItemCount(0), 'nothing to buy');
      expect(formatItemCount(1), '1 item');
      expect(formatItemCount(6), '6 items');
    });
  });

  group('itemTotal', () {
    test('a measure-counted row reads in its measure', () {
      final item = ShoppingItem(
        name: 'Canned Lentils',
        ingredientId: 'lentils',
        totals: [Quantity(240, g)],
        measureTotal: (amount: 1, measure: _can),
      );
      expect(itemTotal(item), '1 can (400 g), drained');
      // …and what it weighs sits beside it, never instead of it.
      expect(itemSecondary(item), '240 g');
    });

    test('a mixed row reads in the canonical family sum', () {
      final item = ShoppingItem(
        name: 'Canned Lentils',
        ingredientId: 'lentils',
        totals: [Quantity(15.52, oz)],
      );
      expect(itemTotal(item), '15.52 oz');
      expect(itemSecondary(item), '');
    });

    test('the round-up hint is the secondary line when there is no count', () {
      final item = ShoppingItem(
        name: 'Potato',
        ingredientId: 'potato',
        totals: [Quantity(674, g)],
        wholeUnitHint: (
          count: 2.25,
          buy: 3,
          unitLabel: 'potato, large',
          approx: true,
        ),
      );
      expect(itemTotal(item), '674 g');
      expect(itemSecondary(item), '≈ 2.25 potato, large → buy 3');
    });

    test('honest subtotals join, and a numberless staple is an em dash', () {
      final split = ShoppingItem(
        name: 'Yoghurt',
        ingredientId: 'yog',
        totals: [Quantity(200, g), Quantity(100, ml)],
      );
      expect(itemTotal(split), '200 g + 100 ml');
      expect(itemTotal(const ShoppingItem(name: 'Paper towels')), '—');
    });
  });

  group('contributionQuantity', () {
    test('a line keeps its own words whatever the total ended up in', () {
      expect(
        contributionQuantity(
          const ShoppingContribution(
            source: ContributionSource.cookSession,
            label: 'Dal',
            quantity: 2,
            measure: _can,
          ),
        ),
        '2 can (400 g), drained',
      );
      expect(
        contributionQuantity(
          const ShoppingContribution(
            source: ContributionSource.cookSession,
            label: 'Salad',
            quantity: 200,
            unit: g,
          ),
        ),
        '200 g',
      );
    });
  });
}
