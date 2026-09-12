/// The ONE vocabulary for an incomplete macro summary, and the two helpers
/// seam D5/D6 add beside it.
///
/// Every sentence these helpers can print is pinned here: the summary-level
/// note for each reason a total is incomplete, a per-line word for every
/// reason there is, the two by-rule rows under a total, and — the
/// anti-drift pin — that an imprecise line contributes **nothing** to the
/// summary-level note, because it is not a reason a summary is incomplete.
///
/// The surfaces that RENDER these sentences assert them by calling the helper,
/// so the exact copy lives in exactly one place: here.
library;

import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/shared/incomplete_macros.dart';
import 'package:flutter_test/flutter_test.dart';

MacroLineNote _note(
  MacroLineReason reason, {
  String name = 'X',
  String? unit,
}) => (lineId: 'li', name: name, reason: reason, unit: unit);

void main() {
  group('incompleteNote: a reason, always, in one sentence', () {
    /// Every incomplete cause and the sentence it prints. A reasonless badge
    /// would leave a dangling separator on a picker row, so the note has to
    /// stay total; a bare count reads as the fix ("needs a piece weight" —
    /// one number on the INGREDIENT, ADR-0015), never as the failure
    /// ("unconvertible").
    const vectors = <String, RecipeMacroSummary>{
      'no ingredients yet': RecipeMacroSummary(noLines: true),
      // Servings ≤ 0 with zero stub/unconvertible lines. The DB check makes
      // this near-unreachable, but the note must still answer.
      'servings not set': RecipeMacroSummary(),
      '2 stub lines': RecipeMacroSummary(stubLines: 2),
      '1 sub-recipe unresolved': RecipeMacroSummary(subRecipesUnresolved: 1),
      '2 sub-recipes unresolved': RecipeMacroSummary(subRecipesUnresolved: 2),
      '1 sub-recipe incomplete': RecipeMacroSummary(subRecipesIncomplete: 1),
      '1 line needs a piece weight': RecipeMacroSummary(
        countLinesWithoutMeasure: 1,
      ),
      '3 lines need a piece weight': RecipeMacroSummary(
        countLinesWithoutMeasure: 3,
      ),
      'nothing weighable yet': RecipeMacroSummary(nothingWeighable: true),
      // Unfolded from each other, in one sentence.
      '1 stub line · 3 sub-recipes incomplete': RecipeMacroSummary(
        stubLines: 1,
        subRecipesIncomplete: 3,
      ),
      '2 stub lines · 1 line needs a piece weight · 1 unconvertible':
          RecipeMacroSummary(
            stubLines: 2,
            countLinesWithoutMeasure: 1,
            unconvertibleLines: 1,
          ),
    };

    for (final MapEntry(key: sentence, value: summary) in vectors.entries) {
      test('"$sentence"', () => expect(incompleteNote(summary), sentence));
    }
  });

  group('incompleteNote is untouched by the imprecise bucket', () {
    test('an imprecise line changes nothing a surface prints', () {
      const withImprecise = RecipeMacroSummary(
        stubLines: 2,
        countLinesWithoutMeasure: 1,
        unconvertibleLines: 1,
        impreciseLines: 3,
      );
      const without = RecipeMacroSummary(
        stubLines: 2,
        countLinesWithoutMeasure: 1,
        unconvertibleLines: 1,
      );
      expect(incompleteNote(withImprecise), incompleteNote(without));
      expect(
        incompleteNote(withImprecise),
        '2 stub lines · 1 line needs a piece weight · 1 unconvertible',
      );
    });

    test('the one guard gets its own words — not "servings not set", which '
        'would send the household to fix the wrong thing', () {
      expect(
        incompleteNote(
          const RecipeMacroSummary(impreciseLines: 2, nothingWeighable: true),
        ),
        'nothing weighable yet',
      );
    });
  });

  group('incompleteLineNote: a word for every reason', () {
    test('every reason has one, and no two fixable reasons share it', () {
      final words = {
        for (final reason in MacroLineReason.values)
          reason: incompleteLineNote(reason),
      };
      for (final entry in words.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key.name);
      }
      final fixable = [
        for (final e in words.entries)
          if (e.key != MacroLineReason.imprecise) e.value,
      ];
      expect(fixable.toSet(), hasLength(fixable.length));
    });

    test('the wordings the board drew', () {
      const drawn = {
        MacroLineReason.stubIngredient: 'stub ingredient',
        MacroLineReason.unknownIngredient: 'not in your ingredients yet',
        MacroLineReason.needsWeight: 'needs a piece weight',
        MacroLineReason.needsDensity: 'needs a density',
        MacroLineReason.noAmount: 'no amount',
        MacroLineReason.subRecipeUnresolved: 'sub-recipe has no yield',
        MacroLineReason.subRecipeIncomplete: 'sub-recipe incomplete',
        MacroLineReason.imprecise: 'not counted',
        MacroLineReason.optional: 'optional',
      };
      // The totality check is the point: a reason added without a word here
      // fails, rather than shipping a blank where the board drew a sentence.
      expect(drawn.keys, unorderedEquals(MacroLineReason.values));
      drawn.forEach((reason, word) {
        expect(incompleteLineNote(reason), word, reason: reason.name);
      });
    });
  });

  group('the exclusion, named in its own row', () {
    test("the imprecise row's names carry the word the source printed", () {
      expect(
        impreciseNotCountedNames([
          _note(MacroLineReason.imprecise, name: 'Parsley', unit: 'handful'),
          _note(
            MacroLineReason.imprecise,
            name: 'Sesame seeds',
            unit: 'to taste',
          ),
        ]),
        'Parsley · handful, Sesame seeds · to taste',
      );
    });

    test('a line with no printed unit still says it is imprecise', () {
      expect(
        impreciseNotCountedNames([
          _note(MacroLineReason.imprecise, name: 'Parsley'),
        ]),
        'Parsley · imprecise',
      );
    });

    test('the optional row is names alone — the label does the counting', () {
      expect(
        optionalNotCountedNames([
          _note(MacroLineReason.optional, name: 'Lime'),
          _note(MacroLineReason.optional, name: 'Coriander'),
        ]),
        'Lime, Coriander',
      );
    });

    test("the two rows never take each other's lines", () {
      final notes = [
        _note(MacroLineReason.optional, name: 'Lime'),
        _note(MacroLineReason.imprecise, name: 'Parsley', unit: 'handful'),
        _note(MacroLineReason.optional, name: 'Coriander'),
      ];
      expect(impreciseNotCountedNames(notes), 'Parsley · handful');
      expect(optionalNotCountedNames(notes), 'Lime, Coriander');
    });

    test('an optional line is by rule — never fixable, and its word is the '
        "page's tag", () {
      final notes = [
        _note(MacroLineReason.optional, name: 'Lime'),
        _note(MacroLineReason.stubIngredient, name: 'Tofu'),
      ];
      expect(
        fixableNotes(RecipeMacroSummary(notes: notes)).single.name,
        'Tofu',
      );
      expect(incompleteLineNote(MacroLineReason.optional), 'optional');
    });

    test('one caption covers both rows, and says rule rather than fault', () {
      expect(
        notCountedCaption,
        'Imprecise and optional lines are left out by rule, not by failure.',
      );
    });

    test('they name ONLY the by-rule exclusions — a stub is a defect, not an '
        'exclusion, and belongs in the fixable list', () {
      final notes = [
        _note(MacroLineReason.stubIngredient, name: 'Tofu'),
        _note(MacroLineReason.imprecise, name: 'Parsley', unit: 'handful'),
      ];
      expect(impreciseNotCountedNames(notes), 'Parsley · handful');
      expect(optionalNotCountedNames(notes), isNull);
      expect(
        fixableNotes(RecipeMacroSummary(notes: notes)).single.name,
        'Tofu',
      );
    });

    test('nothing excluded ⇒ null, so no surface prints a dangling label', () {
      expect(impreciseNotCountedNames(const []), isNull);
      expect(optionalNotCountedNames(const []), isNull);
      expect(
        impreciseNotCountedNames([_note(MacroLineReason.needsWeight)]),
        isNull,
      );
    });
  });
}
