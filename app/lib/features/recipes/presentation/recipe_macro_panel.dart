/// The recipe page's macro panel (step 9) — the per-serving cell strip the
/// design board drew for the Recipe frame (`.macro`), fed by the real
/// [summarizeRecipeMacros] summation instead of mock numbers.
///
/// **Four cells, or five.** Fibre is the one optional figure
/// ([RecipeMacroSummary.linesWithoutFiber]): its cell is drawn when the total
/// states it and left out — never blank, never zero — when it does not, with
/// the lines that could not supply it named underneath.
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
///
/// **The refusal NAMES its causes** (seam D5). The owner's sentence was
/// "this message makes it impossible to know what ingredients need fixing",
/// so the count line is kept verbatim and the lines it is waiting on are
/// listed under it — capped at four with `+N more`, each one a door to the
/// fix its reason implies. Invariant 3 is unchanged: nothing new is included
/// in any total; the refusal just says what it is waiting on.
///
/// **And a real total says what it left out.** Imprecise lines are excluded by
/// rule, and `not counted: Parsley · handful` prints beneath the cells, every
/// time — as do optional lines, one reason wider on the same line: `not
/// counted · 2 optional lines: Lime, Coriander`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/incomplete_macros.dart';
import '../domain/recipe_macros.dart';

class RecipeMacroPanel extends StatelessWidget {
  const RecipeMacroPanel({required this.summary, this.onFix, super.key});

  /// The recipe's honest per-serving summary. Null when the aggregate was
  /// built without line nutrition (the panel then draws nothing rather than
  /// guessing).
  final RecipeMacroSummary? summary;

  /// Opens the fix a named line's reason implies — the amount sheet for a
  /// bare count or a missing amount, the flesh-out form for a stub or a
  /// missing density, the target recipe for the two nested reasons (seam
  /// **D5**). Null leaves the names as plain text: the panel is a pure widget
  /// and routes nothing itself.
  final ValueChanged<MacroLineNote>? onFix;

  /// How many named lines the panel prints before it folds (owner call): four,
  /// with `+N more`. The count above them is the honest fallback for a
  /// thoroughly broken recipe.
  static const int maxNamedLines = 4;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    if (summary == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              ? _Incomplete(summary: summary, onFix: onFix)
              : _Cells(summary: summary),
        ),
        // D6: a real total says what it left out, by name, every time. It
        // rides OUTSIDE the cell strip so the four cells keep their shape.
        if (summary.perServing != null) _NotCounted(summary: summary),
      ],
    );
  }
}

/// `not counted: Parsley · handful, Sesame seeds · to taste` — and/or
/// `not counted · 2 optional lines: Lime, Coriander`.
class _NotCounted extends StatelessWidget {
  const _NotCounted({required this.summary});

  final RecipeMacroSummary summary;

  @override
  Widget build(BuildContext context) {
    final note = notCountedNote(summary.notes);
    // The fifth cell's absence, said in words: the lines are all in the total,
    // and the one figure they cannot support is named.
    final fibre = fiberNotCountedNote(summary);
    if (note == null && fibre == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null) ...[
            Text(note, style: ansiMono(size: 11, color: AnsiColors.muted)),
            const SizedBox(height: 2),
            Text(
              notCountedCaption(summary),
              style: ansiSans(size: 12, color: AnsiColors.muted, height: 1.35),
            ),
          ],
          if (fibre != null)
            Padding(
              padding: EdgeInsets.only(top: note == null ? 0 : 4),
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

/// One named line under the badge: `Cucumber · needs a piece weight ›`.
/// Tapping it opens the fix its reason implies — the marker is a door, not a
/// label.
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

/// The same amber the review card's `attn` state uses, because it is the same
/// claim: *this line is why a number is missing.*
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

/// The board's four equal cells, hairline-divided: value over micro-label.
class _Cells extends StatelessWidget {
  const _Cells({required this.summary});

  final RecipeMacroSummary summary;

  @override
  Widget build(BuildContext context) {
    // Non-null by construction: the panel only builds cells for a complete
    // summary.
    final m = summary.perServing!;
    final fiber = m.fiber;
    final cells = <(String, String)>[
      ('${m.kcal.round()}', 'kcal'),
      ('${m.protein.round()} g', 'protein'),
      ('${m.carb.round()} g', 'carb'),
      ('${m.fat.round()} g', 'fat'),
      // A fifth cell only where there is a fifth fact: fibre is optional, and
      // an empty cell would read as a zero (invariant 3). What its absence
      // means is said in words underneath instead.
      if (fiber != null) ('${fiber.round()} g', 'fibre'),
    ];
    return Row(
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
}

/// The refusal, in the picker rows' exact words — badge plus the reason.
class _Incomplete extends StatelessWidget {
  const _Incomplete({required this.summary, this.onFix});

  final RecipeMacroSummary summary;
  final ValueChanged<MacroLineNote>? onFix;

  @override
  Widget build(BuildContext context) {
    // The COUNT stays, verbatim — the picker rows and the confirm sheet print
    // that same string, and `incomplete_macros.dart` exists so the three
    // surfaces cannot drift into three different failures. What D5 adds is
    // the names underneath it.
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
          // An incomplete recipe can still be excluding imprecise lines by
          // rule, and they are named here too — the exclusion is the honesty,
          // whether or not there is a number above it.
          _NotCounted(summary: summary),
        ],
      ),
    );
  }
}
