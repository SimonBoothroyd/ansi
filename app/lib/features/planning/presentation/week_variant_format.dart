/// The sentences the week's variant is described in, on the screens that
/// compose one.
///
/// The per-change words — the editor's tag and the shopping list's provenance
/// segment — live in the domain beside the classification they read
/// (`line_override.dart`), because they are facts about a change rather than
/// about a screen. What is here is everything a surface phrases for itself:
/// the door row, the editor's band, its footer, and the mark every surface
/// with a week prints.
library;

import '../../../core/words.dart';
import '../../recipes/domain/recipe.dart';

/// What every surface with a week calls a recipe somebody has varied.
const kEditedForThisWeek = 'edited for this week';

/// The footer that drops the whole variant, with the count it would drop — a
/// reset that cannot say how much it undoes gets pressed blind.
String backToTheRecipeLabel(int changes) =>
    'Back to the recipe · drops $changes ${plural(changes, 'change')}';

/// The door row's sub-line in the meal editor sheet. The sheet is per MEAL and
/// the variant is per week and recipe, so the row has to state its own scope
/// or it lies about what a tap changes.
String weekScopeSubLine(List<int> days, List<String> weekdayShort) {
  final named = _daysSentence(days, weekdayShort);
  return named == null
      ? 'a change covers every day this week'
      : 'a change covers every day this week — $named';
}

/// The same scope, in the editor's band: which week, and which days of it
/// cook these lines.
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

/// The band a recipe page prints when it was opened FROM a week that plans it
/// — the fact that makes the page's second door legible before it is tapped.
///
/// Dot-joined, not "Tue and Sat": this is a label the eye scans beside the
/// title, where the door's sub-line is a sentence about scope.
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

/// The recipe page's week door, in its ⋯ menu beside "Edit recipe". It names
/// the days because the two doors change different things: one changes the
/// recipe everywhere, this one changes what these days cook.
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

/// The recipe's own facts, stated once in week mode and not editable there.
/// Serves leads, because every amount on the list is per that number.
String fromTheRecipeLine(Recipe recipe) {
  final steps = recipe.methodSteps?.length ?? recipe.steps.length;
  return 'from the recipe · not edited here: '
      'serves ${_servings(recipe.servingsBase)} · '
      '$steps ${plural(steps, 'step')} · ${recipe.title}';
}

String _servings(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';

/// The weekday names a day list actually names — an out-of-range day is not
/// invented a name for.
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
