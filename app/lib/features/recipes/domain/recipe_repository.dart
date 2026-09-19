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

import 'package:meta/meta.dart';

import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';
import 'recipe_cost.dart';

/// One back-link to a recipe that lists this one as a component — a row of the
/// "Used in · N" tab (step 8.6 / D9): *target · amount · share of a batch*.
///
/// [amount] is the resolved share ([ResolvedComponentAmount]) or the honest
/// reason it cannot be stated; the tab renders that, never a guessed `1×`.
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
  /// own words instead — the same XOR every component line carries.
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

/// A line that says its amount in nothing at all — neither a catalog unit nor
/// one of the target's own words — refused by `saveRecipe` before it is
/// written.
///
/// The database's `num_nonnulls(unit, recipe_measure_id) = 1` would refuse it
/// on UPLOAD, and a refused upload makes the PowerSync connector drop the
/// WHOLE crud transaction: one malformed line would silently take every write
/// queued beside it. So the repository refuses the save instead, where a
/// person is standing in front of it and the write door can say why.
///
/// [LineItem]'s own asserts state the same shape, but an assert is compiled
/// out of a release build — this is the check that is there on a phone.
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

abstract interface class RecipeRepository {
  /// The recipe list, newest first, reacting to local writes.
  Stream<List<RecipeSummary>> watchRecipes();

  /// A single recipe with its groups and line-items assembled, or null if it
  /// doesn't exist (or is soft-deleted). Reacts to local writes.
  Stream<Recipe?> watchRecipe(String id);

  /// Every recipe's cost, keyed by recipe id (ADR-0017) — a SEPARATE read from
  /// [watchRecipes], because a cost moves when a receipt lands and because a
  /// macro summary never carries money.
  Stream<Map<String, RecipeCostSummary>> watchRecipeCosts();

  /// Insert (new id) or replace (existing id) the whole aggregate.
  Future<void> saveRecipe(Recipe recipe);

  /// Soft-delete the recipe (and cascade its groups/items).
  Future<void> deleteRecipe(String id);

  /// Sets the household-shared favorite flag (the picker's Favorites tab).
  // ignore: avoid_positional_boolean_parameters — a set-flag pair reads fine.
  Future<void> setFavorite(String id, bool favorite);

  /// Re-files one recipe (0028 E8) — the Library's "Move to…".
  ///
  /// A narrow write, like [setFavorite] and unlike [saveRecipe]: re-shelving
  /// is a LIBRARY act, and routing it through a whole-recipe save would make
  /// moving a recipe an edit of every field it holds — including fields the
  /// mover never loaded. [sectionId] null files it unsectioned, which is what
  /// crossing a book boundary always means: a section belongs to the book it
  /// was named in.
  Future<void> setFiling(String id, String bookId, String? sectionId);

  /// The live recipes that list [recipeId] as a component, one row per
  /// referencing LINE (step 8.6 / D9). Its length is the count the "Used in ·
  /// N" tab shows *and* the count the delete refusal speaks — one query, two
  /// uses.
  Future<List<RecipeUse>> usedIn(String recipeId);

  /// Whether making [subRecipeId] a component of [recipeId] would close a
  /// cycle (step 8.6 / D5) — checked on device at link time over synced rows,
  /// mirroring migration 0017's trigger. Linking a recipe to itself counts.
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  });
}
