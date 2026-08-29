/// Display strings for the Week screen: weekday labels and the "Week of …"
/// header. Kept apart from widgets so the labels are trivially testable.
library;

import 'dart:math' as math;

/// Short weekday labels indexed 0=Monday..6=Sunday (grid order).
const kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Full weekday labels indexed 0=Monday..6=Sunday.
const kWeekdayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

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
String formatWeekOf(DateTime monday) =>
    'Week of ${_months[monday.month - 1]} ${monday.day}';

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
