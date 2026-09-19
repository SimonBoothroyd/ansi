import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_authoring.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeMeasure _m(
  String label,
  double perBatch, {
  String id = 'm1',
  int sortOrder = 0,
}) => RecipeMeasure(
  id: id,
  recipeId: 'aioli',
  label: label,
  perBatch: perBatch,
  sortOrder: sortOrder,
);

Result<RecipeMeasure> _author(
  String label,
  double? perBatch, {
  String id = 'new',
  List<RecipeMeasure> measures = const [],
}) => authorRecipeMeasure(
  id: id,
  recipeId: 'aioli',
  label: label,
  perBatch: perBatch,
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
    final blob = _m('blob', 20);

    test('a second row with the same word, ignoring case', () {
      final refused =
          _author('Blob', 6, measures: [blob]) as Err<RecipeMeasure>;
      expect(refused.failure.code, 'recipe_measure/word_taken');
      expect(
        refused.failure.message,
        '“blob” is already this recipe’s word, at 20 a batch. Re-state that '
        'one and every line saying it follows.',
      );
    });

    test('a row re-stating ITSELF is not its own duplicate', () {
      // The board's rule: the row keeps its id, so `blob` moving 20 → 24
      // follows through to every line already saying it.
      final restated = _author('blob', 24, id: 'm1', measures: [blob]);
      expect(restated.valueOrNull?.id, 'm1');
      expect(restated.valueOrNull?.perBatch, 24);
    });

    test('another recipe saying it is nothing to do with this one', () {
      expect(_author('blob', 20).valueOrNull?.label, 'blob');
    });
  });

  group('the number', () {
    test('missing, zero, negative or NaN is refused', () {
      for (final bad in [null, 0.0, -2.0, double.nan, double.infinity]) {
        final refused = _author('blob', bad);
        expect(refused, isA<Err<RecipeMeasure>>(), reason: '$bad');
        expect((refused as Err).failure.code, 'recipe_measure/per_batch');
      }
      expect(
        (_author('blob', 0) as Err).failure.message,
        'Say how many “blob” a batch makes — a number above zero.',
      );
    });

    test('a fraction of one is a number too', () {
      expect(_author('vat', 0.5).valueOrNull?.perBatch, 0.5);
    });
  });

  group('recipeMeasureAlreadyNamed', () {
    test('reads what a person would read as the same word', () {
      final blob = _m('blob', 20);
      expect(recipeMeasureAlreadyNamed(' BLOB ', [blob]), blob);
      expect(recipeMeasureAlreadyNamed('ladle', [blob]), isNull);
      expect(recipeMeasureAlreadyNamed('  ', [blob]), isNull);
    });
  });

  group('duplicates merge on read — the ingredient rule, mirrored', () {
    test('the oldest row of a word is canonical, the newer is hidden', () {
      final merged = mergeRecipeMeasures([
        (
          measure: _m('blob', 24, id: 'late'),
          createdAt: '2026-09-11T10:00:00Z',
        ),
        (
          measure: _m('blob', 20, id: 'early'),
          createdAt: '2026-09-10T10:00:00Z',
        ),
      ]);
      expect(merged.map((m) => m.id), ['early']);
      expect(merged.single.perBatch, 20);
    });

    test("two writers' date formats still agree about which is older", () {
      // Postgres syncs `… …Z`, this client writes `…T…Z`; a bare string
      // compare picks the wrong one, because a space sorts before `T`.
      final merged = mergeRecipeMeasures([
        (
          measure: _m('blob', 24, id: 'late'),
          createdAt: '2026-09-11T09:00:00Z',
        ),
        (
          measure: _m('blob', 20, id: 'early'),
          createdAt: '2026-09-10 09:00:00Z',
        ),
      ]);
      expect(merged.single.id, 'early');
    });

    test('a zoneless instant is read as UTC, so two devices agree', () {
      final merged = mergeRecipeMeasures([
        (measure: _m('blob', 24, id: 'late'), createdAt: '2026-09-11 09:00:00'),
        (
          measure: _m('blob', 20, id: 'early'),
          createdAt: '2026-09-10 09:00:00',
        ),
      ]);
      expect(merged.single.id, 'early');
    });

    test('the key is the label EXACTLY as stored — case included', () {
      // The authoring path is what stops a person minting the pair; the merge
      // hides only what the database actually let through.
      final merged = mergeRecipeMeasures([
        (measure: _m('Blob', 24, id: 'b'), createdAt: '2026-09-11T09:00:00Z'),
        (measure: _m('blob', 20, id: 'a'), createdAt: '2026-09-10T09:00:00Z'),
      ]);
      expect(merged.map((m) => m.label), ['blob', 'Blob']);
    });

    test('display order is sort_order, then age, then id', () {
      final merged = mergeRecipeMeasures([
        (
          measure: _m('ladle', 6, id: 'c', sortOrder: 1),
          createdAt: '2026-09-09T09:00:00Z',
        ),
        (measure: _m('blob', 20, id: 'b'), createdAt: '2026-09-11T09:00:00Z'),
        (measure: _m('patty', 8, id: 'a'), createdAt: '2026-09-10T09:00:00Z'),
      ]);
      expect(merged.map((m) => m.label), ['patty', 'blob', 'ladle']);
    });

    test('an unparseable or absent date still sorts deterministically', () {
      final merged = mergeRecipeMeasures([
        (measure: _m('blob', 24, id: 'z'), createdAt: null),
        (measure: _m('blob', 20, id: 'a'), createdAt: 'not a date'),
      ]);
      expect(merged.single.id, 'z');
    });
  });
}
