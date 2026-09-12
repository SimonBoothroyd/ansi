/// English the app prints — PURE DART.
///
/// The plural rule and the weekday names: two things every layer says and
/// neither belongs to one of them. The weekday tables live here, not beside
/// the Week screen, because the shopping repository prints "· cook Mon" too
/// and the data layer cannot reach upward into presentation for a word.
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
