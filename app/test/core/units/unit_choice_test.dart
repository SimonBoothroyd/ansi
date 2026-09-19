import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnitOption', () {
    test('labels itself as the catalog does, and is value-equal', () {
      expect(const UnitOption(cup).label, 'cup');
      expect(const UnitOption(flOz).label, 'fl oz');
      expect(const UnitOption(g), const UnitOption(g));
      expect(const UnitOption(g), isNot(const UnitOption(kg)));
    });
  });

  group('MeasureOption', () {
    const potato = Measure(id: 'm1', label: 'potato, large', amount: 299);

    test('says what one comes to, in the basis unit of the row', () {
      expect(const MeasureOption(potato).label, 'potato, large (299 g)');
      expect(
        const MeasureOption(
          Measure(
            id: 'm2',
            label: 'can (400 ml)',
            amount: 400,
            basis: MacrosBasis.perMl,
          ),
        ).label,
        'can (400 ml) (400 ml)',
      );
    });

    test('identity is the row, not the words on it', () {
      // The label follows a rename; the chip a stored line reopens on must
      // not, or an edit to the word would orphan every line saying it.
      expect(
        const MeasureOption(potato),
        const MeasureOption(Measure(id: 'm1', label: 'spud', amount: 1)),
      );
      expect(
        const MeasureOption(potato),
        isNot(
          const MeasureOption(
            Measure(id: 'm2', label: 'potato, large', amount: 299),
          ),
        ),
      );
    });
  });

  test('a choice is one of the sealed kinds — a switch stays exhaustive', () {
    String kindOf(UnitChoice choice) => switch (choice) {
      UnitOption() => 'unit',
      MeasureOption() => 'measure',
    };
    expect(kindOf(const UnitOption(g)), 'unit');
    expect(
      kindOf(const MeasureOption(Measure(id: 'm', label: 'clove', amount: 3))),
      'measure',
    );
  });
}
