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
      // What you buy leads; the need, still approximate, sits under it with
      // the weight it was read from.
      expect(itemTotal(item), '3 potato, large');
      expect(itemAmount(item), '674 g');
      expect(itemSecondary(item), 'need ≈ 2¼ · 674 g');
    });

    test('a fractional gram total is a scale reading, its measure count is '
        'not', () {
      const large = Measure(id: 'pl', label: 'potato, large', amount: 299);
      final item = ShoppingItem(
        name: 'Potato',
        ingredientId: 'potato',
        totals: [Quantity(672.75, g)],
        measureTotal: (amount: 2.25, measure: large),
      );
      // A fractional measure count leads with the same whole count a piece
      // count does — you buy whole potatoes.
      expect(itemTotal(item), '3 potato, large');
      expect(itemSecondary(item), 'need 2¼ · 672.75 g');
    });

    test('a measure-counted lime rounds up like a piece-counted one, and a '
        'whole count needs no round-up', () {
      const whole = Measure(id: 'm-lime', label: 'lime, whole', amount: 67);
      final lime = ShoppingItem(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(167.5, g)],
        measureTotal: (amount: 2.5, measure: whole),
      );
      expect(itemTotal(lime), '3 lime, whole');
      expect(itemSecondary(lime), 'need 2½ · 167.5 g');
      // The amount as summed keeps the fraction: the at-home pass asks
      // against it.
      expect(itemAmount(lime), '2½ lime, whole');

      final three = ShoppingItem(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(201, g)],
        measureTotal: (amount: 3, measure: whole),
      );
      expect(itemTotal(three), '3 lime, whole');
      expect(itemSecondary(three), '201 g');
    });

    test('a piece-weighted row reads its count, with the grams under it', () {
      // 1 lime, whole (67 g) + 1½ piece on a 67 g piece: 2½ limes, exactly.
      final lime = ShoppingItem(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(167.5, g)],
        pieceTotal: (count: 2.5, approx: false),
      );
      // The count is fractional, so the whole count leads and the need and
      // the weight sit under it.
      expect(itemTotal(lime), '3 piece');
      expect(itemSecondary(lime), 'need 2½ · 167.5 g');
    });

    test('a count read back from a weight says so, and a whole one needs no '
        'round-up', () {
      final approx = ShoppingItem(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(160.8, g)],
        pieceTotal: (count: 2.4, approx: true),
      );
      // What you buy is a whole number; the `≈` belongs to the need.
      expect(itemTotal(approx), '3 piece');
      expect(itemSecondary(approx), 'need ≈ 2.4 · 160.8 g');

      final whole = ShoppingItem(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(201, g)],
        pieceTotal: (count: 3, approx: false),
      );
      expect(itemTotal(whole), '3 piece');
      expect(itemSecondary(whole), '201 g');
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

  group('the rounded headline', () {
    test('a fractional plain count leads with what is bought and says only '
        'its need under it', () {
      final item = ShoppingItem(
        name: 'Avocado',
        ingredientId: 'avocado',
        totals: [Quantity(1.5, pieces)],
        wholeUnitHint: (count: 1.5, buy: 2, unitLabel: 'piece', approx: false),
      );
      expect(itemTotal(item), '2 piece');
      expect(itemSecondary(item), 'need 1½');
    });

    test('an unrounded row is unchanged: its amount is its headline', () {
      final item = ShoppingItem(
        name: 'Flour',
        ingredientId: 'flour',
        totals: [Quantity(500, g)],
      );
      expect(itemTotal(item), '500 g');
      expect(itemNeed(item), '');
      expect(itemSecondary(item), '');
    });

    test('a sum that lands a hair off a whole number does not round up', () {
      const whole = Measure(id: 'm-lime', label: 'lime, whole', amount: 67);
      final item = ShoppingItem(
        name: 'Lime',
        ingredientId: 'lime',
        totals: [Quantity(201, g)],
        measureTotal: (amount: 2.9999999999, measure: whole),
      );
      expect(itemRoundUp(item), isNull);
      expect(itemSecondary(item), '201 g');
    });

    test('the sub-line reads at home, then need, then weight, then price', () {
      const medium = Measure(
        id: 'm-onion',
        label: 'onion, medium',
        amount: 110,
      );
      // Five at home of 6½ asked for: 1½ left, so the row buys 2.
      final item = ShoppingItem(
        name: 'Yellow Onion',
        ingredientId: 'onion',
        totals: [Quantity(165, g)],
        measureTotal: (amount: 1.5, measure: medium),
        atHome: (
          quantity: 5,
          unit: pieces,
          measure: medium,
          measureId: medium.id,
          need: (
            totals: [Quantity(715, g)],
            measureTotal: (amount: 6.5, measure: medium),
            pieceTotal: null,
          ),
          all: false,
          refusal: null,
        ),
      );
      expect(itemTotal(item), '2 onion, medium');
      final line = itemSubLine(item, cents: 154, anyPriced: true);
      expect(line, startsWith('5 at home · need 1½ · 165 g · '));
      expect(line, contains('1.54'));
      // With no price yet and nothing at home, only the need and the weight.
      expect(itemSubLine(item.copyWith(atHome: null)), 'need 1½ · 165 g');
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
