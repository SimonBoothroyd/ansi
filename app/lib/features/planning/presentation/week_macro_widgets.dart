/// The Week's numbers, and its three refusals (D4).
///
/// [DayMacroLine] sits at the foot of a day card, [WeekMacroBand] at the foot
/// of the list, and both draw the SAME [MealSetMacros] shape at two sizes, so
/// there is one honesty story rather than two. The numbers themselves are the
/// recipe line's dense grammar ([MacroStrip]) — a week reads in the same
/// words an ingredient does.
///
/// The **wide** Week says the same things in words instead of glyphs, because
/// it has the room: [DayEnergyLine] under each agenda heading, [DayLedger] at
/// the foot of the day pane, and [MealMacroLine] under one dish. Same four
/// states in the same order, the same denominators and the same refusals — the
/// figures are spelt out (`protein 255 g`) rather than compressed (`255P`),
/// which is what a phone strip is compressed *for*.
///
/// The rule, in the order it is applied:
///
/// 1. **empty** (`considered == 0`) — `no meals`, or `no meals for Ada` under
///    a lens. An absence, never `0 kcal`.
/// 2. **refused** (nothing resolved) — the shared `incomplete` badge and the
///    reasons, and **no number at all**, exactly as `RecipeMacroPanel`
///    refuses.
/// 3. **partial** — the macro line, the denominator (`1 of 2 meals`), and a
///    `left out:` line NAMING each excluded meal in [incompleteNote]'s exact
///    words.
/// 4. **whole** — the macro line and the plain denominator (`2 meals`).
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
import '../../ingredients/presentation/macro_line_text.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../domain/week_macros.dart';

/// An energy figure with a thin thousands separator: `1 900`, `90`.
/// Whole, like every printed kcal ([formatKcal]) — a week's total runs to
/// five digits, and the separator is what keeps them readable.
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

/// The week's total in the dense macro line's own grammar
/// ([macroLineSpans]), at [size]: `1 900 🔥 · 90P 212C 70F · 24 🌾`.
///
/// The same line a recipe's ingredient draws, with the week's thousands
/// separator ([formatMacroNumber], [formatMacroGrams]) in place of the plain
/// figures — one span builder, so a day's foot, the band and a recipe line
/// cannot drift into three dialects. Fibre rides along only where every meal
/// in the total stated it ([Macros.fiber]); an absent one prints nothing at
/// all, never a zero (invariant 3).
class MacroStrip extends StatelessWidget {
  const MacroStrip({required this.macros, this.size = 11, super.key});

  final Macros macros;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = ansiMono(size: size, weight: FontWeight.w500);
    // A macro number is never clipped or ellipsised — a truncated `1 234` is
    // a wrong number, not a shortened one (invariant 3). So when the widest
    // honest total outgrows its band the whole line scales down together,
    // keeping every digit.
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

/// `3 661 kcal` — the energy figure with its unit spelt out.
///
/// The wide Week's own wording. The phone's strip carries a flame because two
/// spelled-out units would be the longest things on a 320 px line; a 560 px
/// pane has no such problem, and a word needs no alt text.
String spelledEnergy(Macros macros) => '${formatMacroNumber(macros.kcal)} kcal';

/// `protein 255 g · carbs 366 g · fat 145 g · fibre 76 g` — the same four (or
/// five) figures the phone prints as `255P 366C 145F · 76 🌾`, in words.
///
/// Fibre obeys [Macros.fiber]'s every-addend rule here as everywhere: an
/// unstated fibre prints nothing at all, never a zero, and the meals that made
/// the total are still counted.
String spelledGrams(Macros macros) {
  final fiber = macros.fiber;
  return [
    'protein ${formatMacroGrams(macros.protein)} g',
    'carbs ${formatMacroGrams(macros.carb)} g',
    'fat ${formatMacroGrams(macros.fat)} g',
    if (fiber != null) 'fibre ${formatMacroGrams(fiber)} g',
  ].join(' · ');
}

/// The day card's foot: the macro line and its denominator, or one of the two
/// refusals.
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
    // denominator sits UNDER the line rather than beside it: the figures fill
    // a day card's width on their own, and the strip can only scale itself
    // down inside a bounded width — a row sharing it with a second text has
    // none to give.
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

/// A day's energy and its denominator on one spelled-out mono line —
/// `3 661 kcal · 3 meals`.
///
/// The wide Week draws it twice: under every heading in the agenda, and as the
/// first line of the day pane's [DayLedger]. The four states are
/// [DayMacroLine]'s own, in the same order and the same words — an empty day
/// says `no meals`, a day that resolved nothing shows the badge and NO number,
/// and a short day still states `1 of 2 meals`. What it never carries is the
/// grams: in the agenda they are the day pane's job, and in the ledger they are
/// the line underneath.
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
    if (macros.isEmpty) {
      return Text(
        scope == 'Everyone' ? 'no meals' : 'no meals for $scope',
        style: muted,
      );
    }
    // 2 · nothing resolved: no number at all, and the reasons in full — the
    // wide pane has the width the phone's card had to borrow from.
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

/// The day pane's foot in the wide Week: [DayEnergyLine] large, and under it
/// the same day's grams spelt out.
///
/// It is [DayMacroLine]'s content in the wide form's wording — one ledger
/// pinned to the bottom of the pane, so the day's meals may scroll past it and
/// the numbers stay where they were. The refusals are not re-spelt here: an
/// empty or refusing day draws its one line and nothing under it, because
/// there are no grams to spell.
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

/// ONE meal's figures, as served to the people eating it — the line the day
/// pane prints under a dish.
///
/// The owner asked for per-recipe macros beside the day's, and this is the
/// honest form of that: not the recipe's per-serving figure (which would be a
/// fact about the recipe, not about Sunday lunch) but `per serving × the
/// portions planned`, read through [servedMealMacros] so it cannot disagree
/// with the ledger that sums it.
///
/// Three states, the day's own:
///
/// * **out of scope** — under a person's lens, a meal they are not eating has
///   no served figure for them. The row is already dimmed; the line simply
///   is not drawn, because there is nothing true to write on it.
/// * **refused** — the badge and the reason, in [exclusionNote]'s exact words
///   (`1 stub line`, `no eaters`, `stub ingredient`), and never a number.
/// * **counted** — `620 kcal · protein 60 g · carbs 80 g · fat 40 g`.
class MealMacroLine extends StatelessWidget {
  const MealMacroLine({required this.macros, super.key});

  final MealSetMacros macros;

  @override
  Widget build(BuildContext context) {
    // Not this person's meal: no figure exists to print, and inventing an
    // "everyone" number under a lens would be answering a question nobody
    // asked. The dimmed row says the rest.
    if (macros.isEmpty) return const SizedBox.shrink();
    final total = macros.total;
    if (total == null) {
      // The meal names itself directly above, so the refusal states the REASON
      // rather than repeating the label the day's own line has to carry.
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
    return Text(
      '${spelledEnergy(total)} · ${spelledGrams(total)}',
      style: ansiMono(size: 11.5, color: AnsiColors.muted),
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
            MacroStrip(macros: macros.total!, size: 13),
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
