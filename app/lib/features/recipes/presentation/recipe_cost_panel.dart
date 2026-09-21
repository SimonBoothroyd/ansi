/// The panel's cost reading, and the chip pair that flips between macros and
/// cost.
///
/// Three cells: `$2.54 / a serving`, `$10.17 / the recipe`, `Sep / prices
/// from`. An `OLDEST` row names the one line with an older price. An unpriced
/// line removes the cells: the refusal counts the lines and `UNPRICED` names
/// them. Where some lines are priced, the refusal adds `at least $1.65 a
/// serving · at least $6.60 the recipe` as a floor; with nothing priced it
/// stays plain.
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

/// The `Macros | Cost` chip pair with `per serving` beside it.
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
        // Both readings are per serving, said once beside the pair.
        Text('per serving', style: ansiLabel()),
      ],
    ),
  );
}

/// The cost strip: cells when every counted line is priced, the refusal
/// otherwise, and the named rows under either.
class RecipeCostPanel extends StatelessWidget {
  const RecipeCostPanel({required this.summary, this.header, super.key});

  /// The recipe's cost. Null while costs load; the panel then draws nothing.
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
    // Non-null: cells are only built for a complete summary.
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

/// No cost and why, with the floor the priced lines reach where there is one.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.summary});

  final RecipeCostSummary summary;

  @override
  Widget build(BuildContext context) {
    final floor = costFloor(summary);
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
                  costRefusal(summary),
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
            ],
          ),
          if (floor != null) ...[
            const SizedBox(height: 8),
            // A cell's weight, one size down to fit its `at least` wording.
            Text(floor, style: ansiMono(size: 13, weight: FontWeight.w500)),
          ],
          const SizedBox(height: 6),
          Text(
            _why(summary),
            style: ansiSans(size: 12, color: AnsiColors.muted, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// The sentence under the badge, in the state's own terms.
  String _why(RecipeCostSummary summary) {
    if (summary.noLines) {
      return 'A cost arrives once this recipe has ingredients.';
    }
    if (summary.nothingCountable) {
      return 'Every line is imprecise or optional, so there is nothing to '
          'price — a figure here would be a fabrication.';
    }
    if (summary.partlyPriced) {
      final month = summary.newestPrice;
      final from = month == null
          ? ''
          : ', at prices from ${formatMonthShort(month)}';
      return 'What the priced lines come to$from — a floor, not the cost: '
          'the lines named below can only add to it.';
    }
    return 'Left out until every line has a price — a figure short of one of '
        'them would not be this recipe.';
  }
}

/// `UNPRICED`, `OLDEST`, `NOT COUNTED`, `OPTIONAL` rows.
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
              // The one row naming something fixable, so it wears the markers'
              // amber.
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
