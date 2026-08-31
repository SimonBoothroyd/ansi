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

  group('allLinesValid (the Save gate)', () {
    test('true only when every line is clean', () {
      expect(allLinesValid({0: const [], 1: const []}), isTrue);
      expect(
        allLinesValid({0: const [], 1: const [LineIssue.unmatched]}),
        isFalse,
      );
    });
  });
}
