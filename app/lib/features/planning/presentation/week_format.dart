/// Display strings for the Week screen: weekday labels and the "Week of …"
/// header. Kept apart from widgets so the labels are trivially testable.
library;

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
