/// A recipe's optional ingredients, each with a week's answer. Pure Dart.
library;

import 'line_display.dart';
import 'line_override.dart';
import 'recipe.dart';

/// One optional ingredient as a week answers it: every optional line of it,
/// asked as one. `uses` are at the week's amounts where it states them.
/// `lineIds` are the lines a tick writes: empty where the week states an
/// amount for every one, which is changed in the week's editor.
typedef OptionalChoice = ({LineUses uses, List<String> lineIds, bool included});

/// What a surface says and draws of one [OptionalChoice].
extension OptionalChoiceReading on OptionalChoice {
  /// The ingredient's name, or the sub-recipe's title.
  String get name =>
      uses.uses.first.subRecipe?.title ?? uses.uses.first.ingredientName;

  /// Whether it is in with [picks], answers given and not yet written, by
  /// line id, over the week's own.
  bool includedWith(Map<String, bool> picks) =>
      lineIds.isEmpty ? included : picks[lineIds.first] ?? included;
}

/// [lines]' optional ingredients, in stored order, under one week's
/// [overrides]. One is included when every line of it is: a half-selected
/// ingredient would still be offered as optional on the Shop. An include and
/// a stated amount both keep a line, and an exclusion, like no answer, leaves
/// it out.
List<OptionalChoice> optionalChoices(
  Iterable<LineItem> lines,
  List<LineOverride> overrides,
) {
  final byLine = {
    for (final o in overrides)
      if (o.recipeLineItemId != null) o.recipeLineItemId!: o,
  };
  bool edited(LineItem line) =>
      byLine[line.id]?.action == LineOverrideAction.replace;

  final asked = groupLineUses([
    for (final line in lines)
      if (line.optional) line,
  ]);
  return [
    for (final group in asked)
      (
        uses: LineUses(
          ingredientId: group.ingredientId,
          subRecipeId: group.subRecipeId,
          uses: [
            for (final line in group.uses)
              if (edited(line)) applyOverride(line, byLine[line.id]!) else line,
          ],
        ),
        lineIds: [
          for (final line in group.uses)
            if (!edited(line)) line.id,
        ],
        included: group.uses.every(
          (line) =>
              edited(line) ||
              byLine[line.id]?.action == LineOverrideAction.include,
        ),
      ),
  ];
}
