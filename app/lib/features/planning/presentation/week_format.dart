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
/// `3mo ago` — or `this week` for a meal planned today-or-later (the
/// already-this-week strip carries the detail). Date-only comparison.
String formatLastPlanned(DateTime lastPlanned, DateTime today) {
  final a = DateTime.utc(lastPlanned.year, lastPlanned.month, lastPlanned.day);
  final b = DateTime.utc(today.year, today.month, today.day);
  final days = b.difference(a).inDays;
  if (days < 0) return 'this week';
  if (days == 0) return 'today';
  if (days < 7) return '${days}d ago';
  if (days < 28) return '${days ~/ 7}w ago';
  return '${math.max(1, days ~/ 30)}mo ago';
}
