import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_authoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// "makes 300 g" — the aioli, weighed, which is what lets it coin a word at
/// all. Every `_author` below is held against this unless it says otherwise.
const _weighed = [(qty: 300.0, unit: g)];

/// "makes 300 g · 1.25 cup" — both denominations stated, so either family
/// can be said.
const _both = [(qty: 300.0, unit: g), (qty: 1.25, unit: cup)];

RecipeMeasure _m(
  String label,
  double amount, {
  Unit unit = g,
  String id = 'm1',
  int sortOrder = 0,
}) => RecipeMeasure(
  id: id,
  recipeId: 'aioli',
  label: label,
  amount: amount,
  unit: unit,
  sortOrder: sortOrder,
);

Result<RecipeMeasure> _author(
  String label,
  double? amount, {
  Unit unit = g,
  List<YieldDenomination> yields = _weighed,
  String id = 'new',
  List<RecipeMeasure> measures = const [],
}) => authorRecipeMeasure(
  id: id,
  recipeId: 'aioli',
  label: label,
  amount: amount,
  unit: unit,
  yields: yields,
  measures: measures,
);

void main() {
  group('the word is read exactly as the ingredient side reads one', () {
    test('trimmed, inner whitespace collapsed, case untouched', () {
      expect(_author('  Big  Blob ', 20).valueOrNull?.label, 'Big Blob');
      expect(_author('BLOB', 20).valueOrNull?.label, 'BLOB');
    });

    test('nothing typed is refused, with the sentence a form prints', () {
      final refused = _author('   ', 20);
      expect(refused, isA<Err<RecipeMeasure>>());
      expect((refused as Err).failure.code, 'recipe_measure/no_label');
      expect((refused as Err).failure.message, contains('what you call one'));
    });
  });

  group('a word that merely names a unit is not a word', () {
    test('a catalog unit, however it is typed', () {
      for (final word in ['cup', 'Cups ', 'g', 'tbsp', 'ml', 'piece']) {
        final refused = _author(word, 20);
        expect(refused, isA<Err<RecipeMeasure>>(), reason: word);
        expect((refused as Err).failure.code, 'recipe_measure/unit_word');
      }
    });

    test('`batch` above all — it is the thing a measure is a share of', () {
      final refused = _author('batch', 20) as Err<RecipeMeasure>;
      expect(refused.failure.code, 'recipe_measure/unit_word');
      expect(refused.failure.message, contains('“batch” is already a unit'));
    });

    test('a printed spelling the catalog does not label', () {
      expect(
        (_author('grams', 20) as Err).failure.code,
        'recipe_measure/unit_word',
      );
      expect(
        (_author('tablespoon', 20) as Err).failure.code,
        'recipe_measure/unit_word',
      );
    });

    test('a household word passes — nothing is hard-coded', () {
      for (final word in ['blob', 'ladle', 'patty', 'loaf', 'schmear']) {
        expect(_author(word, 20).valueOrNull?.label, word, reason: word);
      }
    });
  });

  group('the recipe cannot say one word twice', () {
    final blob = _m('blob', 15);

    test('a second row with the same word, ignoring case', () {
      final refused =
          _author('Blob', 6, measures: [blob]) as Err<RecipeMeasure>;
      expect(refused.failure.code, 'recipe_measure/word_taken');
      expect(
        refused.failure.message,
        '“blob” is already this recipe’s word, at 15 g. Re-state that one '
        'and every line saying it follows.',
      );
    });

    test('a row re-stating ITSELF is not its own duplicate', () {
      // The board's rule: the row keeps its id, so `blob` moving 15 g → 18 g
      // follows through to every line already saying it.
      final restated = _author('blob', 18, id: 'm1', measures: [blob]);
      expect(restated.valueOrNull?.id, 'm1');
      expect(restated.valueOrNull?.amount, 18);
    });

    test('another recipe saying it is nothing to do with this one', () {
      expect(_author('blob', 15).valueOrNull?.label, 'blob');
    });
  });

  group('the number', () {
    test('missing, zero, negative or NaN is refused', () {
      for (final bad in [null, 0.0, -2.0, double.nan, double.infinity]) {
        final refused = _author('blob', bad);
        expect(refused, isA<Err<RecipeMeasure>>(), reason: '$bad');
        expect((refused as Err).failure.code, 'recipe_measure/amount');
      }
      expect(
        (_author('blob', 0) as Err).failure.message,
        'Say what one “blob” comes to — a number above zero.',
      );
    });

    test('a fraction of one is a number too', () {
      expect(
        _author(
          'vat',
          0.5,
          unit: kg,
          yields: const [(qty: 3.0, unit: kg)],
        ).valueOrNull?.amount,
        0.5,
      );
    });
  });

  group('the unit, which is the half a recipe has to lend', () {
    test('it is kept on the row, whichever family it is', () {
      final ladle = _author(
        'ladle',
        180,
        unit: ml,
        yields: const [(qty: 720.0, unit: ml)],
      );
      expect(ladle.valueOrNull?.unit, ml);
      expect(ladle.valueOrNull?.amount, 180);
    });

    test('`batch` is refused: a word defined in batches is circular', () {
      final refused =
          _author('blob', 0.05, unit: batches) as Err<RecipeMeasure>;
      expect(refused.failure.code, 'recipe_measure/unit_cannot_measure');
      expect(
        refused.failure.message,
        '“blob” can’t be a fraction of a batch — that is the arithmetic '
        'nobody thinks in, and the word is here to reach a batch rather than '
        'to be one. Say what one comes to as a weight, a volume or a count.',
      );
    });

    test('an imprecise word is refused: it converts nothing', () {
      for (final bad in [pinch, dash, handful, toTaste]) {
        final refused = _author('blob', 1, unit: bad) as Err<RecipeMeasure>;
        expect(
          refused.failure.code,
          'recipe_measure/unit_cannot_measure',
          reason: bad.id,
        );
      }
      expect(
        (_author('blob', 1, unit: pinch) as Err).failure.message,
        '“pinch” is not a size, so it can’t say what one “blob” comes to. '
        'Say it as a weight, a volume or a count.',
      );
    });
  });

  group('a word needs a `makes` it can be held against', () {
    test('no yield at all: the refusal sends the person to MAKES', () {
      final refused =
          _author('blob', 15, yields: const []) as Err<RecipeMeasure>;
      expect(refused.failure.code, 'recipe_measure/no_yield');
      expect(refused.failure.message, kRecipeMeasureNoYieldRefusal);
      expect(refused.failure.message, contains('MAKES'));
    });

    test("it is the DOOR's gate, asked before anything is typed", () {
      // The MEASURES list is drawn disabled with this sentence under it, so the
      // gate has to answer first — before the label, the unit or the number.
      for (final label in ['', 'cup', 'blob']) {
        expect(
          (_author(label, null, unit: batches, yields: const []) as Err)
              .failure
              .code,
          'recipe_measure/no_yield',
          reason: label,
        );
      }
    });

    test('a unit whose family the recipe does not state is refused', () {
      final refused = _author('ladle', 180, unit: ml) as Err<RecipeMeasure>;
      expect(refused.failure.code, 'recipe_measure/unit_family');
      expect(
        refused.failure.message,
        'This recipe makes 300 g, so “ladle” can’t be said in ml — a recipe '
        'has no density to get from one to the other. Say it in what the batch '
        'is measured in, or add what a batch makes in ml under MAKES.',
      );
    });

    test('the second MAKES denomination is the way out, and it works', () {
      expect(
        _author('ladle', 180, unit: ml, yields: _both).valueOrNull?.unit,
        ml,
      );
      expect(_author('blob', 15, yields: _both).valueOrNull?.unit, g);
      // And the refusal names both stated denominations when there are two.
      final refused = _author('patty', 1, unit: pieces, yields: _both) as Err;
      // Kitchen fractions, as everywhere else the app prints an amount.
      expect(refused.failure.message, contains('makes 300 g · 1¼ cup'));
    });

    test('a count word is sayable exactly when the recipe counts', () {
      expect(
        _author(
          'patty',
          1,
          unit: pieces,
          yields: const [(qty: 8.0, unit: pieces)],
        ).valueOrNull?.unit,
        pieces,
      );
      expect(
        (_author('patty', 1, unit: pieces) as Err).failure.code,
        'recipe_measure/unit_family',
      );
    });

    test('it converts within the family — kg against a g yield', () {
      expect(_author('loaf', 0.3, unit: kg).valueOrNull?.amount, 0.3);
    });
  });

  group('recipeMeasuresOrphanedBy — the same rule, read backwards', () {
    final blob = _m('blob', 15);
    final ladle = _m('ladle', 180, unit: ml, id: 'm2');

    test('a `makes` that loses a family orphans the words in it', () {
      expect(
        recipeMeasuresOrphanedBy(
          measures: [blob, ladle],
          from: _both,
          to: const [(qty: 1.25, unit: cup)],
        ),
        [blob],
      );
    });

    test('dropping MAKES entirely orphans everything', () {
      expect(
        recipeMeasuresOrphanedBy(
          measures: [blob, ladle],
          from: _both,
          to: const [],
        ),
        [blob, ladle],
      );
    });

    test('re-stating the NUMBER orphans nothing — that is the point', () {
      expect(
        recipeMeasuresOrphanedBy(
          measures: [blob],
          from: _weighed,
          to: const [(qty: 600.0, unit: g)],
        ),
        isEmpty,
      );
    });

    test('a word already orphaned is not reported again', () {
      // The warning is about what THIS edit takes away; re-warning about a gap
      // already on screen teaches a person to dismiss the dialog.
      expect(
        recipeMeasuresOrphanedBy(
          measures: [ladle],
          from: _weighed,
          to: const [],
        ),
        isEmpty,
      );
    });

    test('an added denomination orphans nothing', () {
      expect(
        recipeMeasuresOrphanedBy(
          measures: [blob, ladle],
          from: _weighed,
          to: _both,
        ),
        isEmpty,
      );
    });
  });

  group('recipeMeasureAlreadyNamed', () {
    test('reads what a person would read as the same word', () {
      final blob = _m('blob', 15);
      expect(recipeMeasureAlreadyNamed(' BLOB ', [blob]), blob);
      expect(recipeMeasureAlreadyNamed('ladle', [blob]), isNull);
      expect(recipeMeasureAlreadyNamed('  ', [blob]), isNull);
    });
  });

  group('duplicates merge on read — the ingredient rule, mirrored', () {
    test('the oldest row of a word is canonical, the newer is hidden', () {
      final merged = mergeRecipeMeasures([
        (
          measure: _m('blob', 18, id: 'late'),
          createdAt: '2026-09-11T10:00:00Z',
        ),
        (
          measure: _m('blob', 15, id: 'early'),
          createdAt: '2026-09-10T10:00:00Z',
        ),
      ]);
      expect(merged.map((m) => m.id), ['early']);
      expect(merged.single.amount, 15);
    });

    test("two writers' date formats still agree about which is older", () {
      // Postgres syncs `… …Z`, this client writes `…T…Z`; a bare string
      // compare picks the wrong one, because a space sorts before `T`.
      final merged = mergeRecipeMeasures([
        (
          measure: _m('blob', 18, id: 'late'),
          createdAt: '2026-09-11T09:00:00Z',
        ),
        (
          measure: _m('blob', 15, id: 'early'),
          createdAt: '2026-09-10 09:00:00Z',
        ),
      ]);
      expect(merged.single.id, 'early');
    });

    test('a zoneless instant is read as UTC, so two devices agree', () {
      final merged = mergeRecipeMeasures([
        (measure: _m('blob', 18, id: 'late'), createdAt: '2026-09-11 09:00:00'),
        (
          measure: _m('blob', 15, id: 'early'),
          createdAt: '2026-09-10 09:00:00',
        ),
      ]);
      expect(merged.single.id, 'early');
    });

    test('the key is the label EXACTLY as stored — case included', () {
      // The authoring path is what stops a person minting the pair; the merge
      // hides only what the database actually let through.
      final merged = mergeRecipeMeasures([
        (measure: _m('Blob', 18, id: 'b'), createdAt: '2026-09-11T09:00:00Z'),
        (measure: _m('blob', 15, id: 'a'), createdAt: '2026-09-10T09:00:00Z'),
      ]);
      expect(merged.map((m) => m.label), ['blob', 'Blob']);
    });

    test('display order is sort_order, then age, then id', () {
      final merged = mergeRecipeMeasures([
        (
          measure: _m('ladle', 180, unit: ml, id: 'c', sortOrder: 1),
          createdAt: '2026-09-09T09:00:00Z',
        ),
        (measure: _m('blob', 15, id: 'b'), createdAt: '2026-09-11T09:00:00Z'),
        (
          measure: _m('patty', 1, unit: pieces, id: 'a'),
          createdAt: '2026-09-10T09:00:00Z',
        ),
      ]);
      expect(merged.map((m) => m.label), ['patty', 'blob', 'ladle']);
    });

    test('an unparseable or absent date still sorts deterministically', () {
      final merged = mergeRecipeMeasures([
        (measure: _m('blob', 18, id: 'z'), createdAt: null),
        (measure: _m('blob', 15, id: 'a'), createdAt: 'not a date'),
      ]);
      expect(merged.single.id, 'z');
    });
  });

  group('what the authoring form may offer', () {
    test(
      'the offer is every unit of a family MAKES states, in catalog order',
      () {
        expect(recipeMeasureUnitChoices(_weighed), [g, kg, oz, lb]);
        expect(recipeMeasureUnitChoices(_both), [
          g, kg, oz, lb, //
          ml, l, tsp, tbsp, flOz, cup, pint, quart,
        ]);
      },
    );

    test(
      '`batch`, an imprecise word and an unstated family are never in it',
      () {
        final offered = recipeMeasureUnitChoices(_both);
        expect(offered, isNot(contains(batches)));
        expect(offered, isNot(contains(pinch)));
        expect(
          offered,
          isNot(contains(pieces)),
          reason: 'no count yield stated',
        );
      },
    );

    test('a recipe that says nothing offers nothing — the disabled door', () {
      expect(recipeMeasureUnitChoices(const []), isEmpty);
      expect(recipeMeasureOpeningUnit(const []), isNull);
    });

    test(
      'a yield in a family no size can be said in offers nothing either',
      () {
        const pinched = [(qty: 2.0, unit: pinch)];
        expect(recipeMeasureUnitChoices(pinched), isEmpty);
        expect(recipeMeasureOpeningUnit(pinched), isNull);
      },
    );

    test('the form opens on the FIRST stated yield’s own unit', () {
      expect(recipeMeasureOpeningUnit(_both), g);
      expect(
        recipeMeasureOpeningUnit(const [
          (qty: 1.25, unit: cup),
          (qty: 300.0, unit: g),
        ]),
        cup,
      );
    });

    test('…and on the head of the offer where that unit cannot say a size', () {
      // A batch counted in something imprecise, with a weight stated beside it.
      expect(
        recipeMeasureOpeningUnit(const [
          (qty: 2.0, unit: pinch),
          (qty: 300.0, unit: g),
        ]),
        g,
      );
    });

    test('every offered unit really authors — the gate read both ways', () {
      for (final unit in recipeMeasureUnitChoices(_both)) {
        expect(
          _author('blob', 15, unit: unit, yields: _both),
          isA<Ok<RecipeMeasure>>(),
          reason: unit.id,
        );
      }
    });
  });
}
