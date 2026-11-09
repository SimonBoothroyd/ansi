/// The words a leftover prints, kept short: `2 left`, `till Mon`, `for Sun`,
/// `freeze by Mon for Wed`, `past its date`. Pure Dart.
library;

import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../domain/cook_plan.dart';
import '../domain/leftovers.dart';

/// `2 left`, `1¾ left`, `0 left`.
String leftCount(double portions) => '${formatFraction(portions)} left';

/// `till Mon`, `till Jan`, `past its date`, `freeze by Mon`: a row's date,
/// that it is behind it, or — offered under Freezer for a later day — when it
/// has to go in. A row with no date (in words, or a freezer with no limit)
/// says its age. A pot not cooked yet says when it cooks ([potWhen]).
String leftoverWhen(Leftover left, DateTime today, WeekShape shape) {
  if (!left.cooked) return potWhen(left, today, shape);
  if (left.pastItsDate(today)) return 'past its date';
  final freezeBy = left.freezeBy;
  if (left.place == LeftoverPlace.freezer && freezeBy != null) {
    return 'freeze by ${leftoverDay(freezeBy, today, shape)}';
  }
  final until = left.goodUntil;
  if (until != null) {
    return leftoverTill(
      until,
      today,
      shape,
      frozen: left.place == LeftoverPlace.freezer,
    );
  }
  return leftoverAge(left.since, today);
}

/// `cooks Sat`: when a pot not cooked yet will be, by [leftoverDay].
String potWhen(Leftover left, DateTime today, WeekShape shape) =>
    'cooks ${leftoverDay(left.since, today, shape)}';

/// `till today`, `till Mon` within the coming six days, else `till 15 Nov`
/// from the fridge and `till Jan` from the freezer ([frozen]), whose dates
/// run months out.
String leftoverTill(
  DateTime until,
  DateTime today,
  WeekShape shape, {
  bool frozen = false,
}) => frozen && _daysBetween(today, until) >= 7
    ? 'till ${formatMonthShort(until)}'
    : 'till ${leftoverDay(until, today, shape)}';

/// `for Sun`, `for Sat + Sun`: the days of the meals still to come that are
/// served from [left] where it is, but for those [leftoverShortFor] says.
/// Null when there are none.
String? leftoverFor(Leftover left, DateTime today, WeekShape shape) =>
    _days('for', _aheadDays(left, today, frozen: false), today, shape);

/// `Wed needs 2`: each meal still to come from [left] that wants more than
/// is there, said in amber. Null when there are none.
String? leftoverShortFor(Leftover left, DateTime today, WeekShape shape) {
  String needs(LeftoverMeal m) =>
      '${leftoverDay(m.day, today, shape)} needs ${formatFraction(m.portions)}';
  final short = [
    for (final m in left.meals)
      if (m.warning == LeftoverWarning.notEnoughLeft &&
          _daysBetween(today, m.day) >= 0)
        needs(m),
  ];
  return short.isEmpty ? null : short.join(' · ');
}

/// `freeze by Mon for Wed`: the meals a fridge row reaches only from the
/// freezer, and the day it has to go in by. Null when there are none.
String? leftoverFreezeFor(Leftover left, DateTime today, WeekShape shape) {
  final by = left.freezeBy;
  if (left.place != LeftoverPlace.fridge || by == null) return null;
  return _days(
    'freeze by ${leftoverDay(by, today, shape)} for',
    _aheadDays(left, today, frozen: true),
    today,
    shape,
  );
}

/// `freeze by Tue for next Thu`: what a batch of the week beginning
/// [weekStart] puts in the freezer for its later meals, and by when.
String freezeShareFor(FreezeShare share, DateTime weekStart, WeekShape shape) =>
    'freeze by ${shape.labelShort(shape.offsetOf(share.freezeBy))} for '
    '${_mealDays(share.forDays, weekStart, shape)}';

/// `freeze 2 by Tue for next Thu`: what a batch of the week beginning
/// [weekStart], not cooked yet, will put in the freezer for its later meals,
/// and by when. Weekdays, never dates; a meal of the next week is `next Thu`.
String freezeShareLine(
  FreezeShare share,
  DateTime weekStart,
  WeekShape shape,
) =>
    'freeze ${formatFraction(share.portions)} by '
    '${shape.labelShort(shape.offsetOf(share.freezeBy))} for '
    '${_mealDays(share.forDays, weekStart, shape)}';

/// `cook it all · freeze 2 for next Thu`: what the meal that cooks a cooking
/// says of its meals in later weeks; `keep 2` for those it reaches from the
/// fridge. Null when it has none.
String? nextWeekShareLine(
  CookSession session,
  DateTime weekStart,
  DateTime today,
  WeekShape shape,
) {
  final until = useByOf(session, weekStart, today);
  final frozen = <DateTime>[];
  final kept = <DateTime>[];
  var frozenPortions = 0.0;
  var keptPortions = 0.0;
  for (final m in session.laterWeekCovers) {
    final still = m.portions - m.eatenPortions;
    if (still <= 1e-9) continue;
    final day = dateOfDay(weekStart, m.dayOfWeek);
    if (until != null && day.isAfter(until) && session.freezable) {
      frozen.add(day);
      frozenPortions += still;
    } else {
      kept.add(day);
      keptPortions += still;
    }
  }
  if (frozen.isEmpty && kept.isEmpty) return null;
  final keep = formatFraction(keptPortions);
  final freeze = formatFraction(frozenPortions);
  return [
    'cook it all',
    if (kept.isNotEmpty) 'keep $keep for ${_mealDays(kept, weekStart, shape)}',
    if (frozen.isNotEmpty)
      'freeze $freeze for ${_mealDays(frozen, weekStart, shape)}',
  ].join(' · ');
}

