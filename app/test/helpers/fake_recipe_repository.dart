/// A [RecipeRepository] whose reads are canned and whose narrow writes are
/// recorded, for widget and state tests that need the aggregate but not a
/// database.
///
/// Subclass and override only the method the test drives; anything left alone
/// answers with the empty, harmless value. The recording fields carry what a
/// write *asked for*, so a test can assert on the call rather than on a
/// re-render — which is the only way to see a narrow write like a re-filing
/// land at all.
library;

import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';

class FakeRecipeRepository implements RecipeRepository {
  FakeRecipeRepository({
    this.summaries = const [],
    this.recipe,
    this.costs = const {},
  });

  /// What [watchRecipeCosts] emits, keyed by recipe id. Empty by default —
  /// the state of a household that has priced nothing, which is where every
  /// test that is not about cost belongs.
  final Map<String, RecipeCostSummary> costs;

  /// What [watchRecipes] emits.
  final List<RecipeSummary> summaries;

  /// What [watchRecipe] emits, whichever id is asked for.
  final Recipe? recipe;

  /// Every aggregate handed to [saveRecipe], in order.
  final saved = <Recipe>[];

  /// Every id handed to [deleteRecipe], in order.
  final deleted = <String>[];

  /// What the last [setFavorite] asked for.
  ({String id, bool favorite})? favorited;

  /// What the last [setFiling] asked for.
  ({String id, String bookId, String? sectionId})? filed;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(summaries);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(recipe);

  @override
  Stream<Map<String, RecipeCostSummary>> watchRecipeCosts() =>
      Stream.value(costs);

  @override
  Future<void> saveRecipe(Recipe recipe) async => saved.add(recipe);

  @override
  Future<void> deleteRecipe(String id) async => deleted.add(id);

  @override
  Future<void> setFavorite(String id, bool favorite) async {
    favorited = (id: id, favorite: favorite);
  }

  @override
  Future<void> setFiling(String id, String bookId, String? sectionId) async {
    filed = (id: id, bookId: bookId, sectionId: sectionId);
  }

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}
