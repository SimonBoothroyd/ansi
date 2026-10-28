/// The sentences screens use to describe a week's variant: the door row, the
/// editor's band and footer, and the recipe page's band and menu item.
/// Per-change wording lives in the domain (`line_override.dart`).
library;

import '../../../core/words.dart';

/// What every surface with a week calls a recipe somebody has varied.
const kEditedForThisWeek = 'edited for this week';

/// The footer that drops the whole variant, with the count it would drop.
String backToTheRecipeLabel(int changes) =>
    'Back to the recipe · drops $changes ${plural(changes, 'change')}';

/// The editor band's label: which week — `Week of 14 Sep`. The band's week
/// strip says which days cook these lines.
String weekScopeLine(String weekKey) => 'Week of ${_shortDate(weekKey)}';

/// The recipe page's ⋯ item for week mode. The page's week strip, right above
/// it, says which days it changes; without one it names the week.
String editForThisWeekItem(
  List<int> days,
  List<String> weekdayShort, {
  String? weekKey,
}) => days.isEmpty && weekKey != null
    ? 'Edit for this week · Week of ${_shortDate(weekKey)}'
    : 'Edit for this week';

/// The door row's own first line: what the meal is cooking from.
String weekDoorTitle(int changes) =>
    changes == 0 ? 'As the recipe has them' : 'Edited for this week';

/// The door row's count, once there is one. Null before any change.
String? weekDoorDetail(int changes, List<int> days, List<String> weekdayShort) {
  if (changes == 0) return null;
  final named = _daysSentence(days, weekdayShort);
  final count = '$changes ${plural(changes, 'change')}';
  return named == null ? count : '$count · $named';
}

/// The weekday names for [days]; an out-of-range day is skipped.
List<String> _dayNames(List<int> days, List<String> weekdayShort) => [
  for (final d in days)
    if (d >= 0 && d < weekdayShort.length) weekdayShort[d],
];

/// "Tue and Sat", "Tue, Thu and Sat", or null when nothing is planned.
String? _daysSentence(List<int> days, List<String> weekdayShort) {
  final names = _dayNames(days, weekdayShort);
  if (names.isEmpty) return null;
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// An ISO week key as the header prints the week's first day — `14 Sep`.
String _shortDate(String weekKey) {
  final date = DateTime.tryParse(weekKey);
  return date == null ? weekKey : formatDayMonth(date);
}
