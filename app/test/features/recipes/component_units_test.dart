/// The component sheet's chip offer (step 8.6 / D2, board frame d): `batch` ∪
/// the yields' families, kitchen-trimmed, with the stored selection always
/// admitted.
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_units.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
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

SubRecipeTarget _target({double? qty, Unit? unit, double? qty2, Unit? unit2}) =>
    SubRecipeTarget(
      id: 'aioli',
      title: 'Romesco Aioli',
      yieldQty: qty,
      yieldUnit: unit,
      yieldQty2: qty2,
      yieldUnit2: unit2,
    );

List<String> _labels(UnitChoiceOffer offer) => [
  for (final c in offer.choices) c.label,
];

void main() {
  test('a yield-less recipe offers batch and nothing else', () {
    final offer = componentUnitChips(yields: const []);
    expect(offer.chips, [batches]);
    expect(offer.offFilter, isNull);
  });

  test('a "makes 1 cup" yield opens its family, kitchen-trimmed', () {
    // The board's frame-d row — batch | cup tbsp tsp ml — plus the US pair
    // at the tail (plan 0025 #2).
    final offer = componentUnitChips(yields: [(qty: 1, unit: cup)]);
    expect(offer.chips, [batches, cup, tbsp, tsp, ml, pint, quart]);
    // Label-reading granularity is not kitchen granularity.
    expect(offer.chips, isNot(contains(flOz)));
    expect(offer.chips, isNot(contains(l)));
  });

  test('two denominations open both families — the owner amendment', () {
    final offer = componentUnitChips(
      yields: [(qty: 250, unit: g), (qty: 16, unit: tbsp)],
    );
    expect(offer.chips, [batches, g, kg, tbsp, cup, tsp, ml, pint, quart]);
  });

  test('a mass-only yield does NOT open volume — no density for a recipe', () {
    final offer = componentUnitChips(yields: [(qty: 250, unit: g)]);
    expect(offer.chips, [batches, g, kg]);
    expect(offer.chips, isNot(contains(tbsp)));
  });

  test('a count yield offers pieces', () {
    final offer = componentUnitChips(yields: [(qty: 8, unit: pieces)]);
    expect(offer.chips, [batches, pieces]);
  });

  test('the stored unit is always admitted, and flagged off-filter', () {
    // An imported line printed "2 tbsp" of a butter that only says 250 g: the
    // chip stays, so the sheet never silently rewrites what the page printed.
    final offer = componentUnitChips(
      yields: [(qty: 250, unit: g)],
      stored: tbsp,
    );
    expect(offer.chips.last, tbsp);
    expect(offer.offFilter, tbsp);
  });

  test('a stored unit the rule already offers is not flagged', () {
    final offer = componentUnitChips(
      yields: [(qty: 1, unit: cup)],
      stored: tbsp,
    );
    expect(offer.offFilter, isNull);
    expect(offer.chips.where((u) => u == tbsp), hasLength(1));
  });

  group('componentUnitChoices — the recipe\'s own words lead', () {
    test('words first, then batch, then the yields\' families', () {
      final offer = componentUnitChoices(_target(qty: 1, unit: cup), [
        _m('blob', 20),
        _m('ladle', 6, id: 'm2', sortOrder: 1),
      ]);
      expect(_labels(offer), [
        'blob',
        'ladle',
        'batch',
        'cup',
        'tbsp',
        'tsp',
        'ml',
        'pt',
        'qt',
      ]);
      expect(offer.offFilter, isNull);
    });

    test('a recipe with no yield at all still says its own words', () {
      // The whole point: a sauce nobody measured is sayable in the words the
      // household uses for it.
      final offer = componentUnitChoices(_target(), [_m('blob', 20)]);
      expect(_labels(offer), ['blob', 'batch']);
    });

    test('no words is exactly the offer this file gave before', () {
      final offer = componentUnitChoices(_target(qty: 250, unit: g), const []);
      expect(_labels(offer), ['batch', 'g', 'kg']);
    });

    test('a word whose number says nothing is not offered', () {
      final offer = componentUnitChoices(_target(), [
        _m('blob', 0),
        _m('ladle', 6, id: 'm2'),
      ]);
      expect(_labels(offer), ['ladle', 'batch']);
    });

    test('the stored selection is always offered, flagged off-filter', () {
      const stored = UnitOption(tbsp);
      final offer = componentUnitChoices(
        _target(qty: 250, unit: g),
        const [],
        current: stored,
      );
      expect(offer.offFilter, stored);
      expect(offer.choices.last, stored);
    });

    test('a merge-hidden word is admitted the same way', () {
      final hidden = RecipeMeasureOption(_m('blob', 24, id: 'dupe'));
      final offer = componentUnitChoices(_target(), [
        _m('ladle', 6),
      ], current: hidden);
      expect(offer.offFilter, hidden);
      expect(_labels(offer), ['ladle', 'batch', 'blob']);
    });
  });

  group('wholeMeasureOfRecipe — found, never stored', () {
    test('the word for one whole batch, within the app\'s one tolerance', () {
      expect(wholeMeasureOfRecipe([_m('loaf', 1)])?.label, 'loaf');
      expect(wholeMeasureOfRecipe([_m('loaf', 1.005)])?.label, 'loaf');
      expect(wholeMeasureOfRecipe([_m('loaf', 1.5)]), isNull);
      expect(wholeMeasureOfRecipe(const []), isNull);
    });

    test('it leads the offer, and batch stays right behind it', () {
      final offer = componentUnitChoices(_target(qty: 900, unit: g), [
        _m('blob', 20),
        _m('loaf', 1, id: 'm2', sortOrder: 1),
      ]);
      expect(_labels(offer).take(3), ['loaf', 'blob', 'batch']);
    });

    test('and it is what a fresh component amount opens on', () {
      final target = _target(qty: 900, unit: g);
      expect(
        firstComponentChoice(target, [_m('blob', 20), _m('loaf', 1, id: 'm2')]),
        RecipeMeasureOption(_m('loaf', 1, id: 'm2')),
      );
      expect(
        firstComponentChoice(target, [_m('blob', 20)]),
        RecipeMeasureOption(_m('blob', 20)),
      );
      expect(firstComponentChoice(target, const []), const UnitOption(batches));
    });

    test('a tie resolves by sort_order then label, on every device', () {
      expect(
        wholeMeasureOfRecipe([
          _m('round', 1, id: 'b', sortOrder: 1),
          _m('loaf', 1, id: 'c', sortOrder: 0),
        ])?.label,
        'loaf',
      );
      expect(
        wholeMeasureOfRecipe([
          _m('round', 1, id: 'b'),
          _m('boule', 1, id: 'c'),
        ])?.label,
        'boule',
      );
    });

    test('a word is never singled out by what it says', () {
      // Nothing here knows `loaf` from `patty`: only the number is read.
      for (final word in ['loaf', 'patty', 'glob', 'batchling']) {
        expect(wholeMeasureOfRecipe([_m(word, 1)])?.label, word, reason: word);
      }
    });
  });
}
