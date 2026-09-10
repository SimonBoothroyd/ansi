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
import '../core/theme/ansi_tokens.dart';
import '../core/units/macros.dart';
import '../core/words.dart';
import '../features/recipes/domain/recipe_macros.dart';

/// Why a summary is incomplete, for the row note: `no ingredients yet`,
/// `1 stub line`, `2 stub lines · 1 line needs a piece weight · 1
/// unconvertible`,
/// `1 sub-recipe unresolved` — never an empty string (a reasonless badge
/// would leave a dangling separator).
///
/// **"needs a piece weight" is its own reason**, not part of "unconvertible".
/// A bare count — "2 pieces" on a row with no piece weight — is the one
/// incomplete cause a household fixes with a single number on the INGREDIENT
/// (ADR-0015), and calling it a failed conversion described the wrong
/// problem: nothing was ever weighed.
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
    if (counts == 1) '1 line needs a piece weight',
    if (counts > 1) '$counts lines need a piece weight',
    if (summary.unconvertibleLines > 0)
      '${summary.unconvertibleLines} unconvertible',
    // Step 8.6 / D8 — the two sub-recipe reasons, in the same voice as the
    // rest so no surface has to invent its own words for a nested refusal.
    if (unresolved > 0)
      '$unresolved ${plural(unresolved, 'sub-recipe')} unresolved',
    if (subIncomplete > 0)
      '$subIncomplete ${plural(subIncomplete, 'sub-recipe')} incomplete',
  ];
  // Every line joined and there are lines — the only remaining cause is a
  // non-positive serving count (the DB check makes this near-unreachable).
  return parts.isEmpty ? 'servings not set' : parts.join(' · ');
}

/// What ONE excluded line is waiting on — the per-line half of the same
/// vocabulary (seam **D5**). The panel's list, a row's marker and the picker
/// row all read this, so `Cucumber · needs a piece weight` says the same
/// thing wherever it appears.
///
/// [MacroLineReason.imprecise] has no wording of its own here: an imprecise
/// line is named by the WORD THE SOURCE PRINTED ("handful", "to taste"), not
/// by a defect — see [notCountedNote]. [MacroLineReason.optional] is the
/// recipe page's own tag word, which is the same claim in the same voice.
/// `Cucumber · needs a piece weight` names the ingredient's missing fact, so
/// the marker opens the ingredient (ADR-0015).
String incompleteLineNote(MacroLineReason reason) => switch (reason) {
  MacroLineReason.stubIngredient => 'stub ingredient',
  MacroLineReason.unknownIngredient => 'not in your ingredients yet',
  MacroLineReason.needsWeight => 'needs a piece weight',
  MacroLineReason.needsDensity => 'needs a density',
  MacroLineReason.noAmount => 'no amount',
  MacroLineReason.subRecipeUnresolved => 'sub-recipe has no yield',
  MacroLineReason.subRecipeIncomplete => 'sub-recipe incomplete',
  MacroLineReason.imprecise => 'not counted',
  MacroLineReason.optional => 'optional',
};

/// The two reasons a line leaves a total BY RULE rather than by failure —
/// named under the total by [notCountedNote], never marked as fixable.
const Set<MacroLineReason> byRuleReasons = {
  MacroLineReason.imprecise,
  MacroLineReason.optional,
};

/// The lines a summary is WAITING ON — everything a household could fix. The
/// imprecise and optional ones are excluded by rule, not by failure, so they
/// are named under the total by [notCountedNote] instead.
List<MacroLineNote> fixableNotes(RecipeMacroSummary summary) => [
  for (final note in summary.notes)
    if (!byRuleReasons.contains(note.reason)) note,
];

/// `not counted: Parsley · handful, Sesame seeds · to taste` — the exclusion a
/// real total prints UNDER itself, every time — and, one reason wider, `not
/// counted · 2 optional lines: Lime, Coriander`. When both kinds coincide it is
/// ONE line with both reasons: `not counted: Parsley · handful · 2 optional
/// lines: Lime, Coriander`.
///
/// This sentence is the whole honesty argument: nothing is invented, because
/// zero grams were claimed; and nothing is silent, because a reader can see
/// precisely what the figure does and does not cover. The unit word is the
/// line's own printed one, never a category name; the optional lines are
/// counted, then named.
///
/// Null when nothing was excluded by rule — a caller renders nothing then,
/// rather than an empty "not counted:".
String? notCountedNote(List<MacroLineNote> notes) {
  final imprecise = [
    for (final n in notes)
      if (n.reason == MacroLineReason.imprecise)
        '${n.name} · ${n.unit ?? 'imprecise'}',
  ];
  final optional = [
    for (final n in notes)
      if (n.reason == MacroLineReason.optional) n.name,
  ];
  if (imprecise.isEmpty && optional.isEmpty) return null;
  final optionalPart = optional.isEmpty
      ? null
      : '${optional.length} optional ${plural(optional.length, 'line')}: '
            '${optional.join(', ')}';
  if (imprecise.isEmpty) return 'not counted · $optionalPart';
  final line = 'not counted: ${imprecise.join(', ')}';
  return optionalPart == null ? line : '$line · $optionalPart';
}

/// `fibre not counted · 2 lines without it: Onion, Stock` — why a total that
/// is whole in every other respect states no fibre.
///
/// Fibre is optional per ingredient ([Macros.fiber]), so this is the same
/// claim [notCountedNote] makes about a pinch, one figure narrower: the lines
/// are all IN the total, nothing about them needs fixing, and the one number
/// they cannot support is named rather than quietly dropped.
///
/// Null when there is no total yet, when the total states fibre, or when
/// nothing was missing it — a caller renders nothing then.
String? fiberNotCountedNote(RecipeMacroSummary summary) {
  final total = summary.perServing;
  if (total == null || total.fiber != null) return null;
  final names = summary.linesWithoutFiber;
  if (names.isEmpty) return null;
  return 'fibre not counted · ${names.length} '
      '${plural(names.length, 'line')} without it: ${names.join(', ')}';
}

/// The one-line reason under [notCountedNote]: why these lines are out, in
/// the panel's plain voice. Says what applies — a pinch, an optional line, or
/// both — and, for an optional line, where the switch is.
String notCountedCaption(RecipeMacroSummary summary) {
  final imprecise = summary.impreciseLines > 0;
  final optional = summary.optionalLines > 0;
  if (imprecise && optional) {
    return 'a pinch has no weight to count, and an optional line is left out '
        'by rule — untick Optional on a line to count it.';
  }
  if (optional) {
    return 'optional lines are left out by rule, not by failure — untick '
        'Optional on a line to count it.';
  }
  return 'a pinch has no weight to count — these are excluded by rule, '
      'not by failure.';
}

/// The amber `incomplete` badge (design board `.badge-inc`).
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
