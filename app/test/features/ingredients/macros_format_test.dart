/// The one display rounding rule: energy whole, a gram figure whole from a
/// gram up and to one decimal below it, and nothing rounded on its way into
/// storage.
///
/// The rule is display-only on purpose, so the two halves are tested
/// together: what a surface PRINTS, and what a form field seeded from a
/// stored figure shows while the draft behind it keeps the figure whole.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/presentation/macros_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('energy is whole', () {
    test('a derived figure loses the tail of a division nobody asked for', () {
      expect(formatKcal(285.714285714286), '286');
      expect(formatKcal(46.511627906977), '47');
      expect(formatKcal(642.464), '642');
    });

    test('a whole number stays one, and a zero is a zero', () {
      expect(formatKcal(0), '0');
      expect(formatKcal(539), '539');
    });
  });

  group('grams are whole from a gram up', () {
    test('a gram or more loses its tail — nobody weighs a tenth of one', () {
      expect(formatGrams(21.4285714285714), '21');
      expect(formatGrams(54.101), '54');
      expect(formatGrams(1.6), '2');
    });

    test('a trailing .0 is dropped — 25, never 25.0', () {
      expect(formatGrams(25), '25');
      expect(formatGrams(6.999), '7');
      expect(formatGrams(0), '0');
    });

    test('below a gram the decimal stays — an oat milk stores protein, and a '
        'line that said 0P would be lying about it', () {
      expect(formatGrams(0.42), '0.4');
      expect(formatGrams(0.96), '1');
      expect(formatGrams(0.42), isNot('0'));
    });
  });

  group('the line the two build', () {
    test('the picker row’s line, in the panel’s own order', () {
      expect(
        formatMacroLine(
          const Macros(kcal: 197.4, protein: 2, carb: 3, fat: 20),
        ),
        '197 kcal · 2P 3C 20F',
      );
    });

    test('a derived per-100 row prints one rule, not two', () {
      expect(
        formatMacroLine(
          const Macros(
            kcal: 285.714285714286,
            protein: 0,
            carb: 21.4285714285714,
            fat: 25,
            fiber: 0,
          ),
        ),
        '286 kcal · 0P 21C 25F · 0 fibre',
      );
    });

    test('an unstated fibre prints nothing at all — it is not a zero', () {
      const stated = Macros(kcal: 60, protein: 1, carb: 15, fat: 0, fiber: 3);
      const unstated = Macros(kcal: 60, protein: 1, carb: 15, fat: 0);
      expect(formatMacroLine(stated), '60 kcal · 1P 15C 0F · 3 fibre');
      expect(formatMacroLine(unstated), '60 kcal · 1P 15C 0F');
    });

    test('the basis suffix says which 100', () {
      expect(macroBasisSuffix(MacrosBasis.perG), '/100 g');
      expect(macroBasisSuffix(MacrosBasis.perMl), '/100 ml');
    });
  });

  group('a macro field shows the rule and stores past it', () {
    test('a stored figure is SHOWN rounded', () {
      expect(macroFieldText('285.714285714286', energy: true), '286');
      expect(macroFieldText('21.4285714285714', energy: false), '21');
      expect(macroFieldText('0.4285714', energy: false), '0.4');
      expect(macroFieldText('60', energy: true), '60');
    });

    test('anything that is not a number stands exactly as it is — a blank '
        'field, and text nobody can round', () {
      expect(macroFieldText('', energy: true), '');
      expect(macroFieldText('twelve', energy: false), 'twelve');
      expect(macroFieldText('  ', energy: false), '  ');
    });
  });
}
