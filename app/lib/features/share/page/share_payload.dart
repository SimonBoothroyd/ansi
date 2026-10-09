/// A shared recipe's rows, read into the domain for its public page (pure
/// Dart, compiled to JS for the browser and the server alike).
///
/// The payload is the database's own rows as JSON — the server selects them,
/// this file reads them — so a row is read by exactly the rules the app reads
/// it by ([lineItemOfRow] and its neighbours). Its shape:
///
/// ```json
/// {
///   "recipes":         [recipe rows: the shared recipe first, then every
///                       recipe its component lines reach],
///   "groups":          [ingredient_group rows, in display order],
///   "lines":           [recipe_line_item rows with the page's joined
///                       aliases and `group_id`, in display order],
///   "recipe_measures": [live recipe_measure rows for those recipes]
/// }
/// ```
library;

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../recipes/domain/recipe_rows.dart';

/// A shared recipe and every sub-recipe it reaches, each read once.
class ShareTree {
  const ShareTree({required this.root, required this.components});

  /// Reads a payload's rows. Throws [FormatException] when there is no
  /// recipe row to show.
  factory ShareTree.fromPayload(Map<String, Object?> payload) {
    List<StoredRow> rows(String key) => [
      for (final r in payload[key] as List? ?? const [])
        (r as Map).cast<String, Object?>(),
    ];
    final recipeRows = rows('recipes');
    if (recipeRows.isEmpty) {
      throw const FormatException('a share payload names no recipe');
    }
    final measuresByRecipe = recipeMeasuresByRecipe(rows('recipe_measures'));

    final linesByGroup = <String, List<LineItem>>{};
    final nutrition = <String, IngredientNutrition>{};
    for (final row in rows('lines')) {
      (linesByGroup[row['group_id']! as String] ??= []).add(
        lineItemOfRow(row, measuresByRecipe),
      );
      if (nutritionOfLineRow(row) case final n?) {
        nutrition[row['ingredient_id']! as String] = n;
      }
    }
    final groupsByRecipe = <String, List<IngredientGroup>>{};
    for (final g in rows('groups')) {
      (groupsByRecipe[g['recipe_id']! as String] ??= []).add(
        IngredientGroup(
          id: g['id']! as String,
          name: g['name'] as String?,
          items: linesByGroup[g['id']] ?? const [],
        ),
      );
    }

    // Every recipe as a component target, so the macro walk can descend
    // through a component of a component without another read.
    final nodes = <String, SubRecipeNode>{
      for (final r in recipeRows)
        r['id']! as String: (
          servingsBase: rowNumber(r['servings_base']) ?? 1,
          lines: [
            for (final g
                in groupsByRecipe[r['id']] ?? const <IngredientGroup>[])
              ...g.items,
          ],
          yields: yieldsOfRow(r),
          measures: measuresByRecipe[r['id']] ?? const <RecipeMeasure>[],
        ),
    };

    Recipe recipeOf(StoredRow r) {
      final id = r['id']! as String;
      final servingsBase = rowNumber(r['servings_base']) ?? 1;
      final (plainSteps, methodSteps) = stepsOfColumn(r['steps']);
      final groups = groupsByRecipe[id] ?? const <IngredientGroup>[];
      return Recipe(
        id: id,
        title: r['title'] as String? ?? '',
        servingsBase: servingsBase,
        groups: groups,
        steps: plainSteps,
        methodSteps: methodSteps,
        yieldQty: rowNumber(r['yield_qty']),
        yieldUnit: unitById(r['yield_unit'] as String? ?? ''),
        yieldQty2: rowNumber(r['yield_qty_2']),
        yieldUnit2: unitById(r['yield_unit_2'] as String? ?? ''),
        cookTimeSeconds: rowInt(r['cook_time_seconds']),
        totalTimeSeconds: rowInt(r['total_time_seconds']),
        measures: measuresByRecipe[id] ?? const <RecipeMeasure>[],
        macros: summarizeRecipeMacros(
          servingsBase: servingsBase,
          lines: [for (final g in groups) ...g.items],
          nutritionOf: (ingredientId) => nutrition[ingredientId],
          subRecipeOf: (subId) => nodes[subId],
        ),
      );
    }

    final byId = {for (final r in recipeRows) r['id']! as String: r};
    final root = recipeOf(recipeRows.first);

    // The components in the order a cook meets them: depth first, each once,
    // so a cycle the database refuses anyway cannot loop here either.
    final seen = <String>{root.id};
    final components = <Recipe>[];
    void reach(Recipe recipe) {
      for (final group in recipe.groups) {
        for (final line in group.items) {
          final subId = line.subRecipeId;
          if (subId == null || !seen.add(subId)) continue;
          final row = byId[subId];
          if (row == null) continue;
          final component = recipeOf(row);
          components.add(component);
          reach(component);
        }
      }
    }

    reach(root);
    return ShareTree(root: root, components: components);
  }

  /// The recipe the link names.
  final Recipe root;

  /// Every recipe [root]'s component lines reach, as a cook meets them.
  final List<Recipe> components;

  /// Whether [recipeId] is drawn on the page, so a line can point down to it.
  bool shows(String recipeId) => components.any((c) => c.id == recipeId);
}
