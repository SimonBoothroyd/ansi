/// The recipe persistence contract — PURE DART (invariant 2). The data layer
/// implements it over PowerSync's local SQLite; ViewModels depend only on this.
///
/// Writes take a whole [Recipe] aggregate: `saveRecipe` upserts the recipe and
/// *diffs* its groups/line-items against what is stored — kept ids update, new
/// ids insert, dropped ids soft-delete. The diff (not delete + re-insert)
/// matters under sync: PowerSync queues ops literally, and a DELETE of a kept
/// id would tombstone it server-side for every other device. The editor holds
/// the full tree, so callers still pass the whole aggregate and generate ids
/// for new recipes/groups/items before saving.
library;

import 'recipe.dart';

abstract interface class RecipeRepository {
  /// The recipe list, newest first, reacting to local writes.
  Stream<List<RecipeSummary>> watchRecipes();

  /// A single recipe with its groups and line-items assembled, or null if it
  /// doesn't exist (or is soft-deleted). Reacts to local writes.
  Stream<Recipe?> watchRecipe(String id);

  /// Insert (new id) or replace (existing id) the whole aggregate.
  Future<void> saveRecipe(Recipe recipe);

  /// Soft-delete the recipe (and cascade its groups/items).
  Future<void> deleteRecipe(String id);
}
