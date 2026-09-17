/// The panel's COST reading, and the chip pair that flips between the two.
///
/// **Why the panel and not a tab** (design board). A Cost tab would have to
/// show the ingredient lines again to mean anything, and the page holds one
/// list. The strip is already where the lines are summed; giving it two
/// readings keeps one list, one scaler and one summation — a cost is the same
/// per-line record as a macro, added up the same way and scaled by the same
/// factor.
///
/// **Three cells, or none.** `$2.54 / a serving`, `$10.17 / the recipe`,
/// `Sep / prices from`. The third cell is the caveat said in words: a price is
/// the latest one seen, and the strip states when that was. The `OLDEST` row
/// under it names the one line dragging that date back, so a July jar under an
/// otherwise-September recipe is visible rather than averaged away.
///
/// **An unpriced line takes the cells with it** (invariant 3, and exactly what
/// the macro reading does with a stub): a figure that quietly skipped the
/// tomatoes would understate the recipe by the tomatoes. The cells go, the
/// refusal says how many lines it is waiting on, and `UNPRICED` names them.
library;

import 'package:flutter/widgets.dart';

import '../../../core/money.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/cost_words.dart';
import '../../../shared/incomplete_macros.dart';
import '../domain/recipe_cost.dart';
import 'recipe_macro_panel.dart';

/// The `Macros | Cost` pair with `per serving` beside it — what stands over
/// the strip once the panel has two readings.
///
/// The app's chip row for a small closed choice, the control the Account
/// page's *Week starts on* uses. Two chips, not a dropdown: there are two
/// answers and both fit on the row.
class FiguresToggle extends StatelessWidget {
  const FiguresToggle({required this.cost, required this.onChanged, super.key});

  /// Whether COST is the current reading.
  final bool cost;

  /// The reading the tapped chip asks for.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        AnsiChip(
          label: 'Macros',
          selected: !cost,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 6),
        AnsiChip(label: 'Cost', selected: cost, onTap: () => onChanged(true)),
        const SizedBox(width: 10),
        // The label the micro-label over the macro strip was: both readings
        // are per serving, and saying so once beside the pair is the same
        // claim with one fewer line.
        Text('per serving', style: ansiLabel()),
      ],
    ),
  );
}

/// The cost strip: the cells when every counted line is priced, the refusal
/// when one is not, and the named rows under either.
class RecipeCostPanel extends StatelessWidget {
  const RecipeCostPanel({required this.summary, this.header, super.key});

  /// The recipe's honest cost. Null while the costs have not loaded — the
  /// panel then draws nothing rather than guessing.
  final RecipeCostSummary? summary;

  /// What stands over the strip; see [RecipeMacroPanel.header].
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    // See [RecipeMacroPanel]: the header outlives the reading under it.
    if (summary == null) return header ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header ??
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('PER SERVING', style: ansiLabel()),
            ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AnsiColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: summary.incomplete
              ? _Refusal(summary: summary)
              : _Cells(summary: summary),
        ),
        _Named(summary: summary),
      ],
    );
  }
}

class _Cells extends StatelessWidget {
  const _Cells({required this.summary});

  final RecipeCostSummary summary;

  @override
  Widget build(BuildContext context) {
    // Non-null by construction: the cells are only built for a complete
    // summary.
    final month = summary.newestPrice;
    return PanelCells(
      cells: [
        (formatMoneyRounded(summary.perServingCents!), 'a serving'),
        (formatMoneyRounded(summary.totalCents!), 'the recipe'),
        if (month != null) (formatMonthShort(month), 'prices from'),
      ],
    );
  }
}

/// No figure, and why — the macro reading's refusal in the cost vocabulary.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.summary});

  final RecipeCostSummary summary;

  @override
  Widget build(BuildContext context) => Padding(
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
                costRefusal(summary),
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          summary.noLines
              ? 'A cost arrives once this recipe has ingredients.'
              : summary.nothingCountable
              ? 'Every line is imprecise or optional, so there is nothing to '
                    'price — a figure here would be a fabrication.'
              : 'Left out until every line has a price — a figure short of '
                    'one of them would not be this recipe.',
          style: ansiSans(size: 12, color: AnsiColors.muted, height: 1.35),
        ),
      ],
    ),
  );
}

/// `UNPRICED`, `OLDEST`, `NOT COUNTED`, `OPTIONAL` — what the figure above is
/// waiting on, what is dragging its date back, and what it leaves out by rule.
class _Named extends StatelessWidget {
  const _Named({required this.summary});

  final RecipeCostSummary summary;

  @override
  Widget build(BuildContext context) {
    final unpriced = unpricedNames(summary);
    final oldest = oldestPriceLine(summary);
    final imprecise = impreciseCostNames(summary);
    final optional = optionalCostNames(summary);
    if (unpriced == null &&
        oldest == null &&
        imprecise == null &&
        optional == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unpriced != null)
            PanelNoteRow(
              label: 'UNPRICED',
              names: unpriced,
              // The one row here that names a DEFECT — something a person can
              // go and fix — so it wears the same amber the macro reading's
              // markers do rather than the muted the rules wear.
              labelColor: AnsiColors.aging,
            ),
          if (oldest != null) PanelNoteRow(label: 'OLDEST', names: oldest),
          if (imprecise != null)
            PanelNoteRow(label: 'NOT COUNTED', names: imprecise),
          if (optional != null)
            PanelNoteRow(label: 'OPTIONAL', names: optional),
          if (imprecise != null || optional != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                notCountedCaption,
                style: ansiSans(
                  size: 12,
                  color: AnsiColors.muted,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
