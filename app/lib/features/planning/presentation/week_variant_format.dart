/// The words this week's variant is described in — one vocabulary, five
/// places.
///
/// The editor's tag, the door row's sub-line, the dish row's mark, the cook
/// card's clause and the shopping list's provenance segment are all saying the
/// same thing about the same change, so they are written once and the surfaces
/// only choose which of them to print.
library;

import '../../../core/words.dart';
import '../../recipes/domain/line_display.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import 'week_format.dart';

/// What every surface with a week calls a recipe somebody has varied.
const kEditedForThisWeek = 'edited for this week';

/// The editor's tag on one changed line — the recipe's own words quoted back,
/// so the reader can undo the change in their head before undoing it with the
/// button.
///
/// The ingredient is named exactly as the app stores it: a display name is
/// never rewritten to fit a sentence.
String weekTagText(WeekChange change, LineItem? base) => switch (change) {
  WeekChange.swapped when base != null =>
    'this week · was ${amountOfLine(base)} ${base.ingredientName}',
  WeekChange.amount when base != null =>
    'this week · was ${amountOfLine(base)}',
  WeekChange.swapped || WeekChange.amount => 'this week · changed',
  WeekChange.added => 'this week · added',
  WeekChange.leftOut => 'this week · left out',
  WeekChange.included => 'this week · included',
};

/// The shopping list's extra provenance segment — "Ragù · cook Tue · this
/// week, for Pork sausage". Four words, the same four the editor's tags use,
/// on the line the list already prints.
///
/// An exclusion is NOT one of these: there is no row to hang it on, so it
/// takes the echo row the list already prints for optional lines.
String? weekProvenanceSegment(WeekChange change, LineItem? base) =>
    switch (change) {
      WeekChange.swapped when base != null =>
        'this week, for ${base.ingredientName}',
      WeekChange.amount when base != null =>
        'this week, was ${amountOfLine(base)}',
      WeekChange.swapped || WeekChange.amount => 'this week, changed',
      WeekChange.added => 'this week, added',
      WeekChange.included => 'this week, ticked in',
      WeekChange.leftOut => null,
    };

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

/// "Tue and Sat", "Tue, Thu and Sat", or null when nothing is planned.
String? _daysSentence(List<int> days, List<String> weekdayShort) {
  final names = [
    for (final d in days)
      if (d >= 0 && d < weekdayShort.length) weekdayShort[d],
  ];
  if (names.isEmpty) return null;
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// An ISO week key as the header prints its Monday — `14 Sep`.
String _shortDate(String weekKey) {
  final date = DateTime.tryParse(weekKey);
  return date == null ? weekKey : formatDayMonth(date);
}
