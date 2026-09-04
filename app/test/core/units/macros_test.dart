import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Macros.tryParse', () {
    test('parses the server jsonb shape', () {
      final m = Macros.tryParse('{"kcal":197,"protein":2,"carb":3,"fat":20.5}');
      expect(m, isNotNull);
      expect(m!.kcal, 197);
      expect(m.protein, 2);
      expect(m.carb, 3);
      expect(m.fat, 20.5);
    });

    test('null / empty / malformed input parses to null', () {
      expect(Macros.tryParse(null), isNull);
      expect(Macros.tryParse(''), isNull);
      expect(Macros.tryParse('not json'), isNull);
      expect(Macros.tryParse('[1,2,3]'), isNull);
    });

    test('a missing or non-numeric key is null, never a zero', () {
      // Invariant 3: no zeros invented for missing data.
      expect(Macros.tryParse('{"kcal":197,"protein":2,"carb":3}'), isNull);
      expect(
        Macros.tryParse('{"kcal":"x","protein":2,"carb":3,"fat":20}'),
        isNull,
      );
    });
  });

  group('arithmetic', () {
    const a = Macros(kcal: 100, protein: 10, carb: 20, fat: 5);
    const b = Macros(kcal: 50, protein: 1, carb: 2, fat: 3);

    test('adds field-wise', () {
      expect(a + b, const Macros(kcal: 150, protein: 11, carb: 22, fat: 8));
    });

    test('scales field-wise', () {
      expect(
        a.scaledBy(2.5),
        const Macros(kcal: 250, protein: 25, carb: 50, fat: 12.5),
      );
    });
  });

  group('Macros.per100From', () {
    test('a 14 g serving at 100 kcal reads 714.29 kcal per 100 g, '
        'unrounded', () {
      final per100 = Macros.per100From(
        serving: 14,
        basis: MacrosBasis.perG,
        printed: const Macros(kcal: 100, protein: 0, carb: 0, fat: 11),
      );
      expect(per100, isNotNull);
      expect(per100!.kcal, closeTo(714.2857, 0.0001));
      expect(per100.fat, closeTo(78.5714, 0.0001));
      expect(per100.protein, 0);
      expect(per100.carb, 0);
      // M-D3: stored as derived — no rounding of our own on top of the
      // label's.
      expect(per100.kcal, isNot(714));
    });

    test('an ml basis scales the same way — the basis names the unit, not the '
        'arithmetic', () {
      final per100 = Macros.per100From(
        serving: 240,
        basis: MacrosBasis.perMl,
        printed: const Macros(kcal: 120, protein: 8, carb: 12, fat: 5),
      );
      expect(
        per100,
        const Macros(kcal: 50, protein: 8 / 2.4, carb: 5, fat: 5 / 2.4),
      );
    });

    test('a non-positive or non-finite serving is refused, never divided '
        'by', () {
      const printed = Macros(kcal: 100, protein: 1, carb: 2, fat: 3);
      for (final serving in [0.0, -14.0, double.nan, double.infinity]) {
        expect(
          Macros.per100From(
            serving: serving,
            basis: MacrosBasis.perG,
            printed: printed,
          ),
          isNull,
          reason: '$serving',
        );
      }
    });
  });

  group('MacrosBasis', () {
    test('round-trips the stored value', () {
      expect(MacrosBasis.fromDb('g'), MacrosBasis.perG);
      expect(MacrosBasis.fromDb('ml'), MacrosBasis.perMl);
      expect(MacrosBasis.perG.dbValue, 'g');
      expect(MacrosBasis.perMl.dbValue, 'ml');
    });

    test('anything unexpected falls back to per-100 g', () {
      expect(MacrosBasis.fromDb(null), MacrosBasis.perG);
      expect(MacrosBasis.fromDb('cups'), MacrosBasis.perG);
    });

    test('the conversion target is the basis base unit', () {
      expect(MacrosBasis.perG.baseUnit, g);
      expect(MacrosBasis.perMl.baseUnit, ml);
    });
  });
}
