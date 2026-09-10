import 'dart:convert';

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

  group('fibre — the optional fifth', () {
    test('a row without a fiber key is complete, with fibre unstated', () {
      final m = Macros.tryParse('{"kcal":197,"protein":2,"carb":3,"fat":20.5}');
      expect(m, isNotNull);
      expect(m!.fiber, isNull);
    });

    test('a fiber key is read when it is there', () {
      final m = Macros.tryParse(
        '{"kcal":197,"protein":2,"carb":3,"fat":20.5,"fiber":5.4}',
      );
      expect(m!.fiber, 5.4);
    });

    test('a zero fibre is a reading, not an absence', () {
      final m = Macros.tryParse(
        '{"kcal":10,"protein":0,"carb":0,"fat":0,"fiber":0}',
      );
      expect(m!.fiber, 0);
    });

    test('a non-numeric fibre reads as unstated — it never costs the row its '
        'four', () {
      final m = Macros.tryParse(
        '{"kcal":197,"protein":2,"carb":3,"fat":20.5,"fiber":"lots"}',
      );
      expect(m, isNotNull);
      expect(m!.fiber, isNull);
      expect(m.kcal, 197);
    });

    test('toJson writes the four always and fibre only when stated', () {
      expect(const Macros(kcal: 1, protein: 2, carb: 3, fat: 4).toJson(), {
        'kcal': 1.0,
        'protein': 2.0,
        'carb': 3.0,
        'fat': 4.0,
      });
      expect(
        const Macros(kcal: 1, protein: 2, carb: 3, fat: 4, fiber: 5).toJson(),
        containsPair('fiber', 5.0),
      );
    });

    test('round-trips through the stored shape, with and without fibre', () {
      for (final m in const [
        Macros(kcal: 197, protein: 2, carb: 3, fat: 20.5),
        Macros(kcal: 197, protein: 2, carb: 3, fat: 20.5, fiber: 5.4),
        Macros(kcal: 197, protein: 2, carb: 3, fat: 20.5, fiber: 0),
      ]) {
        expect(Macros.tryParse(jsonEncode(m.toJson())), m, reason: '$m');
      }
    });

    test('a set with fibre and one without are not equal — an unstated fibre '
        'is not a zero', () {
      const stated = Macros(kcal: 1, protein: 2, carb: 3, fat: 4, fiber: 0);
      const unstated = Macros(kcal: 1, protein: 2, carb: 3, fat: 4);
      expect(stated, isNot(unstated));
      expect(stated.hashCode, isNot(unstated.hashCode));
    });

    test('a sum states fibre only when EVERY addend did', () {
      const withFibre = Macros(kcal: 1, protein: 1, carb: 1, fat: 1, fiber: 2);
      const without = Macros(kcal: 1, protein: 1, carb: 1, fat: 1);
      expect((withFibre + withFibre).fiber, 4);
      // A partial fibre total is short by an unknown amount, which is exactly
      // the fabricated number invariant 3 forbids — so there is no total.
      expect((withFibre + without).fiber, isNull);
      expect((without + withFibre).fiber, isNull);
      expect((without + without).fiber, isNull);
      // The four are unaffected either way: fibre never costs a line its
      // place in the total.
      expect((withFibre + without).kcal, 2);
    });

    test('scaling carries fibre, and scales nothing into nothing', () {
      const m = Macros(kcal: 100, protein: 10, carb: 20, fat: 5, fiber: 4);
      expect(m.scaledBy(2.5).fiber, 10);
      expect(
        const Macros(
          kcal: 100,
          protein: 10,
          carb: 20,
          fat: 5,
        ).scaledBy(2.5).fiber,
        isNull,
      );
    });

    test('per100From carries fibre through the derivation', () {
      final per100 = Macros.per100From(
        serving: 32,
        basis: MacrosBasis.perG,
        printed: const Macros(
          kcal: 180,
          protein: 6,
          carb: 10,
          fat: 14,
          fiber: 1.98,
        ),
      );
      expect(per100!.fiber, closeTo(6.1875, 1e-9));
      expect(
        Macros.per100From(
          serving: 32,
          basis: MacrosBasis.perG,
          printed: const Macros(kcal: 180, protein: 6, carb: 10, fat: 14),
        )!.fiber,
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
