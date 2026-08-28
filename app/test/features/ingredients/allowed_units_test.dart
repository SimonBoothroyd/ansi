import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/measure.dart';
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

  group('allowedUnitChoicesFor', () {
    const large = Measure(id: 'm1', label: 'potato, large', grams: 299);
    const medium = Measure(id: 'm2', label: 'potato, medium', grams: 213.5);

    test('appends measure options after the honest unit set, in order', () {
      final choices = allowedUnitChoicesFor(_ing(pieces), const [
        medium,
        large,
      ]);
      // The unit set is unchanged and keeps its positions…
      expect(
        choices.whereType<UnitOption>().map((c) => c.unit),
        allowedUnitsFor(_ing(pieces)),
      );
      // …and the measures follow, in the given (sort_order) order.
      expect(choices.whereType<MeasureOption>().map((c) => c.measure), [
        medium,
        large,
      ]);
      expect(choices.last, const MeasureOption(large));
    });

    test('offers a count food its measures despite having no density', () {
      // The whole point of measures: count foods reach mass without one.
      final choices = allowedUnitChoicesFor(_ing(pieces), const [large]);
      expect(choices.whereType<MeasureOption>(), hasLength(1));
    });

    test('no measures → exactly the unit set as choices', () {
      final choices = allowedUnitChoicesFor(_ing(g), const []);
      expect(choices.whereType<MeasureOption>(), isEmpty);
      expect(choices, isNotEmpty);
    });

    test('labels measures with their gram weight, trimming whole grams', () {
      expect(const MeasureOption(large).label, 'potato, large (299 g)');
      expect(const MeasureOption(medium).label, 'potato, medium (213.5 g)');
      expect(const UnitOption(kg).label, 'kg');
    });
  });
}
