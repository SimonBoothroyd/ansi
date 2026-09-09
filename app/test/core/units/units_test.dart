import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convert', () {
    test('within a family via the ratio table (1 kg == 1000 g)', () {
      expect(convert(Quantity(1, kg), to: g).valueOrNull?.amount, 1000);
    });

    test('is exact both ways within volume (2 tbsp == 1 fl oz)', () {
      expect(
        convert(Quantity(2, tbsp), to: flOz).valueOrNull?.amount,
        closeTo(1, 1e-9),
      );
    });

    test('pint and quart are exact US customary', () {
      // Both are defined off the US gallon like every other volume entry:
      // 1 qt = 2 pt = 4 cup = 946.352946 ml, 1 pt = 473.176473 ml.
      expect(
        convert(Quantity(1, quart), to: ml).valueOrNull?.amount,
        946.352946,
      );
      expect(
        convert(Quantity(1, pint), to: ml).valueOrNull?.amount,
        473.176473,
      );
      expect(
        convert(Quantity(1, quart), to: pint).valueOrNull?.amount,
        closeTo(2, 1e-9),
      );
      expect(
        convert(Quantity(1, quart), to: cup).valueOrNull?.amount,
        closeTo(4, 1e-9),
      );
      expect(
        convert(Quantity(1, pint), to: cup).valueOrNull?.amount,
        closeTo(2, 1e-9),
      );
    });

    test('volume→mass via density (600 ml @1.02 == 612 g)', () {
      final r = convert(Quantity(600, ml), to: g, densityGPerMl: 1.02);
      expect(r.valueOrNull?.amount, closeTo(612, 1e-6));
    });

    test('mass→volume via density (100 g @1.42 == 70.42 ml)', () {
      final r = convert(Quantity(100, g), to: ml, densityGPerMl: 1.42);
      expect(r.valueOrNull?.amount, closeTo(70.4225, 1e-4));
    });

    test('same unit is an identity (no density needed)', () {
      expect(convert(Quantity(5, g), to: g).valueOrNull?.amount, 5);
    });

    test('fails mass↔volume without a density', () {
      final r = convert(Quantity(600, ml), to: g);
      expect(r.isOk, isFalse);
      expect((r as Err).failure.code, 'unit/no_density');
    });

    test('treats a non-positive density exactly like no density', () {
      // A zero density would fabricate numbers: g→ml divides (Infinity), ml→g
      // multiplies (0 g). Both must be the honest `unit/no_density` failure,
      // never an invented quantity (invariant 3).
      for (final density in [0.0, -1.0, double.nan]) {
        final gToMl = convert(Quantity(100, g), to: ml, densityGPerMl: density);
        expect(gToMl.isOk, isFalse, reason: 'g→ml @ $density');
        expect((gToMl as Err).failure.code, 'unit/no_density');

        final mlToG = convert(Quantity(100, ml), to: g, densityGPerMl: density);
        expect(mlToG.isOk, isFalse, reason: 'ml→g @ $density');
        expect((mlToG as Err).failure.code, 'unit/no_density');
      }
    });

    test('fails cross-family conversion (count → mass)', () {
      final r = convert(Quantity(2, pieces), to: g);
      expect(r.isOk, isFalse);
      expect((r as Err).failure.code, 'unit/incompatible');
    });

    test('refuses to convert imprecise units', () {
      final r = convert(Quantity(1, toTaste), to: g, densityGPerMl: 1);
      expect(r.isOk, isFalse);
      expect((r as Err).failure.code, 'unit/imprecise');
    });
  });

  group('scale', () {
    test('multiplies precise amounts', () {
      expect(scale(Quantity(200, g), 2.5), Quantity(500, g));
    });

    test('leaves imprecise units unchanged', () {
      expect(scale(Quantity(1, toTaste), 2), Quantity(1, toTaste));
      expect(scale(Quantity(1, pinch), 10), Quantity(1, pinch));
    });
  });

  group('catalog', () {
    test('unitById round-trips a persisted id', () {
      expect(unitById('tbsp'), tbsp);
      expect(unitById('nope'), isNull);
    });

    test('pt and qt are catalogue ids, ordered after cup in the volume '
        'block', () {
      expect(unitById('pt'), pint);
      expect(unitById('qt'), quart);
      expect(pint.family, UnitFamily.volume);
      expect(quart.family, UnitFamily.volume);
      final volume = kIngredientUnits
          .where((u) => u.family == UnitFamily.volume)
          .toList();
      expect(volume, [ml, l, tsp, tbsp, flOz, cup, pint, quart]);
    });
  });

  group('densityFromVolumeWeight (the spoon-mapping entry, ADR-0008)', () {
    test('1 tbsp = 15 g is the canonical example', () {
      expect(densityFromVolumeWeight(tbsp, 15), closeTo(15 / 14.787, 0.001));
    });

    test('every spoon phrasing resolves to the same stored fact', () {
      // 1 cup of water weighs 236.59 g → 1.0 g/ml, same as 1 tsp = 4.93 g.
      expect(densityFromVolumeWeight(cup, 236.5882365), closeTo(1, 1e-9));
      expect(densityFromVolumeWeight(tsp, 4.92892159375), closeTo(1, 1e-9));
    });

    test('non-volume units and non-positive weights yield null, never a '
        'number', () {
      expect(densityFromVolumeWeight(g, 15), isNull);
      expect(densityFromVolumeWeight(pieces, 15), isNull);
      expect(densityFromVolumeWeight(tbsp, 0), isNull);
      expect(densityFromVolumeWeight(tbsp, -1), isNull);
      expect(densityFromVolumeWeight(tbsp, double.nan), isNull);
    });
  });

  group('volumeWeightFromDensity (reading a stored density back)', () {
    test('it is the exact inverse of the entry', () {
      for (final u in [tsp, tbsp, cup, ml]) {
        final gPerMl = densityFromVolumeWeight(u, 15)!;
        expect(volumeWeightFromDensity(u, gPerMl), closeTo(15, 1e-9));
      }
    });

    test('water is a cup of 236.59 g', () {
      expect(volumeWeightFromDensity(cup, 1), closeTo(236.5882365, 1e-6));
      expect(volumeWeightFromDensity(ml, 0.66), closeTo(0.66, 1e-9));
    });

    test('non-volume units and non-positive densities yield null, never a '
        'number', () {
      expect(volumeWeightFromDensity(g, 1), isNull);
      expect(volumeWeightFromDensity(pieces, 1), isNull);
      expect(volumeWeightFromDensity(cup, 0), isNull);
      expect(volumeWeightFromDensity(cup, -1), isNull);
      expect(volumeWeightFromDensity(cup, double.nan), isNull);
    });
  });
}
