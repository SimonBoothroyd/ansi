import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/serving_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a spoon with a mass serving is a density, per spoon', () {
    final one =
        servingOfferFor(amount: 14, name: '1 tbsp', basis: MacrosBasis.perG)!
            as DensityOffer;
    expect(one.unit, tbsp);
    expect(one.gramsPerUnit, 14);
    expect(one.gPerMl, closeTo(14 / tbsp.ratioToBase!, 1e-9));

    // "2 Tbsp = 32 g" — per spoon, the way the pack's own line reads.
    final two =
        servingOfferFor(amount: 32, name: '2 Tbsp', basis: MacrosBasis.perG)!
            as DensityOffer;
    expect(two.gramsPerUnit, 16);
    expect(two.gPerMl, closeTo(16 / tbsp.ratioToBase!, 1e-9));
  });

  test('a spoon with a VOLUME serving is a volume of itself — no offer', () {
    expect(
      servingOfferFor(amount: 14, name: '1 tbsp', basis: MacrosBasis.perMl),
      isNull,
    );
  });

  test('a thing is a measure of one, and only of one', () {
    final slice =
        servingOfferFor(amount: 28, name: 'slice', basis: MacrosBasis.perG)!
            as MeasureOffer;
    expect(slice.label, 'slice');
    expect(slice.amount, 28);
    expect(slice.basis, MacrosBasis.perG);

    // A count above one would need a singular nobody typed.
    expect(
      servingOfferFor(amount: 56, name: '2 slices', basis: MacrosBasis.perG),
      isNull,
    );
  });

  test('half an answer is no answer — a weight or a name alone offers '
      'nothing', () {
    expect(
      servingOfferFor(amount: 14, name: '', basis: MacrosBasis.perG),
      isNull,
    );
    expect(
      servingOfferFor(amount: null, name: '1 tbsp', basis: MacrosBasis.perG),
      isNull,
    );
    expect(
      servingOfferFor(amount: 14, name: '0 tbsp', basis: MacrosBasis.perG),
      isNull,
    );
  });
}
