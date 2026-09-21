/// English the app prints (pure Dart): the plural rule, the weekday names and
/// the month names, shared by every layer.
///
/// The weekday tables are ISO-ordered and read only through the week shape
/// (`core/week_shape.dart`): a meal's `day_of_week` is an offset from the
/// household's own first day, not a Monday-first index.
library;

/// The noun [count] takes: `plural(1, 'recipe')` → `recipe`,
/// `plural(3, 'recipe')` → `recipes`. [plural] carries an irregular form
/// (`plural(n, 'it', plural: 'them')`).
String plural(int count, String noun, {String? plural}) =>
    count == 1 ? noun : (plural ?? '${noun}s');

/// Short weekday labels in ISO order, indexed 0=Monday..6=Sunday.
const kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Full weekday labels in ISO order, indexed 0=Monday..6=Sunday.
const kWeekdayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Short month labels, indexed 0=January..11=December.
const kMonthShort = [
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

/// Full month labels, indexed 0=January..11=December.
const kMonthFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A bare day-and-month, e.g. `31 Aug`.
String formatDayMonth(DateTime date) =>
    '${date.day} ${kMonthShort[date.month - 1]}';

/// The month alone, e.g. `Aug`.
String formatMonthShort(DateTime date) => kMonthShort[date.month - 1];
