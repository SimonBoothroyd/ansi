import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/macros.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/ingredients/domain/allowed_units.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';

Ingredient _ing(
  Unit defaultUnit, {
  double? density,
  String? category,
  MacrosBasis basis = MacrosBasis.perG,
  List<Unit>? allowed,
}) => Ingredient(
  id: 'i',
  canonicalName: 'thing',
  defaultUnit: defaultUnit,
  status: density == null ? IngredientStatus.stub : IngredientStatus.complete,
  densityGPerMl: density,
  category: category,
  macrosBasis: basis,
  allowedUnits: allowed,
);

void main() {
  group('allowedUnitsFor — ADR-0008 derived defaults (mirrors the pgTAP '
      'default_allowed_units vectors)', () {
    test('the yeast shape: tsp default /g — spoons + the basis base; no '
        'litres, no ml·l fronted, no universal pinch', () {
      final units = allowedUnitsFor(_ing(tsp, category: 'baking'));
      expect(units, [tsp, tbsp, g]);
    });

    test('the flour shape: cup default /g with density — kitchen volume + '
        'g AND kg (cup-scale justifies the big sibling)', () {
      final units = allowedUnitsFor(
        _ing(cup, density: 0.59, category: 'baking'),
      );
      expect(units, [cup, tbsp, ml, l, g, kg]);
    });

    test('the olive-oil shape: tbsp default /g oil — mates + g + gated '
        'imprecise', () {
      final units = allowedUnitsFor(
        _ing(tbsp, density: 0.91, category: 'fats & oils'),
      );
      expect(units, [tbsp, tsp, cup, ml, g, pinch, dash, handful, toTaste]);
    });

    test('the egg shape: count default /g — piece + basis base only', () {
      final units = allowedUnitsFor(_ing(pieces, category: 'produce'));
      expect(units, [pieces, g]);
    });

    test('the salt shape: the seasoning category admits the imprecise '
        'tail', () {
      final units = allowedUnitsFor(_ing(tsp, category: 'spices & seasoning'));
      expect(units, [tsp, tbsp, g, pinch, dash, handful, toTaste]);
    });

    test('an imprecise default keeps its whole tail + the basis base', () {
      final units = allowedUnitsFor(
        _ing(pinch, category: 'spices & seasoning'),
      );
      expect(units, [g, pinch, dash, handful, toTaste]);
    });

    test('a per-ml liquid: volume default IS the basis family — no gram '
        'leg without a density; with one, mass unlocks', () {
      expect(allowedUnitsFor(_ing(cup, basis: MacrosBasis.perMl)), [
        cup,
        tbsp,
        ml,
        l,
      ]);
      expect(
        allowedUnitsFor(_ing(cup, basis: MacrosBasis.perMl, density: 1.03)),
        [cup, tbsp, ml, l, g, kg],
      );
    });

    test('a mass default /g with density unlocks kitchen volume, after '
        'the default family', () {
      // Oats: grams AND cups are both honest — and the unlocked family
      // trails the default's own (the choice builder pushes it below the
      // measures too).
      final units = allowedUnitsFor(_ing(g, density: 0.4));
      expect(units, [g, kg, tsp, tbsp, cup, ml]);
      expect(units, isNot(contains(pieces)));
    });

    test('THE MANGO VECTOR (ADR-0008 as amended, plan 0020 D4): a piece '
        'default with a density admits the volume workhorses — "1 cup diced '
        'mango" is a real line', () {
      final units = allowedUnitsFor(
        _ing(pieces, density: 0.66, category: 'produce'),
      );
      expect(units, [pieces, g, tsp, tbsp, cup, ml]);
      // `kg` stays out: the big metric sibling rides the same magnitude gate
      // the mass/volume legs use, and a piece default is not big-scale. It is
      // the board frame's dashed chip.
      expect(units, isNot(contains(kg)));
      expect(units, isNot(contains(l)));
    });

    test('without a density a count default still admits nothing but its own '
        'piece and the basis base — the amendment unlocks on the density, '
        'not on the family', () {
      expect(allowedUnitsFor(_ing(pieces, category: 'produce')), [pieces, g]);
    });

    test('an imprecise default with a density unlocks both families too, and '
        'keeps its whole tail INCLUDING handful (the mirror divergence plan '
        '0020 D4 pins: the SQL leg was missing it)', () {
      final units = allowedUnitsFor(
        _ing(pinch, density: 1, category: 'spices & seasoning'),
      );
      expect(units, [g, tsp, tbsp, cup, ml, pinch, dash, handful, toTaste]);
    });

    test('mg and fl oz stay label-reading units: offered only as the '
        "default itself, never as anyone else's mate", () {
      expect(allowedUnitsFor(_ing(mg)), contains(mg));
      expect(allowedUnitsFor(_ing(flOz)), contains(flOz));
      for (final d in kAllUnits.where((u) => u != mg && u != flOz)) {
        final units = allowedUnitsFor(_ing(d, density: 1));
        expect(units, isNot(contains(mg)), reason: 'mg via ${d.id}');
        expect(units, isNot(contains(flOz)), reason: 'fl_oz via ${d.id}');
      }
    });

    test('always includes the default unit itself', () {
      for (final u in kAllUnits) {
        expect(allowedUnitsFor(_ing(u)), contains(u), reason: u.id);
      }
    });
  });

  group('allowedUnitsFor — the explicit list (0012) wins over the rule', () {
    test('an explicit list is honored verbatim as a set, in chip order', () {
      // A flesh-out-form edit ("this household says flour in cups and
      // grams only") must never be second-guessed by the derived rule.
      final units = allowedUnitsFor(
        _ing(cup, density: 0.59, allowed: const [g, cup, toTaste]),
      );
      expect(units, [cup, g, toTaste]);
    });

    test('ordering fronts the default and demotes the other family, '
        'whatever order the list arrived in', () {
      final units = allowedUnitsFor(
        _ing(tsp, allowed: const [kg, tbsp, g, tsp]),
      );
      expect(units, [tsp, tbsp, g, kg]);
    });

    test('an empty explicit list falls back to the derived defaults '
        '(a row must never render zero chips)', () {
      final units = allowedUnitsFor(_ing(tsp, allowed: const []));
      expect(units, [tsp, tbsp, g]);
    });
  });

  group('allowedUnitChoicesFor', () {
    const large = Measure(id: 'm1', label: 'potato, large', amount: 299);
    const medium = Measure(id: 'm2', label: 'potato, medium', amount: 213.5);

    test('slots measure options after the default set, before imprecise, '
        'in order', () {
      final choices = allowedUnitChoicesFor(_ing(pieces), const [
        medium,
        large,
      ]).choices;
      // The unit set keeps its members and relative order…
      expect(
        choices.whereType<UnitOption>().map((c) => c.unit),
        allowedUnitsFor(_ing(pieces)),
      );
      // …and the measures sit between the count and the demoted basis
      // base, in the given (sort_order) order.
      expect(choices.map((c) => c.label), [
        'piece',
        'potato, medium (213.5 g)',
        'potato, large (299 g)',
        'g',
      ]);
    });

    test('demoted other-family units trail the measures (ADR-0008)', () {
      // A density-unlocked family reads "after measures": default set →
      // measures → demoted units → imprecise.
      final choices = allowedUnitChoicesFor(_ing(g, density: 0.6), const [
        large,
      ]).choices;
      expect(
        choices.map(
          (c) => switch (c) {
            UnitOption(:final unit) => unit.id,
            MeasureOption(:final measure) => measure.label,
          },
        ),
        [
          'g', 'kg', // the default's own family leads
          'potato, large', // measures
          'tsp', 'tbsp', 'cup', 'ml', // density-unlocked, demoted
        ],
      );
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
      const cupish = Measure(id: 'mc', label: 'cup', amount: 226);
      const tbspish = Measure(id: 'mt', label: ' Tbsp ', amount: 15);
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
          amount: 300,
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
        const cupish = Measure(id: 'mc', label: 'cup', amount: 226);
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

  group("allowedUnitCandidates — the flesh-out form's admission chips", () {
    Set<String> lockedOf(Ingredient i) => {
      for (final c in allowedUnitCandidates(i))
        if (c.locked) c.unit.id,
    };
    Set<String> selectedOf(Ingredient i) => {
      for (final c in allowedUnitCandidates(i))
        if (c.selected) c.unit.id,
    };

    test('without a density the cross-family chips are drawn LOCKED, not '
        'hidden — the section has to explain what a density buys', () {
      final curryLeaves = _ing(g, category: 'produce');
      expect(selectedOf(curryLeaves), {'g', 'kg'});
      expect(lockedOf(curryLeaves), {'tsp', 'tbsp', 'cup', 'ml'});
    });

    test('a piece default with no density locks BOTH families beyond its own '
        'basis base — the D4 unlock is what opens them', () {
      final mangoWithoutDensity = _ing(pieces, category: 'produce');
      expect(selectedOf(mangoWithoutDensity), {'piece', 'g'});
      expect(lockedOf(mangoWithoutDensity), {'tsp', 'tbsp', 'cup', 'ml'});
    });

    test('with the density, nothing is locked (the mango frame)', () {
      final mango = _ing(pieces, density: 0.66, category: 'produce');
      expect(lockedOf(mango), isEmpty);
      expect(selectedOf(mango), {'piece', 'g', 'tsp', 'tbsp', 'cup', 'ml'});
    });

    test('a stored unit the derived rules would not admit still appears, '
        'selected and unlocked — an explicit list is user-owned', () {
      final curated = _ing(g, allowed: const [g, flOz, toTaste]);
      expect(selectedOf(curated), containsAll(<String>['fl_oz', 'to_taste']));
      expect(lockedOf(curated), isNot(contains('fl_oz')));
    });

    test('D4b: a stored list that still names the cross-family units draws '
        'them LOCKED once the density is gone — the number, not the list, '
        'says what is sayable', () {
      // The shape a device leaves behind when the density is deleted
      // somewhere the list did not follow (an older client, a server edit).
      final stale = _ing(pieces, allowed: const [pieces, g, cup, ml]);
      expect(lockedOf(stale), {'tsp', 'tbsp', 'cup', 'ml'});
      // …and the basis side is untouched: it never needed a density.
      expect(selectedOf(stale), {'piece', 'g'});
    });

    test('D4b: the basis family is never locked, whichever way the panel '
        'reads', () {
      final perMl = _ing(ml, basis: MacrosBasis.perMl);
      expect(lockedOf(perMl), {'g'});
      expect(selectedOf(perMl), containsAll(<String>['ml', 'l']));

      final perG = _ing(g);
      expect(lockedOf(perG), {'tsp', 'tbsp', 'cup', 'ml'});
      expect(selectedOf(perG), containsAll(<String>['g']));
    });
  });

  group('densityStrippedUnits — what deleting a density takes back (D4b)', () {
    test('the mango shape: the volume leg goes, piece and the basis base '
        'stay', () {
      final mango = _ing(pieces, density: 0.66, category: 'produce');
      expect(densityStrippedUnits(mango), {tsp, tbsp, cup, ml});
      expect(densityStrippedUnits(mango), isNot(contains(g)));
      expect(densityStrippedUnits(mango), isNot(contains(pieces)));
    });

    test('the flour shape strips NOTHING: mass is its basis family, so it '
        'was admitted with or without the density', () {
      final flour = _ing(cup, density: 0.59, category: 'baking');
      expect(densityStrippedUnits(flour), isEmpty);
    });

    test('the milk shape: a per-ml row loses g, keeps every volume unit', () {
      final milk = _ing(ml, density: 1.03, basis: MacrosBasis.perMl);
      expect(densityStrippedUnits(milk), {g});
    });

    test('what is stripped is exactly what a density adds — the two are one '
        'rule read in opposite directions', () {
      for (final i in [
        _ing(pieces, density: 0.66),
        _ing(g, density: 0.5),
        _ing(cup, density: 0.59),
        _ing(ml, density: 1.03, basis: MacrosBasis.perMl),
        _ing(toTaste, density: 0.9, category: 'spices & seasoning'),
      ]) {
        final withDensity = defaultAllowedUnitSet(i);
        expect(
          withDensity.difference(densityStrippedUnits(i)),
          allowedUnitsFor(i).toSet().difference(densityStrippedUnits(i)),
          reason: i.defaultUnit.id,
        );
        // Nothing stripped is ever something the basis leg supplies.
        expect(
          densityStrippedUnits(i).contains(i.macrosBasis.baseUnit),
          isFalse,
          reason: i.defaultUnit.id,
        );
      }
    });
  });
}
