/// The words a leftover prints: its count and its date, kept short —
/// `1¾ · until Mon`, `2 · 2 wk`, `past its date`. Pure Dart.
library;

import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../domain/leftovers.dart';

/// `until Mon`, `2 wk`, `past its date`: a fridge row's date, a freezer
/// row's age, or that it is behind its date. A fridge row with no date (in
/// words, or no known fridge life) says its age.
String leftoverWhen(Leftover left, DateTime today, WeekShape shape) {
  if (left.pastItsDate(today)) return 'past its date';
  final until = left.goodUntil;
  if (left.place == LeftoverPlace.fridge && until != null) {
    return leftoverUntil(until, today, shape);
  }
  return leftoverAge(left.since, today);
}

/// `until today`, `until Mon` within the coming week, `until 21 Nov` past it.
String leftoverUntil(DateTime until, DateTime today, WeekShape shape) {
  final days = _daysBetween(today, until);
  if (days <= 0) return 'until today';
  if (days < 7) return 'until ${shape.labelShort(shape.offsetOf(until))}';
  return 'until ${formatDayMonth(until)}';
}

/// `today`, `1 day`, `4 days`, `1 wk`, `6 wk`: how long since [since].
String leftoverAge(DateTime since, DateTime today) {
  final days = _daysBetween(since, today);
  if (days <= 0) return 'today';
  if (days < 7) return days == 1 ? '1 day' : '$days days';
  return '${days ~/ 7} wk';
}

/// `1¾ · until Mon`: the portions left and [leftoverWhen].
String leftoverLine(Leftover left, DateTime today, WeekShape shape) =>
    '${formatFraction(left.portions)} · ${leftoverWhen(left, today, shape)}';

/// `2`, `2 · 2 planned`: the portions left, and the meals already planned
/// from it that are still to come.
String leftoverCount(Leftover left) => left.planned > 1e-9
    ? '${formatFraction(left.portions)} · '
          '${formatFraction(left.planned)} planned'
    : formatFraction(left.portions);

/// Whole days from [from] to [to], by the calendar, not by hours: a clock
/// change does not move a day.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
