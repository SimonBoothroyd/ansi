import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/result/result.dart';
import 'package:mise/core/units/units.dart';

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
  });
}
