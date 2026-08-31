/// The recipe page's macro panel (step 9) — the four-cell per-serving strip
/// the design board drew for the Recipe frame (`.macro`), now fed by the real
/// [summarizeRecipeMacros] summation instead of mock numbers.
///
/// **Per serving, and therefore scale-invariant.** The servings scaler above
/// it must NOT move these numbers: scaling multiplies every line *and* the
/// servings the recipe yields by the same factor, so a serving is the same
/// serving at 2 or at 12. The panel deliberately takes only the summary (no
/// `servings`/`factor` argument) so a future edit cannot quietly wire the
/// scaler in. The picker rows are per-serving for the same reason.
///
/// **Honesty (invariant 3).** When the summary is `incomplete` — any stub
/// ingredient, any line the unit system cannot bridge, or no lines at all —
/// the strip is replaced by the shared `incomplete` badge and the same note
/// the picker rows print (`1 stub line`, `no ingredients yet`, …). A partial
/// total is never rendered as if it were the recipe's macros, and zeros are
/// never shown for an absence.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../shared/incomplete_macros.dart';
import '../domain/recipe_macros.dart';

class RecipeMacroPanel extends StatelessWidget {
  const RecipeMacroPanel({required this.summary, super.key});

  /// The recipe's honest per-serving summary. Null when the aggregate was
  /// built without line nutrition (the panel then draws nothing rather than
  /// guessing).
  final RecipeMacroSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    if (summary == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('PER SERVING', style: miseLabel()),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: MiseColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: summary.perServing == null
              ? _Incomplete(summary: summary)
              : _Cells(summary: summary),
        ),
      ],
    );
  }
}

/// The board's four equal cells, hairline-divided: value over micro-label.
class _Cells extends StatelessWidget {
  const _Cells({required this.summary});

  final RecipeMacroSummary summary;

  @override
  Widget build(BuildContext context) {
    // Non-null by construction: the panel only builds cells for a complete
    // summary.
    final m = summary.perServing!;
    final cells = <(String, String)>[
      ('${m.kcal.round()}', 'kcal'),
      ('${m.protein.round()} g', 'protein'),
      ('${m.carb.round()} g', 'carb'),
      ('${m.fat.round()} g', 'fat'),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) Container(width: 1, height: 44, color: MiseColors.line),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                children: [
                  Text(
                    cells[i].$1,
                    style: miseMono(size: 14, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cells[i].$2.toUpperCase(),
                    style: miseMono(
                      size: 9.5,
                      color: MiseColors.muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The refusal, in the picker rows' exact words — badge plus the reason.
class _Incomplete extends StatelessWidget {
  const _Incomplete({required this.summary});

  final RecipeMacroSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IncompleteBadge(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  incompleteNote(summary),
                  style: miseMono(size: 11, color: MiseColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary.noLines
                ? 'Macros arrive once this recipe has ingredients.'
                : 'Left out of the total until every line resolves — '
                      'a partial number would not be this recipe.',
            style: miseSans(size: 12, color: MiseColors.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}
