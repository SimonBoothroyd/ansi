/// The ONE vocabulary for an incomplete macro summary, and the two helpers
/// seam D5/D6 add beside it.
///
/// The summary-level `incompleteNote` vectors live with the picker rows
/// (`features/planning/recipe_picker_sheet_test.dart`), where they were
/// written; what is pinned HERE is that the new per-line words exist for every
/// reason, that "not counted" reads the way the board drew it, and — the
/// anti-drift pin — that an imprecise line contributes **nothing** to the
/// summary-level note, because it is not a reason a summary is incomplete.
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
  group('incompleteNote is untouched by the imprecise bucket (D6)', () {
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

  group('incompleteLineNote (D5): a word for every reason', () {
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
      expect(incompleteLineNote(MacroLineReason.needsWeight), 'needs a weight');
      expect(
        incompleteLineNote(MacroLineReason.stubIngredient),
        'stub ingredient',
      );
      expect(
        incompleteLineNote(MacroLineReason.unknownIngredient),
        'not in your ingredients yet',
      );
      expect(
        incompleteLineNote(MacroLineReason.needsDensity),
        'needs a density',
      );
      expect(incompleteLineNote(MacroLineReason.noAmount), 'no amount');
      expect(
        incompleteLineNote(MacroLineReason.subRecipeUnresolved),
        'sub-recipe has no yield',
      );
      expect(
        incompleteLineNote(MacroLineReason.subRecipeIncomplete),
        'sub-recipe incomplete',
      );
    });
  });

  group('notCountedNote (D6): the exclusion, named', () {
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
