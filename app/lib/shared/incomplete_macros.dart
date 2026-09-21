/// The one vocabulary for an incomplete macro summary: the amber
/// `incomplete` badge and the note that says why. Shared so every surface
/// rendering a [RecipeMacroSummary] refuses in the same words.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/macros.dart';
import '../core/words.dart';
import '../features/recipes/domain/recipe_macros.dart';

/// Why a summary is incomplete, for the row note: `1 stub line`, `1 line
/// needs a piece weight · 1 unconvertible`, `1 sub-recipe unresolved`. Never
/// an empty string.
///
/// "needs a piece weight" is its own reason: a bare count is fixed with one
/// number on the ingredient (ADR-0015), not a failed conversion.
String incompleteNote(RecipeMacroSummary summary) {
  if (summary.noLines) return 'no ingredients yet';
  // Every line was imprecise, so nothing was weighed; `0 kcal` would be a
  // fabrication.
  if (summary.nothingWeighable) return 'nothing weighable yet';
  // `stubLines` counts retired rows too; they are named apart here, and
  // first, because a broken link points at nothing.
  final removed = [
    for (final n in summary.notes)
      if (n.reason == MacroLineReason.removedIngredient) n,
  ].length;
  final stubs = summary.stubLines > removed ? summary.stubLines - removed : 0;
  final counts = summary.countLinesWithoutMeasure;
  final unresolved = summary.subRecipesUnresolved;
  final subIncomplete = summary.subRecipesIncomplete;
  final parts = [
    if (removed > 0) '$removed ${plural(removed, 'ingredient')} removed',
    if (stubs == 1) '1 stub line',
    if (stubs > 1) '$stubs stub lines',
    if (counts == 1) '1 line needs a piece weight',
    if (counts > 1) '$counts lines need a piece weight',
    if (summary.unconvertibleLines > 0)
      '${summary.unconvertibleLines} unconvertible',
    // The two sub-recipe reasons.
    if (unresolved > 0)
      '$unresolved ${plural(unresolved, 'sub-recipe')} unresolved',
    if (subIncomplete > 0)
      '$subIncomplete ${plural(subIncomplete, 'sub-recipe')} incomplete',
  ];
  // Lines exist and all joined, so the only cause left is a non-positive
  // serving count.
  return parts.isEmpty ? 'servings not set' : parts.join(' · ');
}

/// What one excluded line is waiting on: `Cucumber · needs a piece weight`.
///
/// [MacroLineReason.imprecise] has no wording here: such a line is named by
/// the word the source printed (see [impreciseNotCountedNames]).
String incompleteLineNote(MacroLineReason reason) => switch (reason) {
  MacroLineReason.stubIngredient => 'stub ingredient',
  MacroLineReason.unknownIngredient => 'not in your ingredients yet',
  // The fix is the line, not the row.
  MacroLineReason.removedIngredient => 'ingredient removed · pick again',
  MacroLineReason.needsWeight => 'needs a piece weight',
  MacroLineReason.needsDensity => 'needs a density',
  MacroLineReason.noAmount => 'no amount',
  MacroLineReason.subRecipeUnresolved => 'sub-recipe has no yield',
  MacroLineReason.subRecipeIncomplete => 'sub-recipe incomplete',
  MacroLineReason.imprecise => 'not counted',
  MacroLineReason.optional => 'optional',
};

/// The reasons a line leaves a total by rule rather than by failure. Named
/// under the total, never marked as fixable.
const Set<MacroLineReason> byRuleReasons = {
  MacroLineReason.imprecise,
  MacroLineReason.optional,
};

/// The lines a household could fix: everything not in [byRuleReasons].
List<MacroLineNote> fixableNotes(RecipeMacroSummary summary) => [
  for (final note in summary.notes)
    if (!byRuleReasons.contains(note.reason)) note,
];

/// `Cilantro · handful, Kosher Salt · to taste`: the imprecise lines a total
/// prints under itself, labelled `NOT COUNTED`, each with the unit word its
/// source printed. Null when there are none.
String? impreciseNotCountedNames(List<MacroLineNote> notes) {
  final names = [
    for (final n in notes)
      if (n.reason == MacroLineReason.imprecise)
        '${n.name} · ${n.unit ?? 'imprecise'}',
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// `Lime, Coriander`: the optional lines a total left out, labelled
/// `OPTIONAL`. Null when there are none.
String? optionalNotCountedNames(List<MacroLineNote> notes) {
  final names = [
    for (final n in notes)
      if (n.reason == MacroLineReason.optional) n.name,
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// `fibre not counted · 2 lines without it: Onion, Stock`: why an otherwise
/// whole total states no fibre ([Macros.fiber] is optional per ingredient).
///
/// Null when there is no total, when the total states fibre, or when no
/// line was missing it.
String? fiberNotCountedNote(RecipeMacroSummary summary) {
  final total = summary.perServing;
  if (total == null || total.fiber != null) return null;
  final names = summary.linesWithoutFiber;
  if (names.isEmpty) return null;
  return 'fibre not counted · ${names.length} '
      '${plural(names.length, 'line')} without it: ${names.join(', ')}';
}

/// The one caption under the named rows: these lines are out by rule.
const notCountedCaption =
    'Imprecise and optional lines are left out by rule, not by failure.';

/// The amber `incomplete` badge.
class IncompleteBadge extends StatelessWidget {
  const IncompleteBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AnsiColors.caution,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'incomplete',
        style: ansiMono(size: 9, color: AnsiColors.cautionInk),
      ),
    );
  }
}
