/// The recipe persistence contract — PURE DART (invariant 2). The data layer
/// implements it over PowerSync's local SQLite; ViewModels depend only on this.
///
/// Writes take a whole [Recipe] aggregate: `saveRecipe` upserts the recipe and
/// *replaces* its groups/line-items with the ones on the passed aggregate. That
/// replace-on-save shape (not a per-row diff) is deliberate for step 2 — data
/// is ephemeral (no migration cost) and the editor already holds the full tree.
/// Callers generate ids for new recipes/groups/items before saving.
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
