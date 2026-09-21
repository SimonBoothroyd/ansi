/// The recipe page's macro panel: a per-serving cell strip fed by
/// [summarizeRecipeMacros].
///
/// Four cells, or five when the total states fibre
/// ([RecipeMacroSummary.linesWithoutFiber]). Figures are per serving and so
/// scale-invariant: the panel takes only the summary, never a scale factor. An
/// `incomplete` summary replaces the strip with the shared badge, the count
/// note, and up to four named lines (`+N more`), each a door to its fix. A real
/// total names what it left out in `NOT COUNTED` and `OPTIONAL` rows; opened
/// from a week, an `INCLUDED` row names the optional lines that week ticked in.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/incomplete_macros.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../domain/recipe_macros.dart';
import 'ingredient_line.dart';

class RecipeMacroPanel extends StatelessWidget {
  const RecipeMacroPanel({
    required this.summary,
    this.onFix,
    this.includedNames = const [],
    this.optionalNames = const [],
    this.header,
    super.key,
  });

  /// What stands over the strip; null draws the default micro-label. The recipe
  /// page passes the `Macros | Cost` chip pair.
  final Widget? header;

  /// The optional lines this week ticked in, in stored order. Empty except on a
  /// page opened from a week that plans the recipe.
  final List<String> includedNames;

  /// The optional lines that week still leaves out. The week's re-summation
  /// drops them before it runs, so the caller names them; from the Library this
  /// is empty and the summary names them.
  final List<String> optionalNames;

  /// The per-serving summary. Null when the aggregate has no line nutrition;
  /// the panel then draws nothing.
  final RecipeMacroSummary? summary;

  /// Opens the fix a named line's reason implies (amount sheet, ingredient
  /// form, or the target recipe). Null leaves the names as plain text.
  final ValueChanged<MacroLineNote>? onFix;

  /// How many named lines print before folding to `+N more`.
  static const int maxNamedLines = 4;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    // The header is the page's control, so it shows even before the summary
    // loads.
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
          child: summary.perServing == null
              ? _Incomplete(
                  summary: summary,
                  onFix: onFix,
                  includedNames: includedNames,
                  optionalNames: optionalNames,
                )
              : _Cells(summary: summary),
        ),
        // A real total names what it left out, outside the cell strip.
        if (summary.perServing != null)
          _NotCounted(
            summary: summary,
            includedNames: includedNames,
            optionalNames: optionalNames,
          ),
      ],
    );
  }
}

/// What the total left out, one labelled row per reason:
///
/// ```text
/// NOT COUNTED   Cilantro · handful, Kosher Salt · to taste
/// OPTIONAL      Lime, Coriander
/// INCLUDED      Pickled Red Onions · for this week
/// ```
///
/// One caption covers the first two. `INCLUDED` names lines the total does
/// cover, so it wears the herb label and sits outside the caption. Missing
/// fibre has its own row.
class _NotCounted extends StatelessWidget {
  const _NotCounted({
    required this.summary,
    this.includedNames = const [],
    this.optionalNames = const [],
  });

  final RecipeMacroSummary summary;
  final List<String> includedNames;
  final List<String> optionalNames;

