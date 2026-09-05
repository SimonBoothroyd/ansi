/// Display strings for the Week screen: weekday labels, the week's own name,
/// the per-dish cook marker, and a snack row's stated amount. Kept apart from
/// widgets so the labels — and, for the marker, the derivation behind them —
/// are trivially testable.
library;

import 'dart:math' as math;

import '../../../core/units/portions.dart';
import '../../../core/words.dart';
import '../../../shared/format.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../domain/planning.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The week header, e.g. "Week of Aug 24" for the Monday the week begins on.
///
/// Superseded on the Week screen itself by [formatWeekTitle] (which names the
/// week rather than dating it); kept for surfaces that only ever want the date.
String formatWeekOf(DateTime monday) =>
    'Week of ${_months[monday.month - 1]} ${monday.day}';

/// A bare day-and-month, e.g. `31 Aug` — the switcher's and day cards' date.
String formatDayMonth(DateTime date) =>
    '${date.day} ${_months[date.month - 1]}';

/// The date of [dayOfWeek] (0=Mon..6=Sun) within the week beginning [monday].
String formatDayDate(DateTime monday, int dayOfWeek) =>
    formatDayMonth(monday.add(Duration(days: dayOfWeek)));

/// How the Week screen NAMES the week it is showing (D2).
///
/// A week is a position, not a date, so the title says the position whenever
/// it can — `This week · 31 Aug`, `Next week · 7 Sep`, `Last week · 24 Aug` —
/// and falls back to `Week of 14 Sep` (with no separate date part) beyond
/// that. The `isThisWeek` flag drives the herb dot, so the emphasis survives
/// a glance.
///
/// [today] is any date in the current week; only its Monday matters.
({String label, String? date, bool isThisWeek}) formatWeekTitle(
  DateTime monday,
  DateTime today,
) {
  final here = mondayOf(today);
  final there = mondayOf(monday);
  final weeks = there.difference(here).inDays ~/ 7;
  final date = formatDayMonth(there);
  return switch (weeks) {
    0 => (label: 'This week', date: date, isThisWeek: true),
    1 => (label: 'Next week', date: date, isThisWeek: false),
    -1 => (label: 'Last week', date: date, isThisWeek: false),
    _ => (label: 'Week of $date', date: null, isThisWeek: false),
  };
}

/// The Cook/Shop empty states' week word under D3 — those screens derive from
/// the VIEWED week, so "nothing planned for *next week* yet" has to say which
/// one when it isn't the current one. Null on the current week. (The headers no
/// longer need it: the switcher is their title.)
String? formatDerivedWeekSuffix(DateTime monday, DateTime today) {
  final title = formatWeekTitle(monday, today);
  if (title.isThisWeek) return null;
  // "Next week" → "next week"; "Week of 14 Sep" → "week of 14 Sep" (only the
  // leading word is lowered — the month keeps its casing).
  return title.label[0].toLowerCase() + title.label.substring(1);
}

/// The Week menu row's trailing label — what that week holds, in the Week's
/// own derivation: `9 meals` / `1 meal` / `empty`.
String formatMealCount(int meals) => switch (meals) {
  0 => 'empty',
  1 => '1 meal',
  _ => '$meals meals',
};

/// The picker row's "last planned" recency: `today`, `3d ago`, `2w ago`,
/// `3mo ago` — or, for a meal planned in the FUTURE, `in 3d` / `in 2w` /
/// `in 1mo` (the old label called any future date "this week", which read
/// wrong for next month's plan). Date-only comparison.
String formatLastPlanned(DateTime lastPlanned, DateTime today) {
  final a = DateTime.utc(lastPlanned.year, lastPlanned.month, lastPlanned.day);
  final b = DateTime.utc(today.year, today.month, today.day);
  final days = b.difference(a).inDays;
  if (days < 0) {
    final ahead = -days;
    if (ahead < 7) return 'in ${ahead}d';
    if (ahead < 28) return 'in ${ahead ~/ 7}w';
    return 'in ${math.max(1, ahead ~/ 30)}mo';
  }
  if (days == 0) return 'today';
  if (days < 7) return '${days}d ago';
  if (days < 28) return '${days ~/ 7}w ago';
  return '${math.max(1, days ~/ 30)}mo ago';
}

/// What a planned dish's second line says about how it gets cooked (D6).
enum CookMarkerKind {
  /// This day IS the batch's cook day.
  cooks,

  /// The batch was cooked earlier and this meal comes out of the fridge.
  fromBatch,

