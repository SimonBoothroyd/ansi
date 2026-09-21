/// The Week's macro totals, phone and wide.
///
/// Every total draws one of four states, in this order: empty (`no meals`,
/// never `0 kcal`), refused (the `incomplete` badge and reasons, no number),
/// partial (the figures, `1 of 2 meals` and a `left out:` line naming each
/// excluded meal) and whole. Reason wording comes from
/// `shared/incomplete_macros.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../../../shared/cost_words.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/incomplete_macros.dart';
import '../../ingredients/presentation/macro_line_text.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../../receipts/domain/receipt_ledger.dart';
import '../domain/week_cost.dart';
import '../domain/week_macros.dart';

/// A whole energy figure with a thin thousands separator: `1 900`, `90`.
String formatMacroNumber(double value) => _separated(formatKcal(value));

/// A gram figure ([formatGrams]) with the same separator: `1 900.5`, `21.4`.
String formatMacroGrams(double value) => _separated(formatGrams(value));

/// Thin spaces every three digits of the integer part.
String _separated(String number) {
  final sign = number.startsWith('-') ? '-' : '';
  final rest = sign.isEmpty ? number : number.substring(1);
  final dot = rest.indexOf('.');
  final digits = dot == -1 ? rest : rest.substring(0, dot);
  final buffer = StringBuffer(sign);
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  buffer.write(dot == -1 ? '' : rest.substring(dot));
  return buffer.toString();
}

/// `2 meals` / `1 of 2 meals` — printed beside every total.
String mealDenominator(MealSetMacros macros) {
  final noun = plural(macros.considered, 'meal');
  return macros.counted == macros.considered
      ? '${macros.considered} $noun'
      : '${macros.counted} of ${macros.considered} $noun';
}

/// The meal count, and under a person's lens their share of the portions: `1
/// meal · Jun · ¾ of 1¾ portions`. [scope] is `Everyone` or the member's
/// display name.
String denominatorLine(MealSetMacros macros, {required String scope}) {
  final share = portionShareLine(
    macros,
    lensName: scope == 'Everyone' ? null : scope,
  );
  return [mealDenominator(macros), if (share != null) share].join(' · ');
}

/// `no meals`, or `no meals for Ada` under a lens. [scope] is `Everyone` or the
/// member's display name.
String noMealsLine(String scope) =>
    scope == 'Everyone' ? 'no meals' : 'no meals for $scope';

/// What a day holds: `3 meals`, `2 of 3 meals`, or [noMealsLine].
String dayCountLabel(MealSetMacros macros, {required String scope}) =>
    macros.isEmpty ? noMealsLine(scope) : mealDenominator(macros);

/// Why one meal was left out, in the shared vocabulary where there is one.
String exclusionNote(ExcludedMeal meal) => switch (meal.reason) {
  // The picker row's, the confirm card's and the recipe panel's exact words.
  MealExclusion.incomplete =>
    meal.summary == null ? 'incomplete' : incompleteNote(meal.summary!),
  MealExclusion.recipeMissing => 'recipe unavailable',
  MealExclusion.noEaters => 'no eaters',
  // The same words a stub recipe line uses.
  MealExclusion.ingredientNotCounted =>
    meal.lineReason == null
        ? 'not counted'
        : incompleteLineNote(meal.lineReason!),
  // A meal eaten out with no stated figures.
  MealExclusion.outNotStated => 'macros not stated',
};

/// `left out: Sausage Sliders · 1 stub line` — every exclusion named.
String excludedLine(MealSetMacros macros) =>
    macros.excluded.map((e) => '${e.label} · ${exclusionNote(e)}').join(', ');

/// A total in the dense macro grammar ([macroLineSpans]) at [size], with
/// thousands separators: `1 900 🔥 · 90P 212C 70F · 24 🌾`. Fibre prints only
/// where every meal stated it ([Macros.fiber]).
class MacroStrip extends StatelessWidget {
  const MacroStrip({
    required this.macros,
    this.size = 11,
    this.color = AnsiColors.ink,
    this.weight = FontWeight.w500,
    super.key,
  });

  final Macros macros;
  final double size;

  /// The line's ink: muted for one meal's figures, ink for a total.
  final Color color;

  /// The line's weight; a per-meal strip uses [FontWeight.w400].
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final style = ansiMono(size: size, color: color, weight: weight);
    // A macro number is never clipped or ellipsised; the whole line scales down
    // instead.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text.rich(
        TextSpan(
          children: macroLineSpans(
            macros,
            style: style,
            kcal: formatMacroNumber,
            grams: formatMacroGrams,
          ),
        ),
      ),
    );
  }
}

/// `3 661 kcal` — the wide Week's spelled-out energy.
String spelledEnergy(Macros macros) => '${formatMacroNumber(macros.kcal)} kcal';

