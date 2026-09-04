/// The ONE vocabulary for an incomplete macro summary, and the two helpers
/// seam D5/D6 add beside it.
///
/// Every sentence these helpers can print is pinned here: the summary-level
/// note for each reason a total is incomplete, a per-line word for every
/// reason there is, "not counted" the way the board drew it, and — the
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
    /// stay total; a bare count reads as the fix ("needs a weight"), never as
    /// the failure ("unconvertible").
    const vectors = <String, RecipeMacroSummary>{
      'no ingredients yet': RecipeMacroSummary(noLines: true),
      // Servings ≤ 0 with zero stub/unconvertible lines. The DB check makes
      // this near-unreachable, but the note must still answer.
      'servings not set': RecipeMacroSummary(),
      '2 stub lines': RecipeMacroSummary(stubLines: 2),
      '1 sub-recipe unresolved': RecipeMacroSummary(subRecipesUnresolved: 1),
      '2 sub-recipes unresolved': RecipeMacroSummary(subRecipesUnresolved: 2),
      '1 sub-recipe incomplete': RecipeMacroSummary(subRecipesIncomplete: 1),
      '1 line needs a weight': RecipeMacroSummary(countLinesWithoutMeasure: 1),
      '3 lines need a weight': RecipeMacroSummary(countLinesWithoutMeasure: 3),
      'nothing weighable yet': RecipeMacroSummary(nothingWeighable: true),
      // Unfolded from each other, in one sentence.
      '1 stub line · 3 sub-recipes incomplete': RecipeMacroSummary(
        stubLines: 1,
        subRecipesIncomplete: 3,
      ),
      '2 stub lines · 1 line needs a weight · 1 unconvertible':
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
        '2 stub lines · 1 line needs a weight · 1 unconvertible',
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
        MacroLineReason.needsWeight: 'needs a weight',
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

  group('notCountedNote: the exclusion, named', () {
    test("the board's own sentence", () {
      expect(
        notCountedNote([
          _note(MacroLineReason.imprecise, name: 'Parsley', unit: 'handful'),
          _note(
            MacroLineReason.imprecise,
            name: 'Sesame seeds',
            unit: 'to taste',
          ),
        ]),
        'not counted: Parsley · handful, Sesame seeds · to taste',
      );
    });

    test('optional lines are counted, then named', () {
      expect(
        notCountedNote([
          _note(MacroLineReason.optional, name: 'Lime'),
          _note(MacroLineReason.optional, name: 'Coriander'),
        ]),
        'not counted · 2 optional lines: Lime, Coriander',
      );
      expect(
        notCountedNote([_note(MacroLineReason.optional, name: 'Lime')]),
        'not counted · 1 optional line: Lime',
      );
    });

    test('imprecise and optional coincide on ONE line with both reasons', () {
      expect(
        notCountedNote([
          _note(MacroLineReason.optional, name: 'Lime'),
          _note(MacroLineReason.imprecise, name: 'Parsley', unit: 'handful'),
          _note(MacroLineReason.optional, name: 'Coriander'),
        ]),
        'not counted: Parsley · handful · 2 optional lines: Lime, Coriander',
      );
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

    test('the caption under the line says what applies, and where the switch '
        'is', () {
      expect(
        notCountedCaption(const RecipeMacroSummary(impreciseLines: 1)),
        contains('excluded by rule'),
      );
      expect(
        notCountedCaption(const RecipeMacroSummary(optionalLines: 1)),
        'optional lines are left out by rule, not by failure — untick '
        'Optional on a line to count it.',
      );
      expect(
        notCountedCaption(
          const RecipeMacroSummary(impreciseLines: 1, optionalLines: 1),
        ),
        allOf(contains('a pinch'), contains('untick Optional')),
      );
    });

    test('it names ONLY the by-rule exclusions — a stub is a defect, not an '
        'exclusion, and belongs in the fixable list', () {
      final notes = [
        _note(MacroLineReason.stubIngredient, name: 'Tofu'),
        _note(MacroLineReason.imprecise, name: 'Parsley', unit: 'handful'),
      ];
      expect(notCountedNote(notes), 'not counted: Parsley · handful');
      expect(
        fixableNotes(RecipeMacroSummary(notes: notes)).single.name,
        'Tofu',
      );
    });

    test('nothing excluded ⇒ null, so no surface prints a dangling label', () {
      expect(notCountedNote(const []), isNull);
      expect(notCountedNote([_note(MacroLineReason.needsWeight)]), isNull);
    });
  });
}
