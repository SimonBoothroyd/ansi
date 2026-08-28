/// Pins the editor draft lifecycle: saving a draft must reset the notifier so
/// the next "New recipe" open starts blank, even when the provider instance
/// outlives the editor screen (auto-dispose only fires once the last listener
/// is gone, which navigation timing can defer).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/features/books/data/book_providers.dart';
import 'package:mise/features/books/domain/book.dart';
import 'package:mise/features/books/domain/book_repository.dart';
import 'package:mise/features/recipes/data/recipe_providers.dart';
import 'package:mise/features/recipes/domain/recipe.dart';
import 'package:mise/features/recipes/domain/recipe_repository.dart';
import 'package:mise/features/recipes/presentation/recipe_view_models.dart';

class _FakeRecipeRepo implements RecipeRepository {
  final saved = <Recipe>[];

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(const []);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);

  @override
  Future<void> saveRecipe(Recipe recipe) async => saved.add(recipe);

  @override
  Future<void> deleteRecipe(String id) async {}
}

class _FakeBookRepo implements BookRepository {
  static const _book = Book(id: 'b1', name: 'Our Cookbook');

  @override
  Stream<List<Book>> watchLibrary() => Stream.value(const [_book]);

  @override
  Future<Book> ensureDefaultBook() async => _book;

  @override
  Future<String> createBook(String name) async => 'b';

  @override
  Future<String> createSection(String bookId, String name) async => 's';

  @override
  Future<void> renameSection(String sectionId, String name) async {}

  @override
  Future<void> reorderSections(String b, List<String> ids) async {}

  @override
  Future<void> deleteSection(String sectionId) async {}

  @override
  Future<void> assignRecipe(
    String recipeId, {
    required String bookId,
    String? sectionId,
  }) async {}
}

void main() {
  test('a "New recipe" open after a save starts from a clean draft', () async {
    final repo = _FakeRecipeRepo();
    final container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
      ],
    );
    addTearDown(container.dispose);

    // Hold a listener for the whole scenario, simulating a provider instance
    // that survives the save (the live leak this test pins).
    final sub = container.listen(recipeEditorProvider(null), (_, _) {});
    addTearDown(sub.close);

    final first = await container.read(recipeEditorProvider(null).future);
    container.read(recipeEditorProvider(null).notifier)
      ..setTitle('Weeknight Chicken Curry')
      ..addGroup();
    final id = await container
        .read(recipeEditorProvider(null).notifier)
        .save();

    expect(repo.saved, hasLength(1));
    expect(id, first.id);

    // A fresh open of the same provider must be a blank draft again — new id,
    // empty title, a single empty group.
    final next = await container.read(recipeEditorProvider(null).future);
    expect(next.id, isNot(first.id));
    expect(next.title, isEmpty);
    expect(next.groups, hasLength(1));
    expect(next.groups.single.items, isEmpty);
  });
}
