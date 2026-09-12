/// Pins scenario 5's inlined Open Food Facts payload to the committed unit
/// fixture it was copied from.
///
/// The integration test cannot read a host path (it runs on the device), so
/// the fixture is duplicated as a Dart const. Duplication without a pin is how
/// two mirrors drift: re-capture the OFF fixture, and the on-sim scenario goes
/// on asserting the old numbers. This test is the pin.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/off_fixture.dart';

void main() {
  test('scenario 5 serves exactly the committed Nutella fixture', () {
    final committed = jsonDecode(
      File(
        'test/features/ingredients/barcode/fixtures/'
        'nutella_per_100g.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final inlined = jsonDecode(offNutellaFixtureJson) as Map<String, Object?>;

    expect(
      inlined,
      committed,
      reason:
          'integration_test/off_fixture.dart has drifted from the committed '
          'fixture — copy the JSON across again',
    );
    expect(committed['code'], offFixtureBarcode);
  });
}
