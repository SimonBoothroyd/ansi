/// The recipe persistence contract. Pure Dart.
///
/// `saveRecipe` takes a whole [Recipe] and diffs its groups and line items
/// against what is stored: kept ids update, new ids insert, dropped ids
/// soft-delete. PowerSync queues ops literally, so deleting a kept id would
/// tombstone it for every device. Callers generate ids for new recipes, groups
/// and items before saving.
library;

import 'package:meta/meta.dart';

import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';
import 'recipe_cost.dart';

/// One back-link to a recipe that lists this one as a component — a row of the
/// "Used in · N" tab. [amount] is the resolved share or the reason it cannot be
/// stated.
@immutable
class RecipeUse {
  const RecipeUse({
    required this.lineId,
    required this.recipeId,
    required this.title,
    required this.unit,
    required this.amount,
    this.quantity,
    this.measureLabel,
  });

  /// The referencing line's id, so a tap can scroll to it.
  final String lineId;

  /// The referencing (parent) recipe.
  final String recipeId;
  final String title;

  /// What the parent's line asks for, as printed ("¼ cup").
  final double? quantity;

  /// The line's catalog unit, or null when it is said in one of this recipe's
  /// measures.
  final Unit? unit;

  /// That word, when the line names one and this recipe still has it.
  final String? measureLabel;

  /// That amount as a share of a batch, or why it cannot be said.
  final ComponentAmount amount;

  @override
  bool operator ==(Object other) =>
      other is RecipeUse &&
      other.lineId == lineId &&
      other.recipeId == recipeId &&
      other.title == title &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.measureLabel == measureLabel &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(
    lineId,
    recipeId,
    title,
    quantity,
    unit,
    measureLabel,
    amount,
  );

  @override
  String toString() =>
      'RecipeUse($title, $quantity ${measureLabel ?? unit?.id}, $amount)';
}

/// A line with neither a catalog unit nor a recipe measure, refused by
/// `saveRecipe` before it is written. The server would reject it on upload, and
/// a rejected upload makes the PowerSync connector drop the whole crud
/// transaction. [LineItem]'s asserts are compiled out of release builds; this
/// check is not.
class UndenominatedLineError implements Exception {
  const UndenominatedLineError({required this.lineId, required this.name});

  final String lineId;

  /// The line's display name, so the message can name which line it was.
  final String name;

  @override
  String toString() =>
      '“$name” says no amount in anything — a line is denominated in a unit '
      'or in one of the target recipe’s own words, never in neither';
}

/// A line naming one of the target's measures but no number, refused by
/// `saveRecipe` for the reason [UndenominatedLineError] is (the server's
/// `line_item_recipe_measure_needs_amount`).
class AmountlessLineError implements Exception {
  const AmountlessLineError({required this.lineId, required this.name});

  final String lineId;

  /// The line's display name, so the message can name which line it was.
  final String name;

  @override
  String toString() =>
      '“$name” says one of the recipe’s own words but no number — a word only '
      'says something beside a count';
}

abstract interface class RecipeRepository {
  /// The recipe list, newest first, reacting to local writes.
  Stream<List<RecipeSummary>> watchRecipes();

  /// One recipe with its groups and line items, or null if it does not exist or
  /// is soft-deleted. Live.
  Stream<Recipe?> watchRecipe(String id);

  /// Every recipe's cost, keyed by recipe id (ADR-0017). Separate from
  /// [watchRecipes]: a cost moves when a receipt lands.
  Stream<Map<String, RecipeCostSummary>> watchRecipeCosts();

  /// Insert (new id) or replace (existing id) the whole aggregate.
  Future<void> saveRecipe(Recipe recipe);

  /// Soft-delete the recipe (and cascade its groups/items).
  Future<void> deleteRecipe(String id);

  /// Sets the household-shared favorite flag (the picker's Favorites tab).
  // ignore: avoid_positional_boolean_parameters — a set-flag pair reads fine.
  Future<void> setFavorite(String id, bool favorite);

  /// Re-files one recipe (the Library's "Move to…"). A narrow write like
  /// [setFavorite], so moving never rewrites fields the mover did not load. A
  /// null [sectionId] files it unsectioned.
  Future<void> setFiling(String id, String bookId, String? sectionId);

  /// The live recipes that list [recipeId] as a component, one row per
  /// referencing line. Its length is the "Used in · N" count and the delete
  /// refusal's.
  Future<List<RecipeUse>> usedIn(String recipeId);

  /// Whether making [subRecipeId] a component of [recipeId] would close a
  /// cycle, checked over synced rows; mirrors the server's trigger. A self-link
  /// counts.
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  });
}
