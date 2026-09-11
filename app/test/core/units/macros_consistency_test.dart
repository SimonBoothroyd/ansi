/// Table-driven over the vocabulary's own awkward rows.
///
/// The table is the whole point: two thresholds trade a caught mistake
/// against a false alarm, and the only honest way to set them is against real
/// foods that break the arithmetic honestly — a vinegar whose calories are
/// acetic acid, a wine whose calories are alcohol, a raising agent that is
/// mostly mineral, a cocoa that is mostly fibre. Every row below says which
/// side of the line it is meant to fall on and why.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/macros_consistency.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Case = ({String food, Macros macros, bool flags, String why});

const _cases = <_Case>[
  (
    food: 'Crispy Onion',
    macros: Macros(kcal: 571, protein: 0, carb: 42.9, fat: 0),
    flags: true,
    why:
        'a fried food filed with no fat at all — 571 kcal against 172 from '
        'the carbohydrate, and the fat column is plainly the one that is '
        'missing',
  ),
  (
    food: 'Fresh Oregano',
    macros: Macros(kcal: 60.9, protein: 0, carb: 0, fat: 0),
    flags: true,
    why:
        'calories out of nothing at all — the first field filled and the '
        'other three never were',
  ),
  (
    food: 'White wine vinegar',
    macros: Macros(kcal: 18, protein: 0, carb: 0.9, fat: 0),
    flags: false,
    why:
        'THE FLOOR’S REASON — acetic acid is not an Atwater macro, so a '
        'vinegar’s energy has nowhere to come from and the panel is still '
        'right. 14 kcal of gap is under the flat 150',
  ),
  (
    food: 'Red wine',
    macros: Macros(kcal: 85, protein: 0.1, carb: 2.6, fat: 0),
    flags: false,
    why:
        'the same reason with alcohol in place of acid: 7 kcal a gram, and '
        'the app has no column for it',
  ),
  (
    food: 'Baking powder',
    macros: Macros(kcal: 53, protein: 0, carb: 28, fat: 0, fiber: 0),
    flags: false,
    why:
        'the gap runs the OTHER way — a mineral raising agent’s carbohydrate '
        'is largely unavailable, so 112 implied against 53 stated is the '
        'food, not a typo',
  ),
  (
    food: 'Cocoa powder',
    macros: Macros(kcal: 228, protein: 0, carb: 58, fat: 0, fiber: 33),
    flags: false,
    why:
        'THE FIBRE ADJUSTMENT’S REASON — counted whole, 58 g of carbohydrate '
        'implies 232 kcal and hides a missing 20 g of protein and 14 g of '
        'fat; with the 33 g of fibre moved onto the 2 it implies 166, which '
        'is inside the slack for a 228 kcal food',
  ),
  (
    food: 'Olive oil',
    macros: Macros(kcal: 884, protein: 0, carb: 0, fat: 100),
    flags: false,
    why: 'the arithmetic at its most exact: 900 implied against 884 stated',
  ),
  (
    food: 'Chicken thigh, boneless',
    macros: Macros(kcal: 209, protein: 26, carb: 0, fat: 11),
    flags: false,
    why: 'an ordinary protein row — 203 implied against 209 stated',
  ),
  (
    food: 'a label’s fat column typed into the carb slot',
    macros: Macros(kcal: 884, protein: 0, carb: 100, fat: 0),
    flags: true,
    why:
        'THE MISTAKE THIS EXISTS FOR — 400 implied against 884 stated, which '
        'clears both the flat floor and half the energy',
  ),
  (
    food: 'Water',
    macros: Macros(kcal: 0, protein: 0, carb: 0, fat: 0),
    flags: false,
    why:
        'a panel of honest zeros is not a panel of missing figures: nothing '
        'is claimed, so nothing is doubted',
  ),
];

void main() {
  group('macrosDoubt', () {
    for (final c in _cases) {
      test('${c.food} ${c.flags ? 'flags' : 'is left alone'} — ${c.why}', () {
        expect(macrosDoubt(c.macros) != null, c.flags);
      });
    }

    test('a panel with no figures says nothing — there is no arithmetic to '
        'doubt yet', () {
      expect(macrosDoubt(null), isNull);
    });

    test('zeros on a food with calories are named as such, not as a gap', () {
      expect(
        macrosDoubt(const Macros(kcal: 60.9, protein: 0, carb: 0, fat: 0)),
        const MacrosAllZero(),
      );
      // And the gap carries the figure the line quotes back, so a person can
      // see which column is wrong.
      expect(
        macrosDoubt(const Macros(kcal: 884, protein: 0, carb: 100, fat: 0)),
        const MacrosEnergyGap(400),
      );
    });
  });

  group('atwaterKcal', () {
    test('4 · 9 · 4, with a stated fibre moved onto the 2', () {
      expect(
        atwaterKcal(const Macros(kcal: 0, protein: 10, carb: 20, fat: 5)),
        4 * 10 + 4 * 20 + 9 * 5,
      );
      // 20 g of carbohydrate of which 8 is fibre: 12 × 4 + 8 × 2.
      expect(
        atwaterKcal(
          const Macros(kcal: 0, protein: 10, carb: 20, fat: 5, fiber: 8),
        ),
        4 * 10 + 4 * 12 + 2 * 8 + 9 * 5,
      );
    });

    test('a fibre bigger than the carbohydrate it is part of leaves no '
        'negative behind', () {
      expect(
        atwaterKcal(
          const Macros(kcal: 0, protein: 0, carb: 2, fat: 0, fiber: 5),
        ),
        2 * 5,
      );
    });
  });
}
