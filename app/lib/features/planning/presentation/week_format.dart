/// Display strings for the Week screen: weekday labels, the week's name, the
/// cook marker, a snack's amount and a meal out's line. Kept apart from widgets
/// so they are testable.
library;

import 'dart:math' as math;

import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../../../shared/format.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../cook_plan/domain/leftovers.dart';
import '../../ingredients/presentation/macros_format.dart';
import '../domain/planning.dart';

/// "Week of Aug 24" — the week by its first day's date. The Week screen itself
/// uses [formatWeekTitle].
String formatWeekOf(DateTime weekStart) =>
    'Week of ${formatMonthShort(weekStart)} ${weekStart.day}';

/// The date of [dayOfWeek] (0..6) within the week beginning [weekStart].
String formatDayDate(DateTime weekStart, int dayOfWeek) =>
    formatDayMonth(weekStart.add(Duration(days: dayOfWeek)));

/// The week's seven days as a span: `13–19 Sep`, or `28 Sep – 4 Oct` across a
/// month boundary.
String formatWeekSpan(DateTime weekStart) {
  final last = weekStart.add(const Duration(days: 6));
  return weekStart.month == last.month
      ? '${weekStart.day}–${formatDayMonth(last)}'
      : '${formatDayMonth(weekStart)} – ${formatDayMonth(last)}';
}

/// The week's name: `This week · 31 Aug`, `Next week · 7 Sep`, `Last week · 24
/// Aug`, else `Week of 14 Sep` with no date part. [today] is any date in the
/// current week, resolved through [shape].
({String label, String? date, bool isThisWeek}) formatWeekTitle(
  DateTime weekStart,
  DateTime today,
  WeekShape shape,
) {
  final here = shape.weekStartOf(today);
  final there = shape.weekStartOf(weekStart);
  final weeks = there.difference(here).inDays ~/ 7;
  final date = formatDayMonth(there);
  return switch (weeks) {
    0 => (label: 'This week', date: date, isThisWeek: true),
    1 => (label: 'Next week', date: date, isThisWeek: false),
    -1 => (label: 'Last week', date: date, isThisWeek: false),
    _ => (label: 'Week of $date', date: null, isThisWeek: false),
  };
}

/// The week word for the Cook/Shop empty states ("nothing planned for next week
/// yet"). Null on the current week.
String? formatDerivedWeekSuffix(
  DateTime weekStart,
  DateTime today,
  WeekShape shape,
) {
  final title = formatWeekTitle(weekStart, today, shape);
  if (title.isThisWeek) return null;
  // Only the leading word is lowered; the month keeps its casing.
  return title.label[0].toLowerCase() + title.label.substring(1);
}

/// The Week menu row's trailing label: `9 meals` / `1 meal` / `empty`.
String formatMealCount(int meals) => switch (meals) {
  0 => 'empty',
  1 => '1 meal',
  _ => '$meals meals',
};

/// The picker row's recency: `today`, `3d ago`, `2w ago`, `3mo ago`, or `in 3d`
/// / `in 2w` / `in 1mo` for a future date. Date-only comparison.
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

/// What a planned dish's second line says about how it gets cooked.
enum CookMarkerKind {
  /// This day IS the batch's cook day.
  cooks,

  /// The batch is cooked earlier and this meal will come out of the fridge.
  fromBatch,

  /// Cooked earlier, and this day is past the fridge window, so it will come
  /// from the freezer.
  freezerShare,

  /// The batch is already cooked: this meal is eaten from it, a `leftover`
  /// from the fridge or the freezer (`frozen`).
  leftover,
}

/// The cook marker for one planned meal (see [cookMarkerFor]).
typedef CookMarker = ({
  CookMarkerKind kind,

  /// The batch's cook day, an offset from the week on screen's first day:
  /// below 0 for a batch of the week before.
  int cookDay,

  /// Portions the whole batch cooks — `batch of 4`, or `batch of 1¾`.
  double batchPortions,

  /// Where this day sits in the batch's fridge window, 0 (just cooked) to 1
  /// (its end). 0 when the recipe has no shelf life.
  double position,

  /// Eaten from the freezer: past the batch's fridge date.
  bool frozen,
});

/// Reads the cook marker for the meal on [dayOfWeek] / [mealSlot] off the cook
/// plan; no batching logic lives here. Null when nothing in the plan covers the
/// meal, when the session cooks for one meal only, or when the meal falls
/// before the day its batch was cooked.
///
/// The cook day is the batch's as the ticks have it ([cookDayOf]) on [today],
/// in the week beginning [weekStart]; without them it is the planned one. A
/// meal after the cook day of a batch already cooked reads as a `leftover`.
/// A meal of this week the week before's batch cooks ([CookPlan.foldedBack],
/// found by [entryId]) reads as a `leftover` too, unless it has become that
/// batch's cook day.
CookMarker? cookMarkerFor(
  CookPlan plan, {
  required String recipeId,
  required int dayOfWeek,
  required String mealSlot,
  String? entryId,
  DateTime? weekStart,
  DateTime? today,
}) {
  if (plan.foldedBack[entryId] case final host?) {
    final start = weekStart;
    return _markerOf(
      host,
      day: dayOfWeek + 7,
      weekStart: start == null
          ? null
          : DateTime(start.year, start.month, start.day - 7),
      today: today,
      shift: 7,
      folded: true,
    );
  }
  for (final recipe in plan.recipes) {
    if (recipe.recipeId != recipeId) continue;
    for (final session in recipe.mealSessions) {
      final covers = session.covers.any(
        (m) =>
            (entryId != null && m.entryId == entryId) ||
            (m.dayOfWeek == dayOfWeek && m.mealSlot == mealSlot),
      );
      if (!covers) continue;
      // One meal, one cook: there is no batch to talk about.
      if (session.covers.length < 2) return null;
      return _markerOf(
        session,
        day: dayOfWeek,
        weekStart: weekStart,
        today: today,
      );
    }
  }
  return null;
}

