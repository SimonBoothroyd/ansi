/// The ONE vocabulary for an honestly-incomplete macro summary — the amber
/// `incomplete` badge (design board `.badge-inc`) and the note that says why.
///
/// Three surfaces render the same [RecipeMacroSummary]: the recipe picker's
/// rows, the confirm sheet's picked card, and the recipe page's macro panel
/// (step 9). Invariant 3 is only credible if they all refuse in the *same
/// words* — a panel that said "macros unavailable" while the picker said
/// "1 stub line" would read as two different failures. They live here so
/// they cannot drift (the same reason `MethodStepText` was hoisted).
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../features/recipes/domain/recipe_macros.dart';

/// Why a summary is incomplete, for the row note: `no ingredients yet`,
/// `1 stub line`, `2 stub lines · 1 line needs a weight · 1 unconvertible`,
/// `1 sub-recipe unresolved` — never an empty string (a reasonless badge
/// would leave a dangling separator).
///
/// **"needs a weight" is its own reason** (plan 0022 **D6**), not part of
/// "unconvertible". A bare count — "2 pieces", no measure behind it — is the
/// one incomplete cause a household can fix in two taps, and calling it a
/// failed conversion described the wrong problem: nothing was ever weighed.
/// Under the ADR-0010 admission model those taps are unambiguous, because the
/// row's chip row holds its measures and (mostly) not `piece`.
String incompleteNote(RecipeMacroSummary summary) {
  if (summary.noLines) return 'no ingredients yet';
  // Seam D6's one guard: every line was imprecise, so nothing was weighed.
  // `0 kcal` there would be a fabrication — the same shape as no ingredients
  // at all, and it gets its own words rather than being folded into a bucket
  // that names a defect.
  if (summary.nothingWeighable) return 'nothing weighable yet';
  final stubs = summary.stubLines;
  final counts = summary.countLinesWithoutMeasure;
  final unresolved = summary.subRecipesUnresolved;
  final subIncomplete = summary.subRecipesIncomplete;
  final parts = [
    if (stubs == 1) '1 stub line',
    if (stubs > 1) '$stubs stub lines',
    if (counts == 1) '1 line needs a weight',
    if (counts > 1) '$counts lines need a weight',
    if (summary.unconvertibleLines > 0)
      '${summary.unconvertibleLines} unconvertible',
    // Step 8.6 / D8 — the two sub-recipe reasons, in the same voice as the
    // rest so no surface has to invent its own words for a nested refusal.
    if (unresolved > 0)
      '$unresolved sub-recipe${unresolved == 1 ? '' : 's'} unresolved',
    if (subIncomplete > 0)
      '$subIncomplete sub-recipe${subIncomplete == 1 ? '' : 's'} incomplete',
  ];
  // Every line joined and there are lines — the only remaining cause is a
  // non-positive serving count (the DB check makes this near-unreachable).
  return parts.isEmpty ? 'servings not set' : parts.join(' · ');
}

/// What ONE excluded line is waiting on — the per-line half of the same
/// vocabulary (seam **D5**). The panel's list, a row's marker and the picker
/// row all read this, so `Cucumber · needs a weight` says the same thing
/// wherever it appears.
///
/// [MacroLineReason.imprecise] has no wording of its own here: an imprecise
/// line is named by the WORD THE SOURCE PRINTED ("handful", "to taste"), not
/// by a defect — see [notCountedNote].
String incompleteLineNote(MacroLineReason reason) => switch (reason) {
  MacroLineReason.stubIngredient => 'stub ingredient',
  MacroLineReason.unknownIngredient => 'not in your ingredients yet',
  MacroLineReason.needsWeight => 'needs a weight',
  MacroLineReason.needsDensity => 'needs a density',
  MacroLineReason.noAmount => 'no amount',
  MacroLineReason.subRecipeUnresolved => 'sub-recipe has no yield',
  MacroLineReason.subRecipeIncomplete => 'sub-recipe incomplete',
  MacroLineReason.imprecise => 'not counted',
};

/// The lines a summary is WAITING ON — everything a household could fix. The
/// imprecise ones are excluded by rule, not by failure, so they are named
/// under the total by [notCountedNote] instead.
List<MacroLineNote> fixableNotes(RecipeMacroSummary summary) => [
  for (final note in summary.notes)
    if (note.reason != MacroLineReason.imprecise) note,
];

/// `not counted: Parsley · handful, Sesame seeds · to taste` — the exclusion
/// D6 prints UNDER the total, every time (seam **D6**).
///
/// This sentence is the whole honesty argument: nothing is invented, because
/// zero grams were claimed; and nothing is silent, because a reader can see
/// precisely what the figure does and does not cover. The unit word is the
/// line's own printed one, never a category name.
///
/// Null when nothing was excluded by rule — a caller renders nothing then,
/// rather than an empty "not counted:".
String? notCountedNote(List<MacroLineNote> notes) {
  final excluded = [
    for (final note in notes)
      if (note.reason == MacroLineReason.imprecise) note,
  ];
  if (excluded.isEmpty) return null;
  final named = [
    for (final n in excluded) '${n.name} · ${n.unit ?? 'imprecise'}',
  ];
  return 'not counted: ${named.join(', ')}';
}

/// The amber `incomplete` badge (design board `.badge-inc`).
class IncompleteBadge extends StatelessWidget {
  const IncompleteBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3E3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'incomplete',
        style: ansiMono(size: 9, color: const Color(0xFF7A5A16)),
      ),
    );
  }
}
