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

/// A recipe that coins no word at all.
const _none = <RecipeMeasure>[];

void main() {
  group('the units half', () {
    List<String> units(SubRecipeTarget target) =>
        _labels(componentUnitChoices(target, _none));

    test('a yield-less recipe offers batch and nothing else', () {
      expect(units(_target()), ['batch']);
    });

    test('a "makes 1 cup" yield opens its family, kitchen-trimmed', () {
      final offered = units(_target(qty: 1, unit: cup));
      expect(offered, ['batch', 'cup', 'tbsp', 'tsp', 'ml', 'pt', 'qt']);
      // Label-reading granularity is not kitchen granularity.
      expect(offered, isNot(contains(flOz.label)));
      expect(offered, isNot(contains(l.label)));
    });

    test('two denominations open both families', () {
      expect(units(_target(qty: 250, unit: g, qty2: 16, unit2: tbsp)), [
        'batch',
        'g',
        'kg',
        'tbsp',
        'cup',
        'tsp',
        'ml',
        'pt',
        'qt',
      ]);
    });

    test(
      'a mass-only yield does NOT open volume — no density for a recipe',
      () {
        expect(units(_target(qty: 250, unit: g)), ['batch', 'g', 'kg']);
      },
    );

    test('a count yield offers pieces', () {
      expect(units(_target(qty: 8, unit: pieces)), ['batch', pieces.label]);
    });

    test('a stored unit the rule already offers is not flagged', () {
      final offer = componentUnitChoices(
        _target(qty: 1, unit: cup),
        _none,
        current: const UnitOption(tbsp),
      );
      expect(offer.offFilter, isNull);
      expect(
        offer.choices.where((c) => c == const UnitOption(tbsp)),
        hasLength(1),
      );
    });
  });

  group("componentUnitChoices — the recipe's own words lead", () {
    test("words first, then batch, then the yields' families", () {
      final offer = componentUnitChoices(_target(qty: 1, unit: cup), [
        _m('blob', 15, unit: ml),
        _m('ladle', 60, unit: ml, id: 'm2', sortOrder: 1),
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

    test('a word the recipe cannot hold is not offered', () {
      // The honest cost of the amount rule: a 15 g blob against a recipe that
      // only says `makes 1 cup` resolves to nothing, so a chip for it would
      // only ever produce a refusal — and the fix is MAKES, not this row.
      final offer = componentUnitChoices(_target(qty: 1, unit: cup), [
        _m('blob', 15),
        _m('ladle', 60, unit: ml, id: 'm2'),
      ]);
      expect(_labels(offer).take(2), ['ladle', 'batch']);
      expect(_labels(offer), isNot(contains('blob')));
    });

    test('a recipe with no yield at all can hold no word', () {
      final offer = componentUnitChoices(_target(), [_m('blob', 15)]);
      expect(_labels(offer), ['batch']);
    });

    test('no words is exactly the offer this file gave before', () {
      final offer = componentUnitChoices(_target(qty: 250, unit: g), _none);
      expect(_labels(offer), ['batch', 'g', 'kg']);
    });

    test('a word whose number says nothing is not offered', () {
      final offer = componentUnitChoices(_target(qty: 250, unit: g), [
        _m('blob', 0),
        _m('ladle', 60, id: 'm2'),
      ]);
      expect(_labels(offer).take(2), ['ladle', 'batch']);
    });

    test('the stored selection is always offered, flagged off-filter', () {
      const stored = UnitOption(tbsp);
      final offer = componentUnitChoices(
        _target(qty: 250, unit: g),
        _none,
        current: stored,
      );
      expect(offer.offFilter, stored);
      expect(offer.choices.last, stored);
    });

    test('a merge-hidden word is admitted the same way', () {
      final hidden = RecipeMeasureOption(_m('blob', 18, id: 'dupe'));
      final offer = componentUnitChoices(_target(qty: 250, unit: g), [
        _m('ladle', 60),
      ], current: hidden);
      expect(offer.offFilter, hidden);
      expect(_labels(offer), ['ladle', 'batch', 'g', 'kg', 'blob']);
    });

    test('and so is an ORPHANED word, when a line already says it', () {
      // A `makes` restated from grams into cups takes `blob` out of the offer —
      // but a line that says `blob` still reads `blob`, off-filter, with the
      // refusal under it. Never silently a number in some other unit.
      final blob = RecipeMeasureOption(_m('blob', 15));
      final offer = componentUnitChoices(_target(qty: 1, unit: cup), [
        _m('blob', 15),
      ], current: blob);
      expect(offer.offFilter, blob);
      expect(offer.choices.last, blob);
    });
  });

  group('wholeMeasureOfRecipe — found, never stored', () {
    /// "makes 900 g" — the bread.
    const bread = [(qty: 900.0, unit: g)];

    test('the word for the WHOLE yield, within the one tolerance', () {
      expect(wholeMeasureOfRecipe([_m('loaf', 900)], bread)?.label, 'loaf');
      expect(wholeMeasureOfRecipe([_m('loaf', 904)], bread)?.label, 'loaf');
      expect(wholeMeasureOfRecipe([_m('loaf', 450)], bread), isNull);
      expect(wholeMeasureOfRecipe(const [], bread), isNull);
    });

    test('it converts to get there — 0.9 kg is a 900 g batch', () {
      expect(
        wholeMeasureOfRecipe([_m('loaf', 0.9, unit: kg)], bread)?.label,
        'loaf',
      );
    });

    test('a word in a family the recipe does not state is not the whole', () {
      expect(wholeMeasureOfRecipe([_m('loaf', 900)], const []), isNull);
      expect(
        wholeMeasureOfRecipe([_m('loaf', 900)], const [(qty: 1.0, unit: cup)]),
        isNull,
      );
    });

    test('it moves when `makes` does, which is the truth', () {
      // A batch restated to 1.8 kg makes the loaf half of one, so it stops
      // leading — the word did not change, what it is a share of did.
      final loaf = [_m('loaf', 900)];
      expect(wholeMeasureOfRecipe(loaf, bread)?.label, 'loaf');
      expect(wholeMeasureOfRecipe(loaf, const [(qty: 1.8, unit: kg)]), isNull);
    });

    test('it leads the offer, and batch stays right behind it', () {
      final offer = componentUnitChoices(_target(qty: 900, unit: g), [
        _m('blob', 15),
        _m('loaf', 900, id: 'm2', sortOrder: 1),
      ]);
      expect(_labels(offer).take(3), ['loaf', 'blob', 'batch']);
    });

    test('and it is what a fresh component amount opens on', () {
      final target = _target(qty: 900, unit: g);
      expect(
        firstComponentChoice(target, [
          _m('blob', 15),
          _m('loaf', 900, id: 'm2'),
        ]),
        RecipeMeasureOption(_m('loaf', 900, id: 'm2')),
      );
      expect(
        firstComponentChoice(target, [_m('blob', 15)]),
        RecipeMeasureOption(_m('blob', 15)),
      );
      expect(firstComponentChoice(target, _none), const UnitOption(batches));
      // A word the recipe cannot hold is not what a fresh amount opens on.
      expect(
        firstComponentChoice(_target(qty: 1, unit: cup), [_m('blob', 15)]),
        const UnitOption(batches),
      );
    });

    test('a tie resolves by sort_order then label, on every device', () {
      expect(
        wholeMeasureOfRecipe([
          _m('round', 900, id: 'b', sortOrder: 1),
          _m('loaf', 900, id: 'c'),
        ], bread)?.label,
        'loaf',
      );
      expect(
        wholeMeasureOfRecipe([
          _m('round', 900, id: 'b'),
          _m('boule', 900, id: 'c'),
        ], bread)?.label,
        'boule',
      );
    });

    test('a word is never singled out by what it says', () {
      // Nothing here knows `loaf` from `patty`: only the number is read.
      for (final word in ['loaf', 'patty', 'glob', 'batchling']) {
        expect(
          wholeMeasureOfRecipe([_m(word, 900)], bread)?.label,
          word,
          reason: word,
        );
      }
    });
  });
}