/// `protein 255 g · carbs 366 g · fat 145 g · fibre 76 g`. An unstated fibre
/// prints nothing ([Macros.fiber]).
String spelledGrams(Macros macros) {
  final fiber = macros.fiber;
  return [
    'protein ${formatMacroGrams(macros.protein)} g',
    'carbs ${formatMacroGrams(macros.carb)} g',
    'fat ${formatMacroGrams(macros.fat)} g',
    if (fiber != null) 'fibre ${formatMacroGrams(fiber)} g',
  ].join(' · ');
}

/// The day card's foot: the macro line and its denominator, or a refusal.
class DayMacroLine extends StatelessWidget {
  const DayMacroLine({required this.macros, required this.scope, super.key});

  final MealSetMacros macros;

  /// `Everyone`, or a member's display name; printed on the refusals.
  final String scope;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: _content(),
    );
  }

  Widget _content() {
    // 1 · an absence is an absence, never a zero.
    if (macros.isEmpty) {
      return Text(
        noMealsLine(scope),
        style: ansiMono(size: 11, color: AnsiColors.muted),
      );
    }
    // 2 · nothing resolved: no number at all.
    if (macros.isRefused) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IncompleteBadge(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'no total — ${excludedLine(macros)}',
              style: ansiMono(size: 10.5, color: AnsiColors.muted),
            ),
          ),
        ],
      );
    }
    // The denominator sits under the strip, not beside it: the strip can only
    // scale down inside a bounded width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacroStrip(macros: macros.total!),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            denominatorLine(macros, scope: scope),
            textAlign: TextAlign.right,
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
        if (macros.isPartial)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'left out: ${excludedLine(macros)}',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
      ],
    );
  }
}

/// A day's energy and denominator on one line — `3 661 kcal · 3 meals` — with
/// [DayMacroLine]'s four states. It never carries the grams.
class DayEnergyLine extends StatelessWidget {
  const DayEnergyLine({
    required this.macros,
    required this.scope,
    this.size = 12.5,
    super.key,
  });

  final MealSetMacros macros;

  /// Whose numbers these are — `Everyone`, or a member's display name.
  final String scope;

  /// The energy figure's size; the denominator rides two points quieter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final muted = ansiMono(size: size - 1.5, color: AnsiColors.muted);
    // 1 · an absence is an absence, never a zero.
    if (macros.isEmpty) return Text(noMealsLine(scope), style: muted);
    // Nothing resolved: no number, and the reasons in full.
    if (macros.isRefused) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IncompleteBadge(),
          const SizedBox(width: 8),
          Expanded(
            child: Text('no total — ${excludedLine(macros)}', style: muted),
          ),
        ],
      );
    }
    // 3/4 · the figure and its MANDATORY denominator, as one wrapping line.
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: spelledEnergy(macros.total!),
            style: ansiMono(size: size, weight: FontWeight.w500),
          ),
          TextSpan(
            text: ' · ${denominatorLine(macros, scope: scope)}',
            style: muted,
          ),
        ],
      ),
    );
  }
}

/// The wide day pane's pinned foot: [DayEnergyLine], and the day's grams
/// spelled out under it. An empty or refusing day draws the one line only.
class DayLedger extends StatelessWidget {
  const DayLedger({required this.macros, required this.scope, super.key});

  final MealSetMacros macros;
  final String scope;

  @override
  Widget build(BuildContext context) {
    final total = macros.total;
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DayEnergyLine(macros: macros, scope: scope, size: 21),
          if (total != null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                spelledGrams(total),
                style: ansiMono(size: 12, color: AnsiColors.muted),
              ),
            ),
          if (macros.isPartial)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'left out: ${excludedLine(macros)}',
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// One meal's figures as served (per serving × the portions planned, via
/// [servedMealMacros]), printed under a dish in the wide day pane.
///
/// Under a lens a meal the person is not eating draws nothing; a refused meal
/// draws the badge and [exclusionNote]'s reason; a counted meal draws a muted
/// [MacroStrip].
class MealMacroLine extends StatelessWidget {
  const MealMacroLine({required this.macros, super.key});

  final MealSetMacros macros;

  @override
  Widget build(BuildContext context) {
    // Not this person's meal: there is no figure to print.
    if (macros.isEmpty) return const SizedBox.shrink();
    final total = macros.total;
    if (total == null) {
      // The meal is named directly above, so the refusal states only the
      // reason.
      final reason = macros.excluded.isEmpty
          ? 'no total'
          : 'no total — ${exclusionNote(macros.excluded.first)}';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IncompleteBadge(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        ],
      );
    }
    return MacroStrip(
      macros: total,
      color: AnsiColors.muted,
      weight: FontWeight.w400,
    );
  }
}

/// The band at the foot of the phone's list: the week's total, its per-day
/// average over the days that counted, and a label saying what the total is
/// not.
class WeekMacroBand extends StatelessWidget {
  const WeekMacroBand({
    required this.macros,
    required this.scope,
    this.cost,
    this.spent = const [],
    this.shape = WeekShape.monday,
    super.key,
  });

  final MealSetMacros macros;
  final String scope;

