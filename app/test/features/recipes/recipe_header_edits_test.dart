/// The header edit rules (plan 0025 #4) — one set, shared by the editor's
/// notifier and the import review's controller, so the two hosts of the
/// header form cannot leave different things behind.
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_header_edits.dart';
import 'package:flutter_test/flutter_test.dart';

const _blank = Recipe(id: 'r', title: 'T', servingsBase: 2);

void main() {
  test('a serving count is never zero or negative', () {
    expect(_blank.withServings(6).servingsBase, 6);
    expect(_blank.withServings(0).servingsBase, 1);
    expect(_blank.withServings(-3).servingsBase, 1);
  });

  group('the yield', () {
    test('both halves or neither', () {
      expect(_blank.withYield(250, g).yields, [(qty: 250.0, unit: g)]);
      expect(_blank.withYield(250, null).yields, isEmpty);
      expect(_blank.withYield(null, g).yields, isEmpty);
      expect(_blank.withYield(0, g).yields, isEmpty);
    });

    test('clearing the first denomination drops the second with it', () {
      final both = _blank.withYield(250, g).withSecondYield(16, tbsp);
      expect(both.yields, hasLength(2));
      final cleared = both.withYield(null, null);
      expect(cleared.yieldQty2, isNull);
      expect(cleared.yieldUnit2, isNull);
    });

    test('a second denomination needs a first, and another family', () {
      expect(_blank.withSecondYield(16, tbsp).yieldQty2, isNull);
      final first = _blank.withYield(250, g);
      // Same family as the first: refused, nothing changes.
      expect(first.withSecondYield(2, kg), first);
      expect(first.withSecondYield(16, tbsp).yieldQty2, 16);
      // Clearing the second alone leaves the first standing.
      final cleared = first
          .withSecondYield(16, tbsp)
          .withSecondYield(null, null);
      expect(cleared.yieldQty, 250);
      expect(cleared.yieldQty2, isNull);
    });
  });

  test('times are two typed facts: unset below one second, no rule between '
      'them', () {
    final timed = _blank.withCookTime(35 * 60).withTotalTime(20 * 60);
    expect(timed.cookTimeSeconds, 2100);
    // A total below the cook time is what somebody wrote — not refused.
    expect(timed.totalTimeSeconds, 1200);
    expect(timed.withCookTime(0).cookTimeSeconds, isNull);
    expect(timed.withTotalTime(null).totalTimeSeconds, isNull);
  });

  group('shelf life', () {
    test('fridge and freezer days clear below one', () {
      expect(_blank.withKeepsForDays(4).keepsForDays, 4);
      expect(_blank.withKeepsForDays(0).keepsForDays, isNull);
      final frozen = _blank.withFreezable(true).withFreezerDays(30);
      expect(frozen.freezerDays, 30);
      expect(frozen.withFreezerDays(-1).freezerDays, isNull);
    });

    test('a dish that stops freezing loses its freezer window', () {
      final thawed = _blank
          .withFreezable(true)
          .withFreezerDays(30)
          .withFreezable(false);
      expect(thawed.freezable, isFalse);
      expect(thawed.freezerDays, isNull);
    });
  });

  test('filing into another book clears the section; a section sets alone', () {
    final filed = _blank.withBook('b1').withSection('s1');
    expect((filed.bookId, filed.sectionId), ('b1', 's1'));
    final moved = filed.withBook('b2');
    expect((moved.bookId, moved.sectionId), ('b2', null));
    expect(moved.withSection('s2').sectionId, 's2');
    expect(moved.withSection(null).sectionId, isNull);
  });

  group('the recipe’s own words', () {
    const blob = RecipeMeasure(
      id: 'm-blob',
      recipeId: 'somewhere else',
      label: 'blob',
      amount: 15,
      unit: g,
      sortOrder: 7,
    );
    const loaf = RecipeMeasure(
      id: 'm-loaf',
      recipeId: 'r',
      label: 'loaf',
      amount: 300,
      unit: g,
    );

    test('every word is stamped with this recipe and with its position', () {
      final stated = _blank.withMeasures(const [loaf, blob]).measures;
      expect(stated.map((m) => m.id), ['m-loaf', 'm-blob']);
      expect(stated.map((m) => m.recipeId), ['r', 'r']);
      // The order IS the fact: the first word fronts a component's chip row.
      expect(stated.map((m) => m.sortOrder), [0, 1]);
    });

    test('a `makes` edit leaves the words alone — an amount is absolute', () {
      final recipe = _blank.withYield(300, g).withMeasures(const [blob]);
      final restated = recipe.withYield(600, g);
      expect(restated.measures, recipe.measures);
      // And clearing it does not delete them either: the editor warns, and the
      // words stay for MAKES to say that family again.
      expect(restated.withYield(null, null).measures, recipe.measures);
    });

    test('dropping a word is just a shorter list', () {
      final one = _blank.withMeasures(const [loaf, blob]);
      expect(one.withMeasures([one.measures.first]).measures, hasLength(1));
      expect(one.withMeasures(const []).measures, isEmpty);
    });
  });
}