/// The marker of [session]'s meal on [day], both counted from [weekStart];
/// [shift] is how far that is behind the week on screen.
CookMarker? _markerOf(
  CookSession session, {
  required int day,
  required DateTime? weekStart,
  required DateTime? today,
  int shift = 0,
  bool folded = false,
}) {
  final cookDay = weekStart == null || today == null
      ? session.cookDay
      : cookDayOf(session, weekStart, today) ?? session.cookDay;
  if (day < cookDay) return null;
  final keeps = session.keepsForDays;
  final gap = day - cookDay;
  final frozen = session.freezable && gap > (keeps ?? kAssumedFridgeDays);
  final kind = gap == 0
      ? CookMarkerKind.cooks
      : folded || wasCooked(session)
      ? CookMarkerKind.leftover
      : frozen
      ? CookMarkerKind.freezerShare
      : CookMarkerKind.fromBatch;
  return (
    kind: kind,
    cookDay: cookDay - shift,
    batchPortions: session.totalPortions,
    position: keeps == null || keeps <= 0
        ? 0
        : math.min(1, math.max(0, gap / keeps)),
    frozen: frozen,
  );
}

/// The marker's words. [todayDayOfWeek] is today's offset when the current week
/// is on screen, else null.
String cookMarkerLabel(
  CookMarker marker,
  WeekShape shape, {
  int? todayDayOfWeek,
}) => switch (marker.kind) {
  CookMarkerKind.cooks =>
    todayDayOfWeek == marker.cookDay
        ? 'cooks today · batch of ${formatFraction(marker.batchPortions)}'
        : 'cooks ${shape.labelShort(marker.cookDay)} · '
              'batch of ${formatFraction(marker.batchPortions)}',
  CookMarkerKind.fromBatch => batchCaption(marker.cookDay, shape),
  // The snowflake is drawn as an icon: no bundled face carries ❄.
  CookMarkerKind.freezerShare =>
    '${shape.labelFull(marker.cookDay)}’s freezer share',
  CookMarkerKind.leftover => 'leftover',
};

/// Where a meal comes from when it is not its batch's cook day: `from
/// Monday’s batch`, or `from Monday’s batch, frozen`. The week strip's caption
/// and the week row's marker say it the same way.
String batchCaption(int cookDay, WeekShape shape, {bool frozen = false}) =>
    'from ${shape.labelFull(cookDay)}\u2019s batch${frozen ? ', frozen' : ''}';

/// The meal batches a week cooks one dish in, from the days its meals are on
/// (one per meal) and the dish's shelf life, clustered exactly as the cook plan
/// clusters them ([clusterSessions]). For a strip of a week other than the one
/// on screen, whose cook plan is not derived.
List<CookSession> weekBatchesOf(
  Iterable<int> mealDays, {
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) => clusterSessions(
  PlannedRecipe(
    recipeId: '',
    title: '',
    servingsBase: 1,
    keepsForDays: keepsForDays,
    freezable: freezable,
    freezerDays: freezerDays,
    meals: [
      for (final d in mealDays)
        CoveredMeal(dayOfWeek: d, mealSlot: '', portions: 1),
    ],
  ),
);

/// What the app does not do with a meal eaten out, as said by the picker and
/// the confirm card.
const kNotCookedNotBought = 'not cooked, not bought';

/// A meal out's second line: `620 kcal · 42P — as stated` (per portion, as
/// typed), or `macros not stated`.
String outMacroLine(PlanEntry entry) {
  final macros = entry.macros;
  if (macros == null) return 'macros not stated';
  return '${formatKcal(macros.kcal)} kcal · '
      '${formatGrams(macros.protein)}P · as stated';
}

/// A snack row's amount: `1 bar · 60 g`, `170 g`, or `no amount`. The second
/// segment is the measure's stored weight, omitted when the amount is already
/// in the basis unit.
String snackAmount(PlanEntry entry) {
  final quantity = entry.quantity;
  final unit = entry.unit;
  if (quantity == null || unit == null) return 'no amount';
  final measure = entry.measure;
  if (measure == null) {
    return '${formatQuantityIn(quantity, unit)} ${unit.label}';
  }
  final basis = measure.basis.baseUnit;
  final weighs = '${formatQuantityIn(measure.amount, basis)} ${basis.label}';
  return '${formatQuantity(quantity)} ${measure.label} · $weighs';
}
