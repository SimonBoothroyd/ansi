/// The words a leftover prints: its count and its date, kept short —
/// `1¾ · until Mon`, `2 · 2 wk`, `past its date`. Pure Dart.
library;

import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../domain/leftovers.dart';

/// `until Mon`, `2 wk`, `past its date`, `freeze by Mon`: a fridge row's
/// date, a freezer row's age, that it is behind its date, or — offered under
/// Freezer for a later day — when it has to go in. A fridge row with no date
/// (in words) says its age.
String leftoverWhen(Leftover left, DateTime today, WeekShape shape) {
  if (left.pastItsDate(today)) return 'past its date';
  final freezeBy = left.freezeBy;
  if (left.place == LeftoverPlace.freezer && freezeBy != null) {
    return 'freeze by ${_dayWord(freezeBy, today, shape)}';
  }
  final until = left.goodUntil;
  if (left.place == LeftoverPlace.fridge && until != null) {
    return leftoverUntil(until, today, shape);
  }
  return leftoverAge(left.since, today);
}

/// `until today`, `until Mon` within the coming week, `until 21 Nov` past it.
String leftoverUntil(DateTime until, DateTime today, WeekShape shape) =>
    'until ${_dayWord(until, today, shape)}';

/// `freeze 2 by Tue for Thu`: what a batch puts in the freezer for its later
/// meals, and by when.
String freezeShareLine(FreezeShare share, DateTime today, WeekShape shape) =>
    'freeze ${formatFraction(share.portions)} by '
    '${_dayWord(share.freezeBy, today, shape)} for '
    '${share.forDays.map((d) => _dayWord(d, today, shape)).join(' + ')}';

/// `today`, `Mon` within the coming week, `21 Nov` past it.
String _dayWord(DateTime day, DateTime today, WeekShape shape) {
  final days = _daysBetween(today, day);
  if (days <= 0) return 'today';
  if (days < 7) return shape.labelShort(shape.offsetOf(day));
  return formatDayMonth(day);
}

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