/// `Thu`, `Sat + next Thu`: meal days by their weekday, counted from the week
/// beginning [weekStart].
String _mealDays(List<DateTime> days, DateTime weekStart, WeekShape shape) =>
    (days.toSet().toList()..sort())
        .map((d) => weekdayFrom(weekStart, d, shape))
        .join(' + ');

/// [day] by its weekday, counted from the week beginning [weekStart]: `Thu`
/// within it, `next Thu` in the week after, its date otherwise.
String weekdayFrom(DateTime weekStart, DateTime day, WeekShape shape) {
  final days = _daysBetween(weekStart, day);
  if (days >= 0 && days < 7) return shape.labelShort(shape.offsetOf(day));
  if (days >= 7 && days < 14) {
    return 'next ${shape.labelShort(shape.offsetOf(day))}';
  }
  return formatDayMonth(day);
}

/// `2 left · till Mon`, `2 left · freeze by Mon`: what can still be planned
/// from [left], and [leftoverWhen]. A pot not cooked yet has nothing to count
/// yet: `cooks Sat`, with `freeze by Tue` when it is offered for a day it
/// reaches from the freezer.
String leftoverLine(Leftover left, DateTime today, WeekShape shape) {
  if (!left.cooked) {
    final by = left.place == LeftoverPlace.freezer ? left.freezeBy : null;
    return [
      potWhen(left, today, shape),
      if (by != null) 'freeze by ${leftoverDay(by, today, shape)}',
    ].join(' · ');
  }
  return '${leftCount(left.portions)} · ${leftoverWhen(left, today, shape)}';
}

/// `cooked today`, `cooked Fri` earlier this week, `cooked last Sat` in the
/// week before, `cooked 21 Oct` before that. Weeks are today's, by [shape].
String cookedOn(DateTime since, DateTime today, WeekShape shape) {
  if (_daysBetween(since, today) <= 0) return 'cooked today';
  final day = shape.labelShort(shape.offsetOf(since));
  return switch (_daysBetween(
        shape.weekStartOf(since),
        shape.weekStartOf(today),
      ) ~/
      7) {
    0 => 'cooked $day',
    1 => 'cooked last $day',
    _ => 'cooked ${formatDayMonth(since)}',
  };
}

/// Where a meal's pot stands: `cooked last Sat` once cooked ([cookedOn]),
/// `cooks Sat` before ([potWhen]).
String potCookedLine(Leftover pot, DateTime today, WeekShape shape) =>
    pot.cooked ? cookedOn(pot.since, today, shape) : potWhen(pot, today, shape);

/// `today`, `1 day`, `4 days`, `1 wk`, `6 wk`: how long since [since].
String leftoverAge(DateTime since, DateTime today) {
  final days = _daysBetween(since, today);
  if (days <= 0) return 'today';
  if (days < 7) return days == 1 ? '1 day' : '$days days';
  return '${days ~/ 7} wk';
}

/// `not enough left`, `past its date`: a leftover meal's warning, said on its
/// Week tag.
String leftoverWarningWords(LeftoverWarning warning) => switch (warning) {
  LeftoverWarning.notEnoughLeft => 'not enough left',
  LeftoverWarning.pastItsDate => 'past its date',
};

/// The days of [left]'s meals still to come: those eaten from the freezer
/// while it is still in the fridge ([frozen]), or the rest.
List<DateTime> _aheadDays(
  Leftover left,
  DateTime today, {
  required bool frozen,
}) => {
  for (final m in left.meals)
    if (_daysBetween(today, m.day) >= 0 &&
        m.portions > 1e-9 &&
        m.warning != LeftoverWarning.notEnoughLeft &&
        (m.freezeBy != null) == frozen)
      DateTime(m.day.year, m.day.month, m.day.day),
}.toList()..sort();

String? _days(
  String lead,
  List<DateTime> days,
  DateTime today,
  WeekShape shape,
) => days.isEmpty
    ? null
    : '$lead ${days.map((d) => leftoverDay(d, today, shape)).join(' + ')}';

/// `today`, `Mon` within the coming week, `21 Nov` past it.
String leftoverDay(DateTime day, DateTime today, WeekShape shape) {
  final days = _daysBetween(today, day);
  if (days <= 0) return 'today';
  if (days < 7) return shape.labelShort(shape.offsetOf(day));
  return formatDayMonth(day);
}

/// Whole days from [from] to [to], by the calendar, not by hours: a clock
/// change does not move a day.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
