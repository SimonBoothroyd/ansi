/// English the app prints — PURE DART.
///
/// The plural rule, the weekday names and the month names: things every layer
/// says and none of them belongs to one. The weekday tables live here, not
/// beside the Week screen, because the shopping repository prints "· cook Mon"
/// too and the data layer cannot reach upward into presentation for a word —
/// and the months sit beside them because a date is printed by the Week, by a
/// price's history and by the receipts ledger.
///
/// The tables are ISO-ordered and **read through the week shape**
/// (`core/week_shape.dart`), never indexed directly: a meal's `day_of_week` is
/// an offset from the week's own first day, which is a household setting, so
/// an offset is only a Monday-first index by coincidence.
///
/// Every screen says "3 recipes" and "1 recipe". One spelling of that rule is
/// one place for it to be right; thirty spellings are thirty chances to print
/// "1 recipes".
///
/// Deliberately **not** routed through `ingredients/domain/normalize.dart`:
/// that singulariser exists to key vocabulary matching, and giving it a second
/// job here would tie two unrelated things together.
library;

/// The noun [count] takes: `plural(1, 'recipe')` → `recipe`,
/// `plural(3, 'recipe')` → `recipes`.
///
/// [plural] carries the form English does not make by adding an `s` — a verb
/// that agrees with the count (`plural(n, 'step mentions', plural: 'steps
/// mention')`), or a pronoun (`plural(n, 'it', plural: 'them')`).
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

/// Full month labels, indexed 0=January..11=December — the receipts ledger's
/// month heading, which has the room to say the word out.
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

/// A bare day-and-month, e.g. `31 Aug` — the Week's day cards, and the date a
/// price was paid on.
String formatDayMonth(DateTime date) =>
    '${date.day} ${kMonthShort[date.month - 1]}';

/// The month alone, e.g. `Aug` — for a line where the day would be more
/// precision than the reader wants.
String formatMonthShort(DateTime date) => kMonthShort[date.month - 1];