  /// The batch was cooked earlier, this day is past the fridge window, and
  /// the freezer is what reaches it.
  freezerShare,
}

/// The cook marker for one planned meal, or null when there is nothing worth
/// saying (see [cookMarkerFor]).
typedef CookMarker = ({
  CookMarkerKind kind,
  int cookDay,

  /// Portions the whole batch cooks — the `batch of 4` (or `batch of 1¾`,
  /// P-D4) on the cook day.
  double batchPortions,

  /// Where this day sits in the batch's fridge window, 0 (just cooked) to 1
  /// (the end of it). Drives the mini fresh→gone bar. 0 when the recipe has
  /// no shelf life set — an unknown window is not a full one.
  double position,
});

/// Reads the cook marker for the meal on [dayOfWeek] / [mealSlot] back off the
/// cook plan (D6) — a READ of the derivation the Cook tab already draws,
/// turned around and printed on its input. No new batching logic lives here.
///
/// Null — no second line at all — when:
///
/// * nothing in the plan covers that meal (an unknown recipe, or a plan still
///   loading), or
/// * the session cooks for **one** meal only. "cooks today" on every row of a
///   week with no batching in it is noise, and an absent second line collapses
///   the row back to one line, which is the point of putting it there.
CookMarker? cookMarkerFor(
  CookPlan plan, {
  required String recipeId,
  required int dayOfWeek,
  required String mealSlot,
}) {
  for (final recipe in plan.recipes) {
    if (recipe.recipeId != recipeId) continue;
    for (final session in recipe.mealSessions) {
      final covers = session.covers.any(
        (m) => m.dayOfWeek == dayOfWeek && m.mealSlot == mealSlot,
      );
      if (!covers) continue;
      // One meal, one cook: there is no batch to talk about.
      if (session.covers.length < 2) return null;

      final keeps = session.keepsForDays;
      final gap = dayOfWeek - session.cookDay;
      final kind = gap == 0
          ? CookMarkerKind.cooks
          : session.frozenDays.contains(dayOfWeek)
          ? CookMarkerKind.freezerShare
          : CookMarkerKind.fromBatch;
      return (
        kind: kind,
        cookDay: session.cookDay,
        batchPortions: session.totalPortions,
        position: keeps == null || keeps <= 0
            ? 0
            : math.min(1, math.max(0, gap / keeps)),
      );
    }
  }
  return null;
}

/// The marker's words. [todayDayOfWeek] is today's index (0=Mon..6=Sun) when
/// the CURRENT week is on screen, and null otherwise — "cooks today" is only
/// true of the week that contains today.
String cookMarkerLabel(CookMarker marker, {int? todayDayOfWeek}) =>
    switch (marker.kind) {
      CookMarkerKind.cooks =>
        todayDayOfWeek == marker.cookDay
            ? 'cooks today · batch of ${formatFraction(marker.batchPortions)}'
            : 'cooks ${kWeekdayShort[marker.cookDay]} · '
                  'batch of ${formatFraction(marker.batchPortions)}',
      CookMarkerKind.fromBatch =>
        'from ${kWeekdayFull[marker.cookDay]}\u2019s batch',
      // The snowflake is drawn as an icon beside this, never as a glyph: no
      // bundled face carries \u2744.
      CookMarkerKind.freezerShare =>
        '${kWeekdayFull[marker.cookDay]}\u2019s freezer share',
    };

/// A snack row's amount, in the place a dish's cook marker would sit (step
/// 8.14 / A-D5): `1 bar · 60 g`, `170 g`, or `no amount`.
///
/// The second segment is what the measure WEIGHS — the stored fact, not a
/// conversion — so the row states both what was planned and what it comes to.
/// It is omitted when the amount is already in the basis unit, which would
/// only repeat it.
///
/// `no amount` is a real state, not an empty string: an entry that states none
/// contributes nothing to the week's macros or to the shopping list, and a row
/// that said nothing about it would be hiding the reason.
String snackAmount(PlanEntry entry) {
  final quantity = entry.quantity;
  final unit = entry.unit;
  if (quantity == null || unit == null) return 'no amount';
  final measure = entry.measure;
  if (measure == null) return '${formatQuantity(quantity)} ${unit.label}';
  final weighs =
      '${formatQuantity(measure.amount)} '
      '${measure.basis.baseUnit.label}';
  return '${formatQuantity(quantity)} ${measure.label} · $weighs';
}
