/// The batch-math resolver (step 8.6 / D2) and the client cycle check (D5).
///
/// The vectors here are the sausage-sliders specimens the exec plan opens
/// with, because they are the whole quantity problem: a count, a volume, a
/// fraction of a batch, and the parked "what does the `1` count".
library;

import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// "makes 1 cup" — the Romesco Aioli.
const _aioli = [(qty: 1.0, unit: cup)];

/// "makes 8 piece" — the page-45 sausage, and the pretzel buns.
const _eight = [(qty: 8.0, unit: pieces)];

/// "makes 250 g · 16 tbsp" — the Garlic Butter, both denominations stated.
const _butter = [(qty: 250.0, unit: g), (qty: 16.0, unit: tbsp)];

double _batches(ComponentAmount a) => (a as ResolvedComponentAmount).batches;

/// "a batch makes 20 blob" — the household's own word for the aioli.
RecipeMeasure _m(String label, double perBatch, {String id = 'blob'}) =>
    RecipeMeasure(id: id, recipeId: 'aioli', label: label, perBatch: perBatch);

void main() {
  group('yieldDenominations', () {
    test(
      'drops a half-stated pair — a number without a unit is half a fact',
      () {
        expect(yieldDenominations(1, null, null, null), isEmpty);
        expect(yieldDenominations(null, cup, null, null), isEmpty);
      },
    );

    test('drops a non-positive quantity rather than dividing by it', () {
      expect(yieldDenominations(0, cup, null, null), isEmpty);
      expect(yieldDenominations(-1, cup, null, null), isEmpty);
    });

    test('keeps both denominations, in stated order', () {
      expect(yieldDenominations(250, g, 16, tbsp), [
        (qty: 250.0, unit: g),
        (qty: 16.0, unit: tbsp),
      ]);
    });

    test('a second denomination without a first is dropped with it', () {
      expect(yieldDenominations(null, null, 16, tbsp), [
        (qty: 16.0, unit: tbsp),
      ]);
    });
  });

  group('resolveComponentAmount — the batch denomination', () {
    test('`batch` resolves with no yield at all: the number IS the count', () {
      final r = resolveComponentAmount(
        quantity: 2,
        unit: batches,
        yields: const [],
      );
      expect(_batches(r), 2);
      expect((r as ResolvedComponentAmount).against, isNull);
    });

    test('a fractional batch is kept fractional, never rounded', () {
      expect(
        _batches(
          resolveComponentAmount(quantity: 0.5, unit: batches, yields: _aioli),
        ),
        0.5,
      );
    });
  });

  group('resolveComponentAmount — against a yield', () {
    test('"¼ cup" of a recipe that makes 1 cup is ¼ of a batch', () {
      final r = resolveComponentAmount(
        quantity: 0.25,
        unit: cup,
        yields: _aioli,
      );
      expect(_batches(r), closeTo(0.25, 1e-12));
      expect((r as ResolvedComponentAmount).against, (qty: 1.0, unit: cup));
    });

    test('a same-family unit converts first: 4 tbsp of a 1-cup batch', () {
      // 4 tbsp = 59.147 ml; a cup is 236.588 ml → exactly ¼.
      expect(
        _batches(
          resolveComponentAmount(quantity: 4, unit: tbsp, yields: _aioli),
        ),
        closeTo(0.25, 1e-12),
      );
    });

    test('THE SAUSAGE ANSWER: "1" of a recipe that makes 8 piece is ⅛', () {
      expect(
        _batches(
          resolveComponentAmount(quantity: 1, unit: pieces, yields: _eight),
        ),
        0.125,
      );
    });

    test('a bare count scales the whole way: 8 pretzel buns is one batch', () {
      expect(
        _batches(
          resolveComponentAmount(quantity: 8, unit: pieces, yields: _eight),
        ),
        1,
      );
    });

    test('both denominations resolve DIFFERENT lines of the same target', () {
      // The owner amendment's whole point: "makes 250 g · 16 tbsp" answers a
      // mass line and a volume line of the same Garlic Butter.
      expect(
        _batches(
          resolveComponentAmount(quantity: 125, unit: g, yields: _butter),
        ),
        0.5,
      );
      final volume = resolveComponentAmount(
        quantity: 2,
        unit: tbsp,
        yields: _butter,
      );
      expect(_batches(volume), 0.125);
      expect((volume as ResolvedComponentAmount).against, (
        qty: 16.0,
        unit: tbsp,
      ));
    });

    test('the SECOND denomination is used when only it matches', () {
      final r = resolveComponentAmount(
        quantity: 8,
        unit: tbsp,
        yields: _butter,
      );
      expect((r as ResolvedComponentAmount).against!.unit, tbsp);
      expect(r.batches, 0.5);
    });
  });

  group('resolveComponentAmount — the honest refusals (never 1×)', () {
    test('no yield at all is unresolved, not one batch', () {
      expect(
        resolveComponentAmount(quantity: 0.25, unit: cup, yields: const []),
        const ComponentYieldMissing(),
      );
    });

    test('a half-stated yield is no yield', () {
      expect(
        resolveComponentAmount(
          quantity: 1,
          unit: cup,
          yields: yieldDenominations(1, null, null, null),
        ),
        const ComponentYieldMissing(),
      );
    });

    test('2 tbsp against a mass-only yield is a family mismatch — there is no '
        'density for a recipe', () {
      final r = resolveComponentAmount(
        quantity: 2,
        unit: tbsp,
        yields: const [(qty: 250.0, unit: g)],
      );
      expect(
        r,
        const ComponentFamilyMismatch(
          lineFamily: UnitFamily.volume,
          yieldFamilies: [UnitFamily.mass],
        ),
      );
      expect((r as ComponentFamilyMismatch).lineFamily, UnitFamily.volume);
      expect(r.yieldFamilies, [UnitFamily.mass]);
    });

    test('a count line against a volume yield does not become millilitres', () {
      expect(
        resolveComponentAmount(quantity: 2, unit: pieces, yields: _aioli),
        const ComponentFamilyMismatch(
          lineFamily: UnitFamily.count,
          yieldFamilies: [UnitFamily.volume],
        ),
      );
    });

    test('an imprecise line never resolves, even against a stated yield', () {
      for (final u in [pinch, dash, handful, toTaste]) {
        expect(
          resolveComponentAmount(quantity: 1, unit: u, yields: _butter),
          isA<ComponentFamilyMismatch>(),
          reason: u.id,
        );
      }
    });

    test('an imprecise line against an imprecise yield still refuses: the '
        'families match but the conversion does not exist', () {
      expect(
        resolveComponentAmount(
          quantity: 1,
          unit: pinch,
          yields: const [(qty: 2.0, unit: dash)],
        ),
        isA<ComponentFamilyMismatch>(),
      );
    });

    test('a numberless line resolves to nothing, for any yield', () {
      expect(
        resolveComponentAmount(quantity: null, unit: cup, yields: _aioli),
        const ComponentAmountMissing(),
      );
      // Even in batches — "some of the aioli" is not a quantity.
      expect(
        resolveComponentAmount(quantity: null, unit: batches, yields: _aioli),
        const ComponentAmountMissing(),
      );
    });

    test('the mismatch carries BOTH yield families when two are stated', () {
      expect(
        resolveComponentAmount(quantity: 1, unit: pieces, yields: _butter),
        const ComponentFamilyMismatch(
          lineFamily: UnitFamily.count,
          yieldFamilies: [UnitFamily.mass, UnitFamily.volume],
        ),
      );
    });
  });

  group('the batch unit itself', () {
    test('converts to nothing — a batch reaches grams only via a yield', () {
      expect(convert(Quantity(1, batches), to: g), isA<Err<Quantity>>());
      expect(convert(Quantity(1, batches), to: pieces), isA<Err<Quantity>>());
      expect(
        convert(Quantity(1, batches), to: ml, densityGPerMl: 1),
        isA<Err<Quantity>>(),
      );
      expect(convert(Quantity(1, g), to: batches), isA<Err<Quantity>>());
    });

    test(
      'scales like a real number (a component line scales with its recipe)',
      () {
        expect(scale(Quantity(0.25, batches), 2), Quantity(0.5, batches));
      },
    );

    test('is not an ingredient unit', () {
      expect(kIngredientUnits, isNot(contains(batches)));
      expect(kAllUnits, contains(batches));
      expect(unitById('batch'), batches);
    });
  });

  group('closesComponentCycle (the client half of the guard)', () {
    test('a recipe cannot be a component of itself', () {
      expect(
        closesComponentCycle(from: 'a', to: 'a', componentsOf: (_) => const []),
        isTrue,
      );
    });

    test('a link into an unrelated recipe is fine', () {
      expect(
        closesComponentCycle(
          from: 'sliders',
          to: 'aioli',
          componentsOf: (_) => const [],
        ),
        isFalse,
      );
    });

    test('refuses a link the target already reaches back through', () {
      // aioli → sauce → sliders; linking sliders → aioli would close it.
      const edges = {
        'aioli': ['sauce'],
        'sauce': ['sliders'],
      };
      expect(
        closesComponentCycle(
          from: 'sliders',
          to: 'aioli',
          componentsOf: (id) => edges[id] ?? const [],
        ),
        isTrue,
      );
    });

    test('terminates over rows that ALREADY contain a cycle', () {
      // A two-device race can land a → b → a. The walk must not hang the
      // device trying to write past it.
      const edges = {
        'a': ['b'],
        'b': ['a'],
      };
      expect(
        closesComponentCycle(
          from: 'c',
          to: 'a',
          componentsOf: (id) => edges[id] ?? const [],
        ),
        isFalse,
      );
    });
  });

  group("resolveComponentAmount — the recipe's own word", () {
    test('`3 blob` of a batch that makes 20 is 0.15 batches', () {
      final r = resolveComponentAmount(
        quantity: 3,
        unit: null,
        yields: _aioli,
        recipeMeasureId: 'blob',
        measures: [_m('blob', 20)],
      );
      expect(_batches(r), closeTo(0.15, 1e-12));
      expect((r as ResolvedComponentAmount).viaMeasure?.label, 'blob');
      // It went nowhere near the yield.
      expect(r.against, isNull);
    });

    test('scaling the parent moves the LINE, never the word', () {
      final blob = [_m('blob', 20)];
      ComponentAmount at(double qty) => resolveComponentAmount(
        quantity: qty,
        unit: null,
        yields: _aioli,
        recipeMeasureId: 'blob',
        measures: blob,
      );
      expect(_batches(at(3)), closeTo(0.15, 1e-12));
      expect(_batches(at(6)), closeTo(0.3, 1e-12));
      expect(blob.single.perBatch, 20);
    });

    test('it needs no yield at all — the whole point of the feature', () {
      final r = resolveComponentAmount(
        quantity: 2,
        unit: null,
        yields: const [],
        recipeMeasureId: 'blob',
        measures: [_m('blob', 20)],
      );
      expect(_batches(r), closeTo(0.1, 1e-12));
    });

    test('a batch that makes one of something is one batch', () {
      final r = resolveComponentAmount(
        quantity: 1,
        unit: null,
        yields: const [(qty: 900.0, unit: g)],
        recipeMeasureId: 'loaf',
        measures: [_m('loaf', 1, id: 'loaf')],
      );
      expect(_batches(r), 1);
    });

    test('nothing is special-cased about the word itself', () {
      for (final word in ['blob', 'ladle', 'patty', 'batchy', 'piecey']) {
        final r = resolveComponentAmount(
          quantity: 5,
          unit: null,
          yields: const [],
          recipeMeasureId: 'w',
          measures: [_m(word, 10, id: 'w')],
        );
        expect(_batches(r), 0.5, reason: word);
      }
    });
  });

  group('a word the target no longer has', () {
    test('refuses, and names the pointer the line still stores', () {
      final r = resolveComponentAmount(
        quantity: 3,
        unit: null,
        yields: _aioli,
        recipeMeasureId: 'blob',
        measures: const [],
      );
      expect(r, const ComponentMeasureMissing('blob'));
    });

    test('NEVER degrades to a count against a counted yield', () {
      // `makes 8 piece` would read `3 blob` as 0.375 of a batch — a number
      // nobody stated, off by whatever the household meant by a blob.
      final r = resolveComponentAmount(
        quantity: 3,
        unit: pieces,
        yields: _eight,
        recipeMeasureId: 'blob',
        measures: const [],
      );
      expect(r, isA<ComponentMeasureMissing>());
      expect(r, isNot(isA<ResolvedComponentAmount>()));
    });

    test('a row whose number says nothing reads as gone, not as a divide', () {
      for (final bad in [0.0, -4.0, double.nan, double.infinity]) {
        final r = resolveComponentAmount(
          quantity: 3,
          unit: null,
          yields: _aioli,
          recipeMeasureId: 'blob',
          measures: [_m('blob', bad)],
        );
        expect(r, const ComponentMeasureMissing('blob'), reason: '\$bad');
      }
    });

    test('a numberless measured line is missing its amount, not its word', () {
      final r = resolveComponentAmount(
        quantity: null,
        unit: null,
        yields: _aioli,
        recipeMeasureId: 'blob',
        measures: [_m('blob', 20)],
      );
      expect(r, const ComponentAmountMissing());
    });

    test('a number with no denomination at all says nothing', () {
      // The database cannot store one and the line model asserts against it;
      // this is totality, and the honest reading of a bare number.
      expect(
        resolveComponentAmount(quantity: 3, unit: null, yields: _aioli),
        const ComponentAmountMissing(),
      );
    });

    test('the refusal is value-equal on the pointer it names', () {
      expect(
        const ComponentMeasureMissing('a'),
        const ComponentMeasureMissing('a'),
      );
      expect(
        const ComponentMeasureMissing('a'),
        isNot(const ComponentMeasureMissing('b')),
      );
      expect(
        const ComponentMeasureMissing('a').hashCode,
        const ComponentMeasureMissing('a').hashCode,
      );
    });
  });
}
