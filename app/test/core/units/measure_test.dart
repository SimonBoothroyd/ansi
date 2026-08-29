import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/result/result.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';

void main() {
  const potatoLarge = Measure(id: 'm1', label: 'potato, large', grams: 299);
  const can400 = Measure(id: 'm2', label: 'can (400 ml)', grams: 400);

  group('convertMeasure', () {
    test('to mass via the gram weight (2 × 299 g == 598 g)', () {
      final r = convertMeasure(2, potatoLarge, to: g);
      expect(r.valueOrNull?.amount, 598);
      expect(r.valueOrNull?.unit, g);
    });

    test('to a non-base mass unit via the ratio table (2 × 299 g in kg)', () {
      final r = convertMeasure(2, potatoLarge, to: kg);
      expect(r.valueOrNull?.amount, closeTo(0.598, 1e-9));
    });

    test('scales fractional amounts (½ can == 200 g)', () {
      expect(convertMeasure(0.5, can400, to: g).valueOrNull?.amount, 200);
    });

    test('to volume only with a density (mass→volume rule unchanged)', () {
      final without = convertMeasure(1, can400, to: ml);
      expect(without.isOk, isFalse);
      expect((without as Err).failure.code, 'unit/no_density');

      final with_ = convertMeasure(1, can400, to: ml, densityGPerMl: 1);
      expect(with_.valueOrNull?.amount, closeTo(400, 1e-9));
    });

    test('never bridges to count or imprecise', () {
      for (final to in [pieces, pinch]) {
        final r = convertMeasure(1, potatoLarge, to: to);
        expect(r.isOk, isFalse, reason: 'to ${to.id}');
      }
    });

    test('rejects a non-positive or NaN gram weight (invariant 3)', () {
      // Multiplying by 0/-1/NaN grams would fabricate a total, exactly like a
      // bad density would — the same honest refusal applies.
      for (final grams in [0.0, -299.0, double.nan]) {
        final bad = Measure(id: 'm', label: 'bad', grams: grams);
        final r = convertMeasure(2, bad, to: g);
        expect(r.isOk, isFalse, reason: 'grams = $grams');
        expect((r as Err).failure.code, 'measure/invalid_grams');
      }
    });
  });

  group('amountInMeasure', () {
    test('mass → measure count (674 g ≈ 2.254 potatoes)', () {
      final r = amountInMeasure(Quantity(674, g), potatoLarge);
      expect(r.valueOrNull, closeTo(674 / 299, 1e-9));
    });

    test('handles non-base mass units (0.598 kg == 2 potatoes)', () {
      final r = amountInMeasure(Quantity(0.598, kg), potatoLarge);
      expect(r.valueOrNull, closeTo(2, 1e-9));
    });

    test('volume → measure count only with a density', () {
      final without = amountInMeasure(Quantity(800, ml), can400);
      expect(without.isOk, isFalse);
      expect((without as Err).failure.code, 'unit/no_density');

      final with_ = amountInMeasure(
        Quantity(800, ml),
        can400,
        densityGPerMl: 1,
      );
      expect(with_.valueOrNull, closeTo(2, 1e-9));
    });

    test('count and imprecise quantities never resolve into a measure', () {
      for (final q in [Quantity(2, pieces), Quantity(1, pinch)]) {
        final r = amountInMeasure(q, potatoLarge);
        expect(r.isOk, isFalse, reason: 'from ${q.unit.id}');
      }
    });

    test('rejects a non-positive gram weight before converting', () {
      const bad = Measure(id: 'm', label: 'bad', grams: 0);
      final r = amountInMeasure(Quantity(100, g), bad);
      expect(r.isOk, isFalse);
      expect((r as Err).failure.code, 'measure/invalid_grams');
    });
  });

  group('sourceKind (7.7 humanized provenance)', () {
    Measure withSource(String? source) =>
        Measure(id: 'm', label: 'x', grams: 1, source: source);

    test('classifies each provenance family', () {
      expect(
        withSource('usda_fdc:170172 (1 packet)').sourceKind,
        MeasureSourceKind.usdaPortion,
      );
      expect(
        withSource('usda_fdc:170171 (1 cup) — borrowed').sourceKind,
        MeasureSourceKind.borrowed,
      );
      expect(withSource('seed:typical').sourceKind, MeasureSourceKind.typical);
      expect(withSource('manual').sourceKind, MeasureSourceKind.manual);
    });

    test('null and unrecognized strings are unknown', () {
      expect(withSource(null).sourceKind, MeasureSourceKind.unknown);
      expect(withSource('mystery').sourceKind, MeasureSourceKind.unknown);
    });
  });

  test('Measure is value-equal on all fields', () {
    expect(
      potatoLarge,
      const Measure(id: 'm1', label: 'potato, large', grams: 299),
    );
    expect(
      potatoLarge,
      isNot(const Measure(id: 'm1', label: 'potato, large', grams: 300)),
    );
  });
}
