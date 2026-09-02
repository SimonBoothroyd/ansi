/// Display strings for the Week screen: weekday labels and the "Week of …"
/// header. Kept apart from widgets so the labels are trivially testable.
library;

import 'dart:math' as math;

import '../domain/planning.dart';

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

/// The Cook/Shop header's week suffix under D3 — those screens derive from the
/// VIEWED week, so they have to say which one when it isn't the current one.
/// Null on the current week (the header stays the plain screen name).
String? formatDerivedWeekSuffix(DateTime monday, DateTime today) {
  final title = formatWeekTitle(monday, today);
  if (title.isThisWeek) return null;
  // "Next week" → "next week"; "Week of 14 Sep" → "week of 14 Sep" (only the
  // leading word is lowered — the month keeps its casing).
  return title.label[0].toLowerCase() + title.label.substring(1);
}

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
