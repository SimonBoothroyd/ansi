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
      ]).choices;
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
      final choices = allowedUnitChoicesFor(_ing(pieces), const [
        large,
      ]).choices;
      expect(choices.whereType<MeasureOption>(), hasLength(1));
    });

    test('no measures → exactly the unit set as choices', () {
      final choices = allowedUnitChoicesFor(_ing(g), const []).choices;
      expect(choices.whereType<MeasureOption>(), isEmpty);
      expect(choices, isNotEmpty);
    });

    test('labels measures with their gram weight, trimming whole grams', () {
      expect(const MeasureOption(large).label, 'potato, large (299 g)');
      expect(const MeasureOption(medium).label, 'potato, medium (213.5 g)');
      expect(const UnitOption(kg).label, 'kg');
    });

    test('a measure that merely names a volume unit is never offered', () {
      // Density owns volume conversion (frame-b review, 0011): a "cup"/"tbsp"
      // measure would shadow the honest unit set.
      const cupish = Measure(id: 'mc', label: 'cup', grams: 226);
      const tbspish = Measure(id: 'mt', label: ' Tbsp ', grams: 15);
      final choices = allowedUnitChoicesFor(_ing(g), const [
        cupish,
        tbspish,
        large,
      ]).choices;
      expect(choices.whereType<MeasureOption>().map((c) => c.measure), [large]);
    });

    group("the stored selection is always offered (the dropdowns' rule)", () {
      test('a current choice inside the set is neither duplicated nor '
          'flagged', () {
        final offer = allowedUnitChoicesFor(_ing(g), const [
          large,
        ], current: const UnitOption(kg));
        expect(offer.offFilter, isNull);
        expect(offer.choices.where((c) => c == const UnitOption(kg)), [
          const UnitOption(kg),
        ]);
      });

      test('a merge-hidden duplicate measure is admitted and flagged', () {
        // The line references a duplicate-label measure the merge-on-read
        // hid: it must stay reachable (and returnable after tapping another
        // chip), styled as outside the filter — never an orphaned value.
        const hidden = Measure(
          id: 'm-dupe',
          label: 'potato, large',
          grams: 300,
        );
        final offer = allowedUnitChoicesFor(_ing(pieces), const [
          large,
        ], current: const MeasureOption(hidden));
        expect(offer.offFilter, const MeasureOption(hidden));
        expect(offer.choices.last, const MeasureOption(hidden));
        // The honest set is untouched ahead of it.
        expect(
          offer.choices.whereType<MeasureOption>().map((c) => c.measure.id),
          ['m1', 'm-dupe'],
        );
      });

      test('a stored unit outside the honest set is admitted and flagged', () {
        // e.g. a cup line whose ingredient lost (or never had) a density:
        // the filter would drop volume, but the stored value must survive.
        final offer = allowedUnitChoicesFor(
          _ing(g),
          const [],
          current: const UnitOption(cup),
        );
        expect(offer.offFilter, const UnitOption(cup));
        expect(offer.choices.last, const UnitOption(cup));
      });

      test('a volume-named measure that IS the stored selection stays '
          'offered', () {
        // Excluded from the filter, admitted as current — reachable but
        // flagged, so the line can still be moved off it deliberately.
        const cupish = Measure(id: 'mc', label: 'cup', grams: 226);
        final offer = allowedUnitChoicesFor(_ing(g), const [
          cupish,
        ], current: const MeasureOption(cupish));
        expect(offer.offFilter, const MeasureOption(cupish));
      });

      test('no current → no off-filter admission', () {
        final offer = allowedUnitChoicesFor(_ing(g), const [large]);
        expect(offer.offFilter, isNull);
      });
    });
  });

  group('isVolumeUnitLabel', () {
    test('matches catalog volume unit ids and labels, case-insensitively', () {
      for (final label in ['cup', 'tbsp', 'TSP', 'ml', 'l', 'fl oz', 'fl_oz']) {
        expect(isVolumeUnitLabel(label), isTrue, reason: label);
      }
    });

    test('sees through whitespace and the simple s plural', () {
      for (final label in [' Cups ', 'tbsps', 'TSPS', 'mls', ' litre'.trim()]) {
        // 'litre' is NOT a catalog name — only real ids/labels match.
        final expected = label.trim().toLowerCase() != 'litre';
        expect(isVolumeUnitLabel(label), expected, reason: label);
      }
    });

    test('leaves real-world measure labels alone', () {
      for (final label in ['can (400 ml)', 'half cup scoop', 'clove', 'oz']) {
        expect(isVolumeUnitLabel(label), isFalse, reason: label);
      }
    });
  });
}
