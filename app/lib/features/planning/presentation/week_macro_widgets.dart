/// The Week's numbers, and its three refusals (D4).
///
/// [DayMacroLine] sits at the foot of a day card, [WeekMacroBand] at the foot
/// of the list, and both draw the SAME [MealSetMacros] shape at two sizes, so
/// there is one honesty story rather than two.
///
/// The rule, in the order it is applied:
///
/// 1. **empty** (`considered == 0`) — `no meals`, or `no meals for Ada` under
///    a lens. An absence, never `0 kcal`.
/// 2. **refused** (nothing resolved) — the shared `incomplete` badge and the
///    reasons, and **no number at all**, exactly as `RecipeMacroPanel`
///    refuses.
/// 3. **partial** — the four cells, the denominator (`1 of 2 meals`), and a
///    `left out:` line NAMING each excluded meal in [incompleteNote]'s exact
///    words.
/// 4. **whole** — the four cells and the plain denominator (`2 meals`).
///
/// The reason wording for an incomplete meal comes from
/// `shared/incomplete_macros.dart` and is never re-invented here — that shared
/// vocabulary is the whole reason the picker, the confirm card and the recipe
/// panel read as one refusal instead of three.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/words.dart';
import '../../../shared/incomplete_macros.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../domain/week_macros.dart';

/// An energy figure with a thin thousands separator: `1 900`, `90`.
/// Whole, like every printed kcal ([formatKcal]) — a week's total runs to
/// four digits, and the separator is what keeps them readable.
String formatMacroNumber(double value) => _separated(formatKcal(value));

/// The same separator over a gram figure's one decimal ([formatGrams]):
/// `1 900.5`, `21.4`, `90`.
String formatMacroGrams(double value) => _separated(formatGrams(value));

/// Thin spaces every three digits of the integer part; a decimal tail and
/// the sign ride along untouched.
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

/// `2 meals` / `1 of 2 meals` — the denominator is MANDATORY beside any total
/// (D4's teeth: no bare number, ever).
String mealDenominator(MealSetMacros macros) {
  final noun = plural(macros.considered, 'meal');
  return macros.counted == macros.considered
      ? '${macros.considered} $noun'
      : '${macros.counted} of ${macros.considered} $noun';
}

/// The denominator line under a total: the meal count, and under a person's
/// lens their share of the portions too — `1 meal · Jun · ¾ of 1¾ portions`.
/// [scope] is `Everyone` or the member's display name, as the Week passes it;
/// only a person has a share to name.
String denominatorLine(MealSetMacros macros, {required String scope}) {
  final share = portionShareLine(
    macros,
    lensName: scope == 'Everyone' ? null : scope,
  );
  return [mealDenominator(macros), if (share != null) share].join(' · ');
}

/// Why one meal was left out, in the shared vocabulary where there is one.
String exclusionNote(ExcludedMeal meal) => switch (meal.reason) {
  // The picker row's, the confirm card's and the recipe panel's exact words.
  MealExclusion.incomplete =>
    meal.summary == null ? 'incomplete' : incompleteNote(meal.summary!),
  MealExclusion.recipeMissing => 'recipe unavailable',
  MealExclusion.noEaters => 'no eaters',
  // A snack says `stub ingredient` in the exact words a stub recipe LINE says
  // it (step 8.14 / B-D3) — one vocabulary, not a second one for the week.
  MealExclusion.ingredientNotCounted =>
    meal.lineReason == null
        ? 'not counted'
        : incompleteLineNote(meal.lineReason!),
};

/// `left out: Sausage Sliders · 1 stub line` — every exclusion NAMED, never
/// counted.
String excludedLine(MealSetMacros macros) =>
    macros.excluded.map((e) => '${e.label} · ${exclusionNote(e)}').join(', ');

/// The cell strip, at [size] — the recipe panel's grammar, smaller. Four
/// cells, and a fifth for fibre when every meal in the total stated it
/// ([Macros.fiber]).
class MacroCells extends StatelessWidget {
  const MacroCells({required this.macros, this.size = 12, super.key});

  final Macros macros;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fiber = macros.fiber;
    final cells = <(String, String)>[
      (formatMacroNumber(macros.kcal), 'kcal'),
      ('${formatMacroGrams(macros.protein)} g', 'p'),
      ('${formatMacroGrams(macros.carb)} g', 'c'),
      ('${formatMacroGrams(macros.fat)} g', 'f'),
      // Fibre is optional, so the cell appears only where the figure does — an
      // empty fifth cell would read as a zero (invariant 3). `fib`, not `f`,
      // which this strip already spends on fat.
      if (fiber != null) ('${formatMacroGrams(fiber)} g', 'fib'),
    ];
    // A macro number is never clipped or ellipsised — a truncated `1 234` is
    // a wrong number, not a shortened one (invariant 3). So when the widest
    // honest total outgrows its band the whole strip scales down together,
    // keeping every digit and the divider rhythm.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Container(
                  width: 1,
                  height: size,
                  color: AnsiColors.line,
                ),
              ),
            Text(
              '${cells[i].$1} ${cells[i].$2}',
              style: ansiMono(size: size, weight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}

/// The day card's foot: the four cells and their denominator, or one of the
/// two refusals.
class DayMacroLine extends StatelessWidget {
  const DayMacroLine({required this.macros, required this.scope, super.key});

  final MealSetMacros macros;

  /// Whose numbers these are — `Everyone`, or a member's display name. It is
  /// printed on the refusals so an absence says WHOSE absence it is.
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
        scope == 'Everyone' ? 'no meals' : 'no meals for $scope',
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
    // 3/4 · the total, its denominator, and anything it left out. The
    // denominator sits UNDER the cells rather than beside them: five cells
    // fill a day card's width on their own, and the strip can only scale
    // itself down inside a bounded width — a row sharing it with a second
    // text has none to give.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacroCells(macros: macros.total!),
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

/// The band at the foot of the list: the week's total, its per-day average
/// over the days that counted, and the label that stops the biggest number on
/// the screen inviting a health reading it cannot support (D4d).
class WeekMacroBand extends StatelessWidget {
  const WeekMacroBand({required this.macros, required this.scope, super.key});

  final MealSetMacros macros;
  final String scope;

  /// `avg 1 425 kcal/day over the 6 days that counted` — the average states
  /// its OWN denominator too, because a week that plans four days is not a
  /// week that ate a quarter less.
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
            Text(
              'no meals yet — nothing to add up',
              style: ansiMono(size: 11.5, color: AnsiColors.muted),
            )
          else if (macros.isRefused)
            Row(
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
          else ...[
            MacroCells(macros: macros.total!, size: 14),
            const SizedBox(height: 6),
            Text(
              [
                if (average != null) _averageLine(average, macros),
                denominatorLine(macros, scope: scope),
              ].join(' · '),
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
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
