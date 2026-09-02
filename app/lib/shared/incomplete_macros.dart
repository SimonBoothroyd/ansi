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
/// `1 stub line`, `2 stub lines · 1 unconvertible`,
/// `1 sub-recipe unresolved` — never an empty string (a reasonless badge
/// would leave a dangling separator).
String incompleteNote(RecipeMacroSummary summary) {
  if (summary.noLines) return 'no ingredients yet';
  final stubs = summary.stubLines;
  final unresolved = summary.subRecipesUnresolved;
  final subIncomplete = summary.subRecipesIncomplete;
  final parts = [
    if (stubs == 1) '1 stub line',
    if (stubs > 1) '$stubs stub lines',
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
