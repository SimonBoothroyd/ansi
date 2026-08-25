import 'package:flutter_test/flutter_test.dart';

// When the unit system lands (roadmap step 1), import it and remove the skip.
// import 'package:mise/core/units/units.dart';

void main() {
  group('unit system', () {
    // These describe the intended behaviour up front (spec §4). They're skipped
    // until step 1 implements `lib/core/units/units.dart`. Golden values here are
    // pre-verified, so implementing to make them pass is safe.
    test('converts within a family (1 kg == 1000 g)', () {
      // expect(convert(Quantity(1, kg), to: g).valueOrNull?.amount, 1000);
    }, skip: 'roadmap step 1 — unit system not implemented yet');

    test('converts volume↔mass via density (600 ml @1.02 == 612 g)', () {
      // expect(convert(Quantity(600, ml), to: g, densityGPerMl: 1.02)
      //     .valueOrNull?.amount, closeTo(612, 1e-6));
    }, skip: 'roadmap step 1 — unit system not implemented yet');

    test('leaves imprecise units unchanged under scaling', () {
      // expect(scale(Quantity(1, toTaste), 2), Quantity(1, toTaste));
    }, skip: 'roadmap step 1 — unit system not implemented yet');

    test('fails cross-family conversion without a density', () {
      // expect(convert(Quantity(2, pieces), to: g).isOk, isFalse);
    }, skip: 'roadmap step 1 — unit system not implemented yet');
  });
}