  /// The receipts dated inside the week on screen. Empty draws no spend line.
  final List<ReceiptSummary> spent;

  /// The household's week, for the day a receipt's date names.
  final WeekShape shape;

  /// What the week's meals cost to cook at the latest prices: `≈` when every
  /// line is priced, `at least` once an unpriced line has left a meal out.
  /// Never reconciled with [spent]. See ADR-0017.
  final PlannedCost? cost;

  /// `avg 1 425 kcal/day over the 6 days that counted`.
  static String _averageLine(Macros average, MealSetMacros macros) {
    final days = macros.daysContributing;
    return 'avg ${formatMacroNumber(average.kcal)} kcal/day over the $days '
        '${plural(days, 'day')} that counted';
  }

  @override
  Widget build(BuildContext context) {
    final average = macros.perDayAverage;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PLANNED · WEEK · ${scope.toUpperCase()}',
                  style: ansiMono(
                    size: 9.5,
                    color: AnsiColors.muted,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (!macros.isEmpty && !macros.isRefused)
                Text(
                  '${macros.daysContributing} of 7 days',
                  style: ansiMono(size: 9.5, color: AnsiColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (macros.isEmpty)
            // A week that plans nothing can still have been shopped for.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'no meals yet — nothing to add up',
                  style: ansiMono(size: 11.5, color: AnsiColors.muted),
                ),
                _SpentLine(spent: spent, shape: shape),
              ],
            )
          else if (macros.isRefused)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IncompleteBadge(),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'no total — ${excludedLine(macros)}',
                        style: ansiMono(size: 10.5, color: AnsiColors.muted),
                      ),
                      // Cost and spend do not depend on the macros resolving.
                      _CostLine(cost: cost),
                      _SpentLine(spent: spent, shape: shape),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            MacroStrip(macros: macros.total!, size: 13),
            const SizedBox(height: 6),
            Text(
              [
                if (average != null) _averageLine(average, macros),
                denominatorLine(macros, scope: scope),
              ].join(' · '),
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
            _CostLine(cost: cost),
            _SpentLine(spent: spent, shape: shape),
            if (macros.isPartial)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'excluded: ${excludedLine(macros)}',
                  style: ansiMono(size: 10, color: AnsiColors.muted),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'This is the sum of what is planned, not a daily target — a '
              'week that only plans dinners averages a dinner.',
              style: ansiSans(
                size: 11.5,
                color: AnsiColors.muted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `≈ $71 to cook`, or `at least $71 to cook · 3 lines unpriced`, or nothing.
class _CostLine extends StatelessWidget {
  const _CostLine({required this.cost});

  final PlannedCost? cost;

  @override
  Widget build(BuildContext context) {
    final cost = this.cost;
    final line = cost == null
        ? null
        : weekCostLine(cents: cost.cents, unpriced: cost.unpriced.length);
    if (line == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(line, style: ansiMono(size: 11.5)),
    );
  }
}

/// `\$84.12 spent · 1 receipt · TJ's, Sun` — a door onto the ledger, drawn only
/// when a receipt is dated inside the week. Phone band only.
class _SpentLine extends StatelessWidget {
  const _SpentLine({required this.spent, required this.shape});

  final List<ReceiptSummary> spent;
  final WeekShape shape;

  @override
  Widget build(BuildContext context) {
    final line = weekSpentLine(spent, shape);
    if (line == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.pushOnce('/receipts'),
        child: Row(
          children: [
            Expanded(child: Text(line, style: ansiMono(size: 11.5))),
            const SizedBox(width: 6),
            const Icon(
              FLucideIcons.chevronRight,
              size: 12,
              color: AnsiColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// `avg 2 915 · 6 of 7 days`. The average is absent when nothing counted.
String weekAverageLine(MealSetMacros macros) {
  final average = macros.perDayAverage;
  return [
    if (average != null) 'avg ${formatMacroNumber(average.kcal)}',
    '${macros.daysContributing} of 7 days',
  ].join(' · ');
}

/// The wide agenda's pinned foot: the week's total as a [MacroStrip] and
/// [weekAverageLine] under it. An empty week draws nothing.
class WeekFootBand extends StatelessWidget {
  const WeekFootBand({required this.macros, required this.scope, super.key});

  final MealSetMacros macros;

  /// Whose numbers these are — `Everyone`, or a member's display name.
  final String scope;

  @override
  Widget build(BuildContext context) {
    if (macros.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: macros.isRefused
          // Nothing resolved: no number, and the reasons named.
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IncompleteBadge(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'no total — ${excludedLine(macros)}',
                    style: ansiMono(size: 10.5, color: AnsiColors.muted),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MacroStrip(macros: macros.total!, size: 13),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      weekAverageLine(macros),
                      if (scope != 'Everyone') scope,
                    ].join(' · '),
                    style: ansiMono(size: 10.5, color: AnsiColors.muted),
                  ),
                ),
              ],
            ),
    );
  }
}