  @override
  Widget build(BuildContext context) {
    final imprecise = impreciseNotCountedNames(summary.notes);
    final optional = optionalNames.isNotEmpty
        ? optionalNames.join(', ')
        : optionalNotCountedNames(summary.notes);
    final included = includedNames.isEmpty
        ? null
        : '${includedNames.join(', ')} · for this week';
    // Fibre's absence in words: the lines are counted, the figure is not
    // stated.
    final fibre = fiberNotCountedNote(summary);
    final excluded = imprecise != null || optional != null;
    if (!excluded && included == null && fibre == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imprecise != null)
            PanelNoteRow(label: 'NOT COUNTED', names: imprecise),
          if (optional != null)
            PanelNoteRow(label: 'OPTIONAL', names: optional),
          if (included != null)
            PanelNoteRow(
              label: 'INCLUDED',
              names: included,
              labelColor: AnsiColors.herb,
            ),
          if (excluded)
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
          if (fibre != null)
            Padding(
              padding: EdgeInsets.only(top: excluded ? 4 : 0),
              child: Text(
                fibre,
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// One reason's row: the micro-label, then the names it covers. Shared with the
/// panel's cost reading.
class PanelNoteRow extends StatelessWidget {
  const PanelNoteRow({
    required this.label,
    required this.names,
    this.labelColor = AnsiColors.muted,
    super.key,
  });

  final String label;
  final String names;

  /// Herb on the week's own row, muted on the two that name exclusions.
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // The ingredient rows' amount column, so names align with the list
            // above.
            width: kLineAmountWidth,
            child: Text(
              label,
              style: ansiMono(size: 10, color: labelColor, letterSpacing: 0.8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              names,
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One named line under the badge: `Cucumber · needs a piece weight ›`. Tapping
/// opens the fix its reason implies.
class _NamedLine extends StatelessWidget {
  const _NamedLine({required this.note, this.onFix});

  final MacroLineNote note;
  final ValueChanged<MacroLineNote>? onFix;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const _AmberDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: note.name,
                    style: ansiSans(size: 13, weight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: '  ·  ${incompleteLineNote(note.reason)}',
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
          ),
          if (onFix != null)
            const Icon(
              FLucideIcons.chevronRight,
              size: 14,
              color: AnsiColors.muted,
            ),
        ],
      ),
    );
    if (onFix == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onFix!(note),
      child: row,
    );
  }
}

/// The amber the import review card's `attn` state uses.
class _AmberDot extends StatelessWidget {
  const _AmberDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(
      color: AnsiColors.aging,
      shape: BoxShape.circle,
    ),
  );
}

/// Equal cells, hairline-divided: a value over a micro-label. Shared by the
/// macro and cost readings.
class PanelCells extends StatelessWidget {
  const PanelCells({required this.cells, super.key});

  /// Value then label, left to right.
  final List<(String, String)> cells;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) Container(width: 1, height: 44, color: AnsiColors.line),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              children: [
                Text(
                  cells[i].$1,
                  style: ansiMono(size: 14, weight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  cells[i].$2.toUpperCase(),
                  style: ansiMono(
                    size: 9.5,
                    color: AnsiColors.muted,
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

/// The macro reading's cells.
class _Cells extends StatelessWidget {
  const _Cells({required this.summary});

  final RecipeMacroSummary summary;

  @override
  Widget build(BuildContext context) {
    // Non-null: cells are only built for a complete summary.
    final m = summary.perServing!;
    final fiber = m.fiber;
    final cells = <(String, String)>[
      (formatKcal(m.kcal), 'kcal'),
      ('${formatGrams(m.protein)} g', 'protein'),
      ('${formatGrams(m.carb)} g', 'carb'),
      ('${formatGrams(m.fat)} g', 'fat'),
      // Fibre is optional; an empty cell would read as a zero, so its absence
      // is said in words underneath.
      if (fiber != null) ('${formatGrams(fiber)} g', 'fibre'),
    ];
    return PanelCells(cells: cells);
  }
}

/// The refusal, in the picker rows' exact words — badge plus the reason.
class _Incomplete extends StatelessWidget {
  const _Incomplete({
    required this.summary,
    this.onFix,
    this.includedNames = const [],
    this.optionalNames = const [],
  });

  final RecipeMacroSummary summary;
  final ValueChanged<MacroLineNote>? onFix;
  final List<String> includedNames;
  final List<String> optionalNames;

  @override
  Widget build(BuildContext context) {
    // The count note is the same string the picker rows and confirm sheet print
    // (`incomplete_macros.dart`); the named lines go under it.
    final named = fixableNotes(summary);
    final shown = named.take(RecipeMacroPanel.maxNamedLines).toList();
    final more = named.length - shown.length;
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
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary.noLines
                ? 'Macros arrive once this recipe has ingredients.'
                : summary.nothingWeighable
                ? 'Every line is imprecise, so nothing was weighed — a total '
                      'here would be a fabrication, not a number.'
                : 'Left out of the total until every line resolves — '
                      'a partial number would not be this recipe.',
            style: ansiSans(size: 12, color: AnsiColors.muted, height: 1.35),
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final note in shown) _NamedLine(note: note, onFix: onFix),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 14),
                child: Text(
                  '+$more more',
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
          ],
          // An incomplete recipe still names the lines it excludes by rule.
          _NotCounted(
            summary: summary,
            includedNames: includedNames,
            optionalNames: optionalNames,
          ),
        ],
      ),
    );
  }
}
