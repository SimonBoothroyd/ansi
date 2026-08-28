import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/ingredients/domain/allowed_units.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';

Ingredient _ing(Unit defaultUnit, {double? density}) => Ingredient(
  id: 'i',
  canonicalName: 'thing',
  defaultUnit: defaultUnit,
  status: density == null ? IngredientStatus.stub : IngredientStatus.complete,
  densityGPerMl: density,
);

void main() {
  group('allowedUnitsFor', () {
    test('mass default without density: mass + imprecise only', () {
      final units = allowedUnitsFor(_ing(g));
      expect(units, [g, kg, mg, oz, lb, pinch, dash, toTaste]);
    });

    test('volume default without density: volume + imprecise only', () {
      final units = allowedUnitsFor(_ing(cup));
      expect(units, [ml, l, tsp, tbsp, flOz, cup, pinch, dash, toTaste]);
    });

    test('a density opens the mass↔volume boundary', () {
      // Oats with a density: grams AND cups are both honest.
      final units = allowedUnitsFor(_ing(g, density: 0.4));
      expect(units, [
        g, kg, mg, oz, lb, //
        ml, l, tsp, tbsp, flOz, cup, //
        pinch, dash, toTaste,
      ]);
      expect(units, isNot(contains(pieces)));
    });

    test('count default offers only count + imprecise', () {
      final units = allowedUnitsFor(_ing(pieces));
      expect(units, [pieces, pinch, dash, toTaste]);
    });

    test('count default ignores density — count never converts', () {
      final units = allowedUnitsFor(_ing(pieces, density: 1));
      expect(units, [pieces, pinch, dash, toTaste]);
    });

    test('always includes the default unit itself', () {
      for (final u in kAllUnits) {
        expect(allowedUnitsFor(_ing(u)), contains(u), reason: u.id);
      }
    });

    test('preserves kAllUnits order', () {
      final units = allowedUnitsFor(_ing(ml, density: 1.03));
      final indices = units.map(kAllUnits.indexOf).toList();
      expect(indices, [...indices]..sort());
    });
  });
}
