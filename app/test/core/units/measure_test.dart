import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const potatoLarge = Measure(id: 'm1', label: 'potato, large', amount: 299);
  const can400 = Measure(id: 'm2', label: 'can (400 ml)', amount: 400);

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
        final bad = Measure(id: 'm', label: 'bad', amount: grams);
        final r = convertMeasure(2, bad, to: g);
        expect(r.isOk, isFalse, reason: 'grams = $grams');
        expect((r as Err).failure.code, 'measure/invalid_amount');
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
      const bad = Measure(id: 'm', label: 'bad', amount: 0);
      final r = amountInMeasure(Quantity(100, g), bad);
      expect(r.isOk, isFalse);
      expect((r as Err).failure.code, 'measure/invalid_amount');
    });
  });

  group('sourceKind (7.7 humanized provenance)', () {
    Measure withSource(String? source) =>
        Measure(id: 'm', label: 'x', amount: 1, source: source);

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
      const Measure(id: 'm1', label: 'potato, large', amount: 299),
    );
    expect(
      potatoLarge,
      isNot(const Measure(id: 'm1', label: 'potato, large', amount: 300)),
    );
  });

  group('basis-aware measures (ADR-0008, 0012)', () {
    // A per-ml ingredient's measure maps to VOLUME: "can (400 ml) = 400 ml".
    const can = Measure(
      id: 'm-can',
      label: 'can (400 ml)',
      amount: 400,
      basis: MacrosBasis.perMl,
    );

    test('a per-ml measure converts to volume without a density', () {
      final r = convertMeasure(0.5, can, to: ml);
      expect(r, Ok(Quantity(200, ml)));
      final cups = convertMeasure(1, can, to: cup);
      expect((cups as Ok<Quantity>).value.amount, closeTo(1.69, 0.01));
    });

    test('a per-ml measure reaches mass only via the density', () {
      expect(
        (convertMeasure(1, can, to: g) as Err).failure.code,
        'unit/no_density',
      );
      final r = convertMeasure(1, can, to: g, densityGPerMl: 1.03);
      expect((r as Ok<Quantity>).value.amount, closeTo(412, 0.001));
    });

    test('amountInMeasure inverts within the basis family', () {
      final r = amountInMeasure(Quantity(600, ml), can);
      expect(r, const Ok(1.5));
      // …and needs a density to cross from mass.
      expect(
        (amountInMeasure(Quantity(412, g), can) as Err).failure.code,
        'unit/no_density',
      );
      expect(
        amountInMeasure(Quantity(412, g), can, densityGPerMl: 1.03),
        const Ok<double>(1),
      );
    });

    test('the default basis stays per-g (every pre-0012 caller)', () {
      const clove = Measure(id: 'm', label: 'clove', amount: 3);
      expect(clove.basis, MacrosBasis.perG);
      expect(convertMeasure(2, clove, to: g), Ok(Quantity(6, g)));
    });
  });
}
