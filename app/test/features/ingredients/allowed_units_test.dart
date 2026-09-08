import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row of `allowed_units_vectors.json` — the file the pgTAP mirror reads
/// too, through `supabase/seed/scripts/gen_admission_vectors.ts`.
class _Vector {
  _Vector(Map<String, dynamic> json)
    : shape = json['shape'] as String,
      why = json['why'] as String,
      ingredient = _ing(
        unitById(json['defaultUnit'] as String)!,
        density: (json['density'] as num?)?.toDouble(),
        category: json['category'] as String?,
        basis: json['basis'] == 'ml' ? MacrosBasis.perMl : MacrosBasis.perG,
      ),
      expect = [
        for (final id in json['expect'] as List) unitById(id as String)!,
      ];

  final String shape;
  final String why;
  final Ingredient ingredient;
  final List<Unit> expect;
}

List<_Vector> _sharedVectors() {
  final file = File('test/features/ingredients/allowed_units_vectors.json');
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final v in decoded['vectors'] as List)
      _Vector(v as Map<String, dynamic>),
  ];
}

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

/// The two mass/volume families in chip order. A family is the unit of
/// admission now (ADR-0014), so most expectations below are one of these, or
/// both, with the row's default fronted.
const _mass = [g, kg, oz, lb];
const _volume = [tsp, tbsp, flOz, cup, ml, l, pint, quart];
final _massIds = {for (final u in _mass) u.id};
final _volumeIds = {for (final u in _volume) u.id};

