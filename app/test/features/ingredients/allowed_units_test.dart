import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

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
    test('THE YEAST SHAPE: tsp default /g with NO density admits the basis '
        'base and nothing else — being sold by the spoon does not make spoons '
        'convertible', () {
      final units = allowedUnitsFor(_ing(tsp, category: 'baking'));
      expect(units, [g]);
      // Before D4c this read [tsp, tbsp, g]: the default unit's own family
      // was an admission source, so a row could offer a unit no number on it
      // could resolve. A density is what buys the spoons back.
      expect(allowedUnitsFor(_ing(tsp, density: 0.4, category: 'baking')), [
        tsp,
        tbsp,
        g,
      ]);
    });

    test('the flour shape: cup default /g with density — kitchen volume + g '
        'AND kg (cup-scale justifies the big sibling)', () {
      final units = allowedUnitsFor(
        _ing(cup, density: 0.59, category: 'baking'),
      );
      expect(units, [cup, tbsp, ml, l, pint, quart, g, kg]);
    });

    test('the olive-oil shape: tbsp default /g oil — mates + g + the oil class '
        'imprecise words (no handful of oil)', () {
      final units = allowedUnitsFor(
        _ing(tbsp, density: 0.91, category: 'fats & oils'),
      );
      expect(units, [tbsp, tsp, cup, ml, pint, g, pinch, dash, toTaste]);
      expect(units, isNot(contains(handful)));
    });

    test('the egg shape: count default /g — piece + basis base, and produce '
        'earns handful and nothing else', () {
      final units = allowedUnitsFor(_ing(pieces, category: 'produce'));
      expect(units, [pieces, g, handful]);
      expect(units, isNot(contains(pinch)));
      expect(units, isNot(contains(dash)));
    });

    test('the salt shape: the seasoning category admits the whole tail — which '
        'the density rule leaves alone, being no part of the mass⇄volume '
        'duality', () {
      final units = allowedUnitsFor(_ing(tsp, category: 'spices & seasoning'));
      expect(units, [g, pinch, dash, handful, toTaste]);
    });

    test('an imprecise default keeps its whole tail + the basis base', () {
      final units = allowedUnitsFor(
        _ing(pinch, category: 'spices & seasoning'),
      );
      expect(units, [g, pinch, dash, handful, toTaste]);
    });

    test('a per-ml liquid: volume default IS the basis family — no gram leg '
        'without a density; with one, mass unlocks', () {
      expect(allowedUnitsFor(_ing(cup, basis: MacrosBasis.perMl)), [
        cup,
        tbsp,
        ml,
        l,
        pint,
        quart,
      ]);
      expect(
        allowedUnitsFor(_ing(cup, basis: MacrosBasis.perMl, density: 1.03)),
        [cup, tbsp, ml, l, pint, quart, g, kg],
      );
    });

    test('a mass default /g with density unlocks kitchen volume, after the '
        'default family', () {
      // Oats: grams AND cups are both honest — and the unlocked family
      // trails the default's own (the choice builder pushes it below the
      // measures too).
      final units = allowedUnitsFor(_ing(g, density: 0.4));
      expect(units, [g, kg, tsp, tbsp, cup, ml, pint]);
      expect(units, isNot(contains(pieces)));
    });

    test(
      'THE MANGO VECTOR (ADR-0008 as amended): a piece default with a density '
      'admits the volume workhorses — "1 cup diced mango" is a real line',
      () {
        final units = allowedUnitsFor(
          _ing(pieces, density: 0.66, category: 'produce'),
        );
        expect(units, [pieces, g, tsp, tbsp, cup, ml, pint, handful]);
        // `kg` stays out: the big metric sibling rides the same magnitude gate
        // the mass/volume legs use, and a piece default is not big-scale. It is
        // the board frame's dashed chip. `qt` rides with `l`, so it stays out
        // with it (D2b); `pt` rides with `cup`, so it came in.
        expect(units, isNot(contains(kg)));
        expect(units, isNot(contains(l)));
        expect(units, isNot(contains(quart)));
      },
    );

    test('without a density a count default still admits nothing but its own '
        'piece and the basis base — the amendment unlocks on the density, not '
        'on the family', () {
      expect(allowedUnitsFor(_ing(pieces, category: 'produce')), [
        pieces,
        g,
        handful, // J3: the category's word, not the density's business
      ]);
    });

    test('an imprecise default with a density unlocks both families too, and '
        'keeps its whole tail INCLUDING handful (the mirror divergence: the '
        'SQL leg was missing it)', () {
      final units = allowedUnitsFor(
        _ing(pinch, density: 1, category: 'spices & seasoning'),
      );
      expect(units, [
        g,
        tsp,
        tbsp,
        cup,
        ml,
        pint,
        pinch,
        dash,
        handful,
        toTaste,
      ]);
    });

    group('pint and quart — quart rides with litre, pint rides with cup', () {
      test('the broth shape: a cup default admits a pint, and a quart with it '
          '— "1 quart broth" lands on a chip', () {
        final broth = allowedUnitsFor(
          _ing(cup, basis: MacrosBasis.perMl, category: 'pantry'),
        );
        expect(broth, containsAll(<Unit>[pint, quart]));
        // …behind the metric jugs in chip order, never fronted over them.
        expect(broth, [cup, tbsp, ml, l, pint, quart]);
      });

      test('a litre default admits a quart', () {
        expect(allowedUnitsFor(_ing(l, basis: MacrosBasis.perMl)), [
          l,
          cup,
          ml,
          pint,
          quart,
        ]);
      });

      test('a spoon default admits neither — no quarts of yeast', () {
        for (final i in [
          _ing(tsp, basis: MacrosBasis.perMl),
          _ing(tsp, density: 0.4),
          _ing(tbsp, basis: MacrosBasis.perMl),
        ]) {
          final units = allowedUnitsFor(i);
          expect(units, isNot(contains(quart)), reason: i.defaultUnit.id);
          // tbsp's mates name cup, so a pint rides in there — tsp's do not.
          expect(
            units.contains(pint),
            i.defaultUnit == tbsp,
            reason: i.defaultUnit.id,
          );
        }
      });

      test('the pair as defaults: one rung each side, and both pass the big '
          'gate', () {
        expect(allowedUnitsFor(_ing(quart, basis: MacrosBasis.perMl)), [
          quart,
          cup,
          ml,
          l,
          pint,
        ]);
        expect(allowedUnitsFor(_ing(pint, basis: MacrosBasis.perMl)), [
          pint,
          cup,
          ml,
          quart,
        ]);
        // Per-g with a density: the basis leg brings kg because a pint is
        // cup-scale and a quart litre-scale.
        expect(allowedUnitsFor(_ing(pint, density: 1)), [
          pint,
          cup,
          ml,
          quart,
          g,
          kg,
        ]);
        expect(allowedUnitsFor(_ing(quart, density: 1)), [
          quart,
          cup,
          ml,
          l,
          pint,
          g,
          kg,
        ]);
        // …and without one they are stranded like any cross-family default.
        expect(allowedUnitsFor(_ing(pint)), [g, kg]);
        expect(defaultUnitNeedsDensity(_ing(quart)), isTrue);
      });

      test('a density buys a mass row a pint but never a quart — the cross leg '
          'names cup, not l', () {
        final oats = densityUnlockedUnits(_ing(g, density: 0.4));
        expect(oats, contains(pint));
        expect(oats, isNot(contains(quart)));
      });
    });

    test('mg and fl oz stay label-reading units: offered only as the '
        "default itself, never as anyone else's mate", () {
      // `mg` is a mass unit on a per-100 g row: its own family, so D4c admits
      // it bare. `fl oz` is volume, and needs the density like every other
      // cross-family default.
      expect(allowedUnitsFor(_ing(mg)), contains(mg));
      expect(allowedUnitsFor(_ing(flOz, density: 1)), contains(flOz));
      for (final d in kIngredientUnits.where((u) => u != mg && u != flOz)) {
        final units = allowedUnitsFor(_ing(d, density: 1));
        expect(units, isNot(contains(mg)), reason: 'mg via ${d.id}');
        expect(units, isNot(contains(flOz)), reason: 'fl_oz via ${d.id}');
      }
    });

    test('the default unit is admitted when its family is — and a row whose '
        'default falls outside says so rather than smuggling it in', () {
      // `batch` is deliberately absent: it is a sub-recipe denomination,
      // never an ingredient's unit (step 8.6 / D2) — hence
      // [kIngredientUnits] rather than [kAllUnits].
      for (final u in kIngredientUnits) {
        final bare = _ing(u);
        final bridged = _ing(u, density: 1);
        // With a density every default unit is sayable, as before.
        expect(
          allowedUnitsFor(bridged),
          contains(u),
          reason: '${u.id} bridged',
        );
        expect(defaultUnitNeedsDensity(bridged), isFalse, reason: u.id);
        // Without one, exactly the cross-family defaults are stranded — and
        // stranded is a FLAGGED state, not a silent admission.
        final stranded = u.family == UnitFamily.volume;
        expect(defaultUnitNeedsDensity(bare), stranded, reason: u.id);
        expect(allowedUnitsFor(bare).contains(u), !stranded, reason: u.id);
      }
    });

    test('what may be picked as a default mirrors the same rule, and the '
        'one-tap fix is the basis family’s natural unit', () {
      final perG = _ing(cup);
      expect(unitSayableAsDefault(perG, g), isTrue);
      expect(unitSayableAsDefault(perG, pieces), isTrue);
      expect(unitSayableAsDefault(perG, pinch), isTrue);
      expect(unitSayableAsDefault(perG, cup), isFalse);
      expect(unitSayableAsDefault(_ing(cup, density: 0.59), cup), isTrue);
      expect(basisDefaultUnitFix(perG), g);

      final perMl = _ing(g, basis: MacrosBasis.perMl);
      expect(unitSayableAsDefault(perMl, cup), isTrue);
      expect(unitSayableAsDefault(perMl, g), isFalse);
      expect(basisDefaultUnitFix(perMl), ml);
    });
  });

  group('impreciseUnitsFor — the per-word category gate', () {
    // Owner ruling off the Pixel field test: "a dash of kale" is not how
    // anyone cooks. pinch and dash belong to the spice/seasoning/oil classes;
    // handful belongs to greens — which `produce` is the nearest category the
    // vocabulary can express.
    Set<String> wordsFor(String? category) =>
        impreciseUnitsFor(_ing(g, category: category)).map((u) => u.id).toSet();

    test('the whole mapping, category by category', () {
      expect(wordsFor('spices & seasoning'), {
        'pinch',
        'dash',
        'handful',
        'to_taste',
      });
      expect(wordsFor('fats & oils'), {'pinch', 'dash', 'to_taste'});
      expect(wordsFor('produce'), {'handful'});
      for (final ungated in [
        'pantry',
        'grains',
        'baking',
        'dairy',
        'proteins',
      ]) {
        expect(wordsFor(ungated), isEmpty, reason: ungated);
      }
      // An uncategorised row earns nothing — the gate is a fact about the
      // category, so no category is no licence.
      expect(wordsFor(null), isEmpty);
      expect(wordsFor(''), isEmpty);
    });

    test('THE KALE VECTOR: greens take a handful, never a pinch or a dash', () {
      final kale = allowedUnitsFor(
        _ing(cup, density: 0.2, category: 'produce'),
      );
      expect(kale, contains(handful));
      expect(kale, isNot(contains(pinch)));
      expect(kale, isNot(contains(dash)));
    });

    test('a row whose DEFAULT unit is imprecise can always say it, whatever '
        'its category', () {
      expect(
        impreciseUnitsFor(_ing(pinch, category: 'produce')),
        contains(pinch),
      );
      expect(impreciseUnitsFor(_ing(dash, category: 'grains')), contains(dash));
    });

    test('the category is matched case- and whitespace-insensitively', () {
      expect(wordsFor('  Produce '), {'handful'});
      expect(wordsFor('Spices & Seasoning'), hasLength(4));
    });
  });

  group('allowedUnitsFor — the explicit list wins over the rule', () {
    test('an explicit list is honored verbatim as a set, in chip order', () {
      // A flesh-out-form edit ("this household says flour in cups and
      // grams only") must never be second-guessed by the derived rule.
      final units = allowedUnitsFor(
        _ing(cup, density: 0.59, allowed: const [g, cup, toTaste]),
      );
      expect(units, [cup, g, toTaste]);
    });

    test('ordering fronts the default and demotes the other family, whatever '
        'order the list arrived in', () {
      final units = allowedUnitsFor(
        _ing(tsp, density: 0.4, allowed: const [kg, tbsp, g, tsp]),
      );
      expect(units, [tsp, tbsp, g, kg]);
    });

    test('what an explicit list CANNOT do is admit a unit no density supports '
        '— the number, not the list, says what is sayable', () {
      // The shape a pre-D4c server materialization leaves behind (and an
      // older client, and a deleted density the list did not follow).
      final stale = _ing(tsp, allowed: const [kg, tbsp, g, tsp]);
      expect(allowedUnitsFor(stale), [g, kg]);
      // The list is not rewritten — only read strictly. Give the row its
      // density and every unit it names is offered again.
      expect(
        allowedUnitsFor(_ing(tsp, density: 0.4, allowed: const [kg, tbsp, g])),
        [tbsp, g, kg],
      );
    });

    test('an empty explicit list falls back to the derived defaults (a row '
        'must never render zero chips)', () {
      final units = allowedUnitsFor(_ing(tsp, allowed: const []));
      expect(units, [g]);
    });
  });

  group('allowedUnitChoicesFor', () {
    const large = Measure(id: 'm1', label: 'potato, large', amount: 299);
    const medium = Measure(id: 'm2', label: 'potato, medium', amount: 213.5);

    test('slots measure options after the default set, before imprecise, in '
        'order', () {
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
          'tsp', 'tbsp', 'cup', 'ml', 'pt', // density-unlocked, demoted
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

    group('ADR-0010: piece is an admission, so the chip row simply never '
        'offers it where the list refuses it', () {
      test('the avocado shape: a curated list without `piece` gives a chip row '
          'with the measure and no `piece` anywhere', () {
        const avocadoMeasure = Measure(
          id: 'm-avo',
          label: 'avocado',
          amount: 201,
        );
        final offer = allowedUnitChoicesFor(
          _ing(
            pieces,
            density: 0.634,
            category: 'produce',
            allowed: const [g, tsp, tbsp, cup, ml],
          ),
          const [avocadoMeasure],
        );
        expect(offer.choices.map((c) => c.label), isNot(contains('piece')));
        expect(offer.choices.first, const MeasureOption(avocadoMeasure));
      });

      test('a measure-less count row keeps `piece`, and it leads — there is '
          'nothing clearer to say', () {
        // The derived default is deliberately untouched by the curation
        // pass: this is the fallback the whole rule exists to protect.
        final offer = allowedUnitChoicesFor(_ing(pieces), const []);
        expect(offer.choices.first.label, 'piece');
      });

      test('a line already SAVED as a bare `piece` on a now-measured row is '
          'still offered, flagged "not in filter" — degrade, never '
          'destroy', () {
        const avocadoMeasure = Measure(
          id: 'm-avo',
          label: 'avocado',
          amount: 201,
        );
        final offer = allowedUnitChoicesFor(
          _ing(pieces, density: 0.634, allowed: const [g, cup, ml]),
          const [avocadoMeasure],
          current: const UnitOption(pieces),
        );
        // The same rule ADR-0009 applied to a `cup` line whose density was
        // deleted: the stored value stays selectable and is never rewritten.
        expect(offer.offFilter, const UnitOption(pieces));
        expect(offer.choices.last, const UnitOption(pieces));
        // …and it does not sneak back into the honest offer ahead of it.
        expect(
          offer.choices.sublist(0, offer.choices.length - 1),
          isNot(contains(const UnitOption(pieces))),
        );
      });
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
      expect(selectedOf(curryLeaves), {'g', 'kg', 'handful'});
      expect(lockedOf(curryLeaves), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
    });

    test('a piece default with no density locks BOTH families beyond its own '
        'basis base — a density is what opens them', () {
      final mangoWithoutDensity = _ing(pieces, category: 'produce');
      expect(selectedOf(mangoWithoutDensity), {'piece', 'g', 'handful'});
      expect(lockedOf(mangoWithoutDensity), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
    });

    test('with the density, nothing is locked (the mango frame)', () {
      final mango = _ing(pieces, density: 0.66, category: 'produce');
      expect(lockedOf(mango), isEmpty);
      expect(selectedOf(mango), {
        'piece',
        'g',
        'tsp',
        'tbsp',
        'cup',
        'ml',
        'pt',
        'handful',
      });
    });

    test('a stored unit the derived rules would not admit still appears, '
        'selected and unlocked — an explicit list is user-owned', () {
      final curated = _ing(g, allowed: const [g, flOz, toTaste]);
      expect(selectedOf(curated), containsAll(<String>['fl_oz', 'to_taste']));
      expect(lockedOf(curated), isNot(contains('fl_oz')));
    });

    test('a stored list that still names the cross-family units draws them '
        'LOCKED once the density is gone — the number, not the list, says what '
        'is sayable', () {
      // The shape a device leaves behind when the density is deleted
      // somewhere the list did not follow (an older client, a server edit).
      final stale = _ing(pieces, allowed: const [pieces, g, cup, ml]);
      expect(lockedOf(stale), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
      // …and the basis side is untouched: it never needed a density.
      expect(selectedOf(stale), {'piece', 'g'});
    });

    test('the basis family is never locked, whichever way the panel reads', () {
      final perMl = _ing(ml, basis: MacrosBasis.perMl);
      expect(lockedOf(perMl), {'g'});
      expect(selectedOf(perMl), containsAll(<String>['ml', 'l']));

      final perG = _ing(g);
      expect(lockedOf(perG), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
      expect(selectedOf(perG), containsAll(<String>['g']));
    });
  });

  group('densityStrippedUnits — what deleting a density takes back', () {
    test('the mango shape: the volume leg goes, piece and the basis base '
        'stay', () {
      final mango = _ing(pieces, density: 0.66, category: 'produce');
      expect(densityStrippedUnits(mango), {tsp, tbsp, cup, ml, pint});
      expect(densityStrippedUnits(mango), isNot(contains(g)));
      expect(densityStrippedUnits(mango), isNot(contains(pieces)));
    });

    test('THE FLOUR SHAPE: the volume family goes — including the row’s own '
        'default unit, which the density was the only thing admitting', () {
      final flour = _ing(cup, density: 0.59, category: 'baking');
      expect(densityStrippedUnits(flour), {cup, tbsp, ml, l, pint, quart});
      // Mass is its basis family and survives, density or not.
      expect(densityStrippedUnits(flour), isNot(contains(g)));
      expect(densityStrippedUnits(flour), isNot(contains(kg)));
      // Which is exactly the state D4c flags rather than repairing.
      expect(defaultUnitNeedsDensity(_ing(cup, category: 'baking')), isTrue);
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
