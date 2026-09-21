/// The sentences screens use to describe a week's variant: the door row, the
/// editor's band and footer, and the recipe page's band. Per-change wording
/// lives in the domain (`line_override.dart`).
library;

import '../../../core/words.dart';
import '../../recipes/domain/recipe.dart';

/// What every surface with a week calls a recipe somebody has varied.
const kEditedForThisWeek = 'edited for this week';

/// The footer that drops the whole variant, with the count it would drop.
String backToTheRecipeLabel(int changes) =>
    'Back to the recipe · drops $changes ${plural(changes, 'change')}';

/// The door row's sub-line in the meal editor sheet, stating that a change
/// covers every planned day of the recipe this week.
String weekScopeSubLine(List<int> days, List<String> weekdayShort) {
  final named = _daysSentence(days, weekdayShort);
  return named == null
      ? 'a change covers every day this week'
      : 'a change covers every day this week — $named';
}

/// The editor band's scope: which week, and which days of it cook these lines.
String weekScopeLine(
  String weekKey,
  List<int> days,
  List<String> weekdayShort,
) {
  final named = _daysSentence(days, weekdayShort);
  final week = 'Week of ${_shortDate(weekKey)}';
  return named == null
      ? '$week · every day that plans it cooks these lines'
      : '$week · $named both cook these lines';
}

/// The band a recipe page prints when opened from a week that plans it. Days
/// are dot-joined.
String plannedThisWeekLine(
  List<int> days,
  List<String> weekdayShort, {
  required bool edited,
}) {
  final named = _dayNames(days, weekdayShort).join(' · ');
  final planned = named.isEmpty
      ? 'Planned this week'
      : 'Planned $named this week';
  return edited ? '$planned · $kEditedForThisWeek' : planned;
}

/// The recipe page's ⋯ item for week mode, naming the days it changes.
String editForThisWeekItem(
  List<int> days,
  List<String> weekdayShort, {
  String? weekKey,
}) {
  final names = _dayNames(days, weekdayShort);
  if (names.isEmpty) {
    return weekKey == null
        ? 'Edit for this week'
        : 'Edit for this week · Week of ${_shortDate(weekKey)}';
  }
  final named = names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
  return 'Edit for this week · $named only';
}

/// The door row's own first line: what the meal is cooking from.
String weekDoorTitle(int changes) =>
    changes == 0 ? 'As the recipe has them' : 'Edited for this week';

/// The door row's count, once there is one.
String weekDoorDetail(int changes, List<int> days, List<String> weekdayShort) {
  if (changes == 0) return weekScopeSubLine(days, weekdayShort);
  final named = _daysSentence(days, weekdayShort);
  final count = '$changes ${plural(changes, 'change')}';
  return named == null ? count : '$count · $named';
}

/// The recipe's own facts as week mode states them, serves first.
String fromTheRecipeLine(Recipe recipe) {
  final steps = recipe.methodSteps?.length ?? recipe.steps.length;
  return 'from the recipe · not edited here: '
      'serves ${_servings(recipe.servingsBase)} · '
      '$steps ${plural(steps, 'step')} · ${recipe.title}';
}

String _servings(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';

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