void main() {
  group('allowedUnitsFor — the derived defaults (mirrors the pgTAP '
      'default_allowed_units vectors)', () {
    // The shapes themselves live in allowed_units_vectors.json, which the
    // pgTAP suite reads too — through gen_admission_vectors.ts, which renders
    // it as the generated `values` block in tests/unit_admission.sql. One
    // file, so neither mirror can move without the other failing. What is
    // written out below the loop is what a vector cannot carry: a refusal, or
    // a second row read against the first.
    final vectors = _sharedVectors();

    test('the vector file actually loaded', () {
      // An emptied or unfound fixture would make every case below vacuous.
      expect(vectors, hasLength(12));
    });

    for (final v in vectors) {
      test('the ${v.shape} shape: ${v.why}', () {
        expect(allowedUnitsFor(v.ingredient), v.expect);
      });
    }

    test('a density is what buys the yeast shape its spoons back', () {
      // Without the number the row's own default is unsayable (D4c): the
      // volume family is the density's to give, spoons included.
      expect(allowedUnitsFor(_ing(tsp, density: 0.4, category: 'baking')), [
        tsp,
        tbsp,
        flOz,
        cup,
        ml,
        l,
        pint,
        quart,
        ..._mass,
      ]);
    });

    test('what the shapes refuse: no handful of oil, no pinch of egg', () {
      // The per-word category gate, read from the other side — the vectors
      // say what is admitted, and these are the words that stayed out.
      final oil = allowedUnitsFor(
        _ing(tbsp, density: 0.91, category: 'fats & oils'),
      );
      expect(oil, isNot(contains(handful)));
      final egg = allowedUnitsFor(_ing(pieces, category: 'produce'));
      expect(egg, isNot(contains(pinch)));
      expect(egg, isNot(contains(dash)));
    });

    test('an imprecise default keeps its whole tail + the basis family', () {
      final units = allowedUnitsFor(
        _ing(pinch, category: 'spices & seasoning'),
      );
      expect(units, [..._mass, pinch, dash, handful, toTaste]);
    });

    test('a mass default /g with density unlocks the volume family, after the '
        'default family', () {
      // Oats: grams AND cups are both honest — and the unlocked family
      // trails the default's own (the choice builder pushes it below the
      // measures too).
      final units = allowedUnitsFor(_ing(g, density: 0.4));
      expect(units, [..._mass, ..._volume]);
      expect(units, isNot(contains(pieces)));
    });

    test('the mango shape leaves nothing out: a density is a fact about the '
        'substance, so both families come whole', () {
      final units = allowedUnitsFor(
        _ing(pieces, density: 0.66, category: 'produce'),
      );
      // The magnitude gate that kept `kg` and `l` off a piece-default row is
      // gone with the rest of the trim: a litre of mango purée is a sentence,
      // and a household that will never say it turns the chip off.
      expect(units, containsAll(<Unit>[kg, l, quart]));
    });

    test('without a density a count default still admits nothing but its own '
        'piece and the basis family — the unlock rides the density, not the '
        'family', () {
      expect(allowedUnitsFor(_ing(pieces, category: 'produce')), [
        pieces,
        ..._mass,
        handful, // J3: the category's word, not the density's business
      ]);
    });

    test('an imprecise default with a density unlocks both families too, and '
        'keeps its whole tail INCLUDING handful (the mirror divergence: the '
        'SQL leg was missing it)', () {
      final units = allowedUnitsFor(
        _ing(pinch, density: 1, category: 'spices & seasoning'),
      );
      expect(units, [..._mass, ..._volume, pinch, dash, handful, toTaste]);
    });

    group('ADR-0014 — all to all: a family is admitted whole', () {
      // The admissions themselves are the shared vectors above. What is
      // pinned here is the property they are examples of: the relation "may
      // be said in" is now the family, read in every direction.

      test('a row that may be said in one unit of a family may be said in '
          'every unit of it', () {
        for (final basis in [MacrosBasis.perG, MacrosBasis.perMl]) {
          final family = basis == MacrosBasis.perMl ? _volume : _mass;
          for (final d in family) {
            expect(
              allowedUnitsFor(_ing(d, basis: basis)),
              containsAll(family),
              reason: '${d.id} /${basis.baseUnit.id}',
            );
          }
        }
      });

      test('the ladders join up in both directions, spoons to litres', () {
        // The asymmetries two ADRs closed one rung at a time — cup refusing
        // tsp, oz refusing kg — cannot exist in a rule that admits families.
        final sugar = allowedUnitsFor(_ing(cup, density: 0.85));
        expect(sugar, containsAll(<Unit>[tsp, tbsp, l, quart]));
        final yeast = allowedUnitsFor(_ing(tsp, density: 0.4));
        expect(yeast, containsAll(<Unit>[cup, l]));
        expect(allowedUnitsFor(_ing(oz)), contains(kg));
      });

      test('fl oz is an ordinary volume unit — a kitchen unit here, offered '
          'like the rest of its family', () {
        expect(allowedUnitsFor(_ing(cup, basis: MacrosBasis.perMl)), [
          cup,
          tsp,
          tbsp,
          flOz,
          ml,
          l,
          pint,
          quart,
        ]);
        expect(allowedUnitsFor(_ing(g, density: 0.9)), contains(flOz));
        // …and as a default it needs a density like any cross-family one.
        expect(allowedUnitsFor(_ing(flOz, density: 1)), contains(flOz));
        expect(defaultUnitNeedsDensity(_ing(flOz)), isTrue);
      });

      test('mg is gone from the catalog, so nothing can offer it', () {
        expect(unitById('mg'), isNull);
        for (final d in kIngredientUnits) {
          expect(
            allowedUnitsFor(_ing(d, density: 1)).map((u) => u.id),
            isNot(contains('mg')),
            reason: d.id,
          );
        }
      });

      test('the density gate is the only gate left: the other family is all '
          'there, or none of it', () {
        for (final d in [g, kg, oz, lb, pieces, pinch]) {
          expect(allowedUnitsFor(_ing(d)), isNot(contains(ml)), reason: d.id);
          expect(
            allowedUnitsFor(_ing(d, density: 0.9)),
            containsAll(_volume),
            reason: d.id,
          );
        }
      });

      test('what a density is worth is the whole other family', () {
        expect(densityUnlockedUnits(_ing(g, density: 0.9)), _volume.toSet());
        expect(
          densityUnlockedUnits(_ing(pieces, density: 0.9)),
          _volume.toSet(),
        );
        final milk = _ing(ml, density: 1.03, basis: MacrosBasis.perMl);
        expect(densityUnlockedUnits(milk), _mass.toSet());
      });
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
      expect(units, _mass);
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
        'kg',
        'oz',
        'lb',
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
          'g', 'kg', 'oz', 'lb', // the default's own family leads
          'potato, large', // measures
          // the density-unlocked family, whole and demoted
          'tsp', 'tbsp', 'fl_oz', 'cup', 'ml', 'l', 'pt', 'qt',
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
      expect(selectedOf(curryLeaves), {'g', 'kg', 'oz', 'lb', 'handful'});
      expect(lockedOf(curryLeaves), _volumeIds);
    });

    test('a piece default with no density locks BOTH families beyond its own '
        'basis base — a density is what opens them', () {
      final mangoWithoutDensity = _ing(pieces, category: 'produce');
      expect(selectedOf(mangoWithoutDensity), {
        'piece',
        ..._massIds,
        'handful',
      });
      expect(lockedOf(mangoWithoutDensity), _volumeIds);
    });

    test('with the density, nothing is locked (the mango frame)', () {
      final mango = _ing(pieces, density: 0.66, category: 'produce');
      expect(lockedOf(mango), isEmpty);
      expect(selectedOf(mango), {
        'piece',
        ..._massIds,
        ..._volumeIds,
        'handful',
      });
    });

    test('a stored unit the derived rules would not admit still appears, '
        'selected and unlocked — an explicit list is user-owned', () {
      // `piece` is the one admission the rule never derives for a weighed row
      // (ADR-0010 keeps it curated), so it is what this can be shown with.
      final curated = _ing(g, allowed: const [g, pieces, toTaste]);
      expect(selectedOf(curated), containsAll(<String>['piece', 'to_taste']));
      expect(lockedOf(curated), isNot(contains('piece')));
    });

    test('every imprecise word is a chip the row may turn on, whatever its '
        'category — the user prunes, the gate only pre-picks', () {
      final chips = {
        for (final c in allowedUnitCandidates(_ing(g, category: 'produce')))
          c.unit.id: c,
      };
      for (final word in ['pinch', 'dash', 'handful', 'to_taste']) {
        expect(chips[word]?.locked, isFalse, reason: word);
      }
      // Only `handful` arrives picked: produce earns that one word (J3).
      expect(chips['handful']!.selected, isTrue);
      expect(chips['pinch']!.selected, isFalse);
    });

    test('a density-carrying row locks nothing at all', () {
      for (final c in allowedUnitCandidates(_ing(cup, density: 0.85))) {
        expect(c.locked, isFalse, reason: c.unit.id);
      }
    });

    test('a stored list that still names the cross-family units draws them '
        'LOCKED once the density is gone — the number, not the list, says what '
        'is sayable', () {
      // The shape a device leaves behind when the density is deleted
      // somewhere the list did not follow (an older client, a server edit).
      final stale = _ing(pieces, allowed: const [pieces, g, cup, ml]);
      expect(lockedOf(stale), _volumeIds);
      // …and the basis side is untouched: it never needed a density.
      expect(selectedOf(stale), {'piece', 'g'});
    });

    test('the basis family is never locked, whichever way the panel reads', () {
      final perMl = _ing(ml, basis: MacrosBasis.perMl);
      expect(lockedOf(perMl), _massIds);
      expect(selectedOf(perMl), containsAll(<String>['ml', 'l']));

      final perG = _ing(g);
      expect(lockedOf(perG), _volumeIds);
      expect(selectedOf(perG), containsAll(<String>['g']));
    });
  });

  group('densityStrippedUnits — what deleting a density takes back', () {
    test('the mango shape: the volume leg goes, piece and the basis base '
        'stay', () {
      final mango = _ing(pieces, density: 0.66, category: 'produce');
      expect(densityStrippedUnits(mango), _volume.toSet());
      expect(densityStrippedUnits(mango), isNot(contains(g)));
      expect(densityStrippedUnits(mango), isNot(contains(pieces)));
    });

    test('THE FLOUR SHAPE: the volume family goes — including the row’s own '
        'default unit, which the density was the only thing admitting', () {
      final flour = _ing(cup, density: 0.59, category: 'baking');
      expect(densityStrippedUnits(flour), _volume.toSet());
      // Mass is its basis family and survives, density or not.
      expect(densityStrippedUnits(flour), isNot(contains(g)));
      expect(densityStrippedUnits(flour), isNot(contains(kg)));
      // Which is exactly the state D4c flags rather than repairing.
      expect(defaultUnitNeedsDensity(_ing(cup, category: 'baking')), isTrue);
      // Mass is its basis family and survives, density or not.
      expect(allowedUnitsFor(_ing(cup, category: 'baking')), _mass);
    });

    test('the milk shape: a per-ml row loses g, keeps every volume unit', () {
      final milk = _ing(ml, density: 1.03, basis: MacrosBasis.perMl);
      expect(densityStrippedUnits(milk), _mass.toSet());
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
