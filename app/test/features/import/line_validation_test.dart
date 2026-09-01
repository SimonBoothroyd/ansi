import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/import/domain/line_resolution.dart';
import 'package:mise/features/import/domain/line_validation.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';

const _garlic = Ingredient(
  id: 'i-garlic',
  canonicalName: 'Garlic',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

const _clove = Measure(id: 'm-clove', label: 'clove', amount: 3);

LineResolution _res({
  String? chosenIngredientId,
  String? createStubName,
  bool isRange = false,
  double? quantity,
  String? unit,
}) => LineResolution(
  lineIndex: 0,
  band: MatchBand.suggest,
  ingredientText: 'garlic',
  isRange: isRange,
  unit: unit,
  chosenIngredientId: chosenIngredientId,
  createStubName: createStubName,
  quantity: quantity,
);

void main() {
  group('acceptableUnitTokens (allowed set + measures + imprecise)', () {
    test('a mass ingredient admits its catalog units, its measures, and the '
        'always-on imprecise units — nothing else', () {
      final tokens = acceptableUnitTokens(_garlic, const [_clove]);
      expect(tokens, containsAll(<String>['g', 'kg'])); // mass default set
      expect(tokens, contains('clove')); // its measure, by label
      expect(
        tokens,
        containsAll(<String>['pinch', 'dash', 'handful', 'to_taste']),
      );
      // A volume unit is NOT admitted (no density) — enforcement, not anything.
      expect(tokens, isNot(contains('ml')));
    });
  });

  group('acceptableUnitChips (inline "did you mean" for the unit)', () {
    test('offers allowed units + measures + imprecise as chips', () {
      final chips = acceptableUnitChips(_garlic, const [_clove]);
      final tokens = chips.map((c) => c.token).toSet();
      expect(tokens, containsAll(<String>['g', 'kg', 'clove']));
      expect(tokens, contains('to_taste'));
      // Every chip is a token the amount sheet could produce — so tapping one
      // is always valid (it never re-seeds an invalid unit).
      final acceptable = acceptableUnitTokens(_garlic, const [_clove]);
      expect(tokens.every(acceptable.contains), isTrue);
    });
  });

  group('lineIssues', () {
    test('unmatched line → unmatched', () {
      expect(lineIssues(_res()), [LineIssue.unmatched]);
    });

    test('matched range with no picked number → rangeUnpicked', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', isRange: true),
        ingredient: _garlic,
      );
      expect(issues, contains(LineIssue.rangeUnpicked));
    });

    test('a unit outside the ingredient allowed set → unitNotAllowed', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', quantity: 1, unit: 'ml'),
        ingredient: _garlic,
      );
      expect(issues, [LineIssue.unitNotAllowed]);
    });

    test("D4b: deleting an ingredient's density degrades a line already "
        'saying a cross-family unit — flagged, never rewritten', () {
      // The mango shape before and after the density is deleted. The line is
      // byte-identical in both calls: nothing rewrites what the user wrote,
      // and the only thing that changes is whether the unit is still
      // supported (plan 0020 D4b — `clearDensity` strips the admission, this
      // is what the recipe side then sees).
      const line = 'cup';
      const withDensity = Ingredient(
        id: 'i-mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        densityGPerMl: 0.66,
        allowedUnits: [pieces, g, tsp, tbsp, cup, ml],
      );
      const stripped = Ingredient(
        id: 'i-mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        allowedUnits: [pieces, g],
      );

      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-mango', quantity: 1, unit: line),
          ingredient: withDensity,
        ),
        isEmpty,
      );
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-mango', quantity: 1, unit: line),
          ingredient: stripped,
        ),
        [LineIssue.unitNotAllowed],
      );
    });

    test('D4c: a line saying a unit only the DEFAULT unit used to admit '
        'degrades the same way — a stale allowed list does not make it '
        'sayable', () {
      // The renamed-rice shape: cup default, per-100 g macros, no density,
      // and an `allowed_units` list materialized under the looser pre-D4c
      // rule (the server still writes those, and this is what stops one from
      // smuggling an unconvertible unit onto a line).
      const rice = Ingredient(
        id: 'i-rice',
        canonicalName: 'Black rice',
        defaultUnit: cup,
        status: IngredientStatus.stub,
        allowedUnits: [cup, tbsp, ml, l, g, kg],
      );
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-rice', quantity: 1, unit: 'cup'),
          ingredient: rice,
        ),
        [LineIssue.unitNotAllowed],
      );
      // Flagged, never rewritten — and honest again the moment a density
      // bridges the two families.
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-rice', quantity: 1, unit: 'cup'),
          ingredient: rice.copyWith(densityGPerMl: 0.75),
        ),
        isEmpty,
      );
    });

    test('a measure-label unit is allowed when the ingredient has it', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', quantity: 2, unit: 'clove'),
        ingredient: _garlic,
        measures: const [_clove],
      );
      expect(issues, isEmpty);
    });

    test('an imprecise unit is always allowed (to serve)', () {
      final issues = lineIssues(
        _res(createStubName: 'Aleppo chilli', unit: 'to_taste'),
        // A create-new stub validates against a plain g-shaped stub.
        ingredient: const Ingredient(
          id: 'stub',
          canonicalName: 'Aleppo chilli',
          defaultUnit: g,
          status: IngredientStatus.stub,
        ),
      );
      expect(issues, isEmpty);
    });

    test('a matched line with an allowed unit is clean', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', quantity: 400, unit: 'g'),
        ingredient: _garlic,
      );
      expect(issues, isEmpty);
    });
  });

  group('rankedUnitChips (5 visible, the rest behind the fold)', () {
    // The Tomato-shaped flood: a dozen-plus admissible chips.
    final chips = acceptableUnitChips(
      const Ingredient(
        id: 'i-tom',
        canonicalName: 'Tomato',
        defaultUnit: g,
        status: IngredientStatus.complete,
        densityGPerMl: 1,
      ),
      const [
        Measure(id: 'm-small', label: 'small', amount: 90),
        Measure(id: 'm-large', label: 'large', amount: 180),
      ],
    );

    test('the parsed unit leads, then its family', () {
      final ranked = rankedUnitChips(chips, parsedUnit: 'kg');
      expect(ranked.first.token, 'kg');
      // The rest of the mass family comes next, before any measure.
      expect(ranked[1].token, 'g');
    });

    test('measures beat the generic g, and keep their given order', () {
      final ranked = rankedUnitChips(chips, parsedUnit: 'ml');
      final tokens = ranked.map((c) => c.token).toList();
      expect(tokens.indexOf('small'), lessThan(tokens.indexOf('large')));
      expect(tokens.indexOf('large'), lessThan(tokens.indexOf('g')));
    });

    test('the imprecise words fold — they are last', () {
      final visible = rankedUnitChips(
        chips,
        parsedUnit: 'kg',
      ).take(kVisibleUnitChips).map((c) => c.token).toSet();
      expect(visible, isNot(contains('to_taste')));
      expect(visible, isNot(contains('pinch')));
      expect(visible, hasLength(kVisibleUnitChips));
    });

    test('an imprecise parsed amount fronts the imprecise family instead', () {
      final visible = rankedUnitChips(
        chips,
        parsedUnit: 'pinch',
      ).take(kVisibleUnitChips).map((c) => c.token).toList();
      expect(visible.first, 'pinch');
      expect(visible, contains('to_taste'));
    });

    test('the fold hides nothing — every chip survives the ranking', () {
      final ranked = rankedUnitChips(chips, parsedUnit: 'clove');
      expect(ranked.toSet(), chips.toSet());
      expect(ranked, hasLength(chips.length));
    });

    test('the owner’s garlic, exactly as the cloud carries it: the printed '
        '"clove" leads, measures beat generic, imprecise last (J2)', () {
      // Piece default, an explicit [piece, g] list, a `clove` measure, no
      // density — and a line that printed "1 clove". The Pixel screenshot read
      // "g piece pinch dash handful (+1 more)", which is precisely this
      // ranking run over an EMPTY measure list: the ordering never degraded,
      // the measures never arrived (see import_validation_test.dart).
      const garlic = Ingredient(
        id: 'i-garlic',
        canonicalName: 'Garlic',
        defaultUnit: pieces,
        category: 'produce',
        status: IngredientStatus.complete,
        allowedUnits: [pieces, g],
      );
      final garlicChips = acceptableUnitChips(garlic, const [_clove]);
      final ranked = rankedUnitChips(
        garlicChips,
        parsedUnit: 'clove',
      ).map((c) => c.token).toList();

      expect(ranked.first, 'clove');
      expect(ranked.indexOf('clove'), lessThan(ranked.indexOf('g')));
      expect(ranked.indexOf('g'), lessThan(ranked.indexOf('handful')));
      expect(ranked.last, 'to_taste');
      // The line's own unit is never behind the fold.
      expect(ranked.take(kVisibleUnitChips), contains('clove'));
      // And the fold still hides nothing.
      expect(ranked.toSet(), garlicChips.map((c) => c.token).toSet());
    });
  });

  group('preselectedMeasure (one confirm tap, not a scroll-and-choose)', () {
    test('an inadmissible unit on a measured ingredient pre-picks the first '
        'measure', () {
      final picked = preselectedMeasure(
        _garlic,
        const [_clove],
        unit: 'ml', // garlic has no density: not admissible
      );
      expect(picked, _clove);
    });

    test('an admissible unit pre-picks nothing', () {
      expect(preselectedMeasure(_garlic, const [_clove], unit: 'g'), isNull);
      expect(
        preselectedMeasure(_garlic, const [_clove], unit: 'clove'),
        isNull,
      );
    });

    test('no unit, or no measure to offer, pre-picks nothing', () {
      expect(preselectedMeasure(_garlic, const [_clove], unit: null), isNull);
      expect(preselectedMeasure(_garlic, const [], unit: 'ml'), isNull);
    });

    test('a volume-named measure is skipped — density owns volume', () {
      expect(
        preselectedMeasure(_garlic, const [
          Measure(id: 'm-cup', label: 'cup', amount: 120),
        ], unit: 'ml'),
        isNull,
      );
    });
  });

  group('allLinesValid (the Save gate)', () {
    test('true only when every line is clean', () {
      expect(allLinesValid({0: const [], 1: const []}), isTrue);
      expect(
        allLinesValid({
          0: const [],
          1: const [LineIssue.unmatched],
        }),
        isFalse,
      );
    });
  });
}
