import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/books/data/book_providers.dart';
import 'package:mise/features/books/domain/book.dart';
import 'package:mise/features/books/domain/book_repository.dart';
import 'package:mise/features/ingredients/data/ingredient_providers.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';
import 'package:mise/features/ingredients/domain/ingredient_repository.dart';
import 'package:mise/features/recipes/data/recipe_providers.dart';
import 'package:mise/features/recipes/domain/recipe.dart';
import 'package:mise/features/recipes/domain/recipe_repository.dart';
import 'package:mise/features/recipes/presentation/recipe_editor_view.dart';
import 'package:mise/features/recipes/presentation/recipe_view.dart';

class _FakeRecipeRepo implements RecipeRepository {
  _FakeRecipeRepo(this.recipe);

  final Recipe? recipe;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    if (recipe != null)
      RecipeSummary(
        id: recipe!.id,
        title: recipe!.title,
        servingsBase: recipe!.servingsBase,
      ),
  ]);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(recipe);

  @override
  Future<void> saveRecipe(Recipe recipe) async {}

  @override
  Future<void> deleteRecipe(String id) async {}

  @override
  Future<void> setFavorite(String id, bool favorite) async {}
}

class _FakeIngredientRepo implements IngredientRepository {
  @override
  Future<List<Ingredient>> search(String query, {int limit = 30}) async =>
      const [];

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async =>
      null;

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Future<Ingredient?> byId(String id) async => null;

  @override
  Future<Ingredient> createStub(String name) async => Ingredient(
    id: 'stub-1',
    canonicalName: name,
    defaultUnit: g,
    status: IngredientStatus.stub,
  );
}

/// The editor defaults new recipes into a book and renders a section picker.
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

Widget _host(Widget child, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: miseThemeData(), child: child),
  ),
);

const _recipe = Recipe(
  id: '1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
  keepsForDays: 4,
  freezable: true,
  freezerDays: 60,
  groups: [
    IngredientGroup(
      id: 'g1',
      name: 'for the curry',
      items: [
        LineItem(
          id: 'i1',
          ingredientId: 'chicken',
          ingredientName: 'Chicken thigh',
          unit: g,
          quantity: 600,
        ),
        LineItem(
          id: 'i2',
          ingredientId: 'salt',
          ingredientName: 'Salt',
          unit: toTaste,
        ),
      ],
    ),
  ],
  steps: ['Dice the onion.', 'Simmer gently.'],
);

void main() {
  testWidgets('RecipeView renders the scaled ingredients + method', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(_recipe)),
      ]),
    );
    await tester.pump();

    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('for the curry'), findsOneWidget);
    expect(find.text('600 g'), findsOneWidget);
    expect(find.text('to taste'), findsOneWidget);
    expect(find.text('keeps 4 d'), findsOneWidget);
  });

  testWidgets('RecipeEditorView builds a blank create form', (tester) async {
    await tester.pumpWidget(
      _host(const RecipeEditorView(), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(null)),
        ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
      ]),
    );
    await tester.pump();

    expect(find.text('New recipe'), findsOneWidget);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('SHELF LIFE'), findsOneWidget);
    expect(find.text('Keeps in the fridge'), findsOneWidget);
    // METHOD and the group controls sit below the fold now the shelf-life
    // section is in the form — scroll the outer list to reach them.
    await tester.scrollUntilVisible(
      find.text('METHOD'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('METHOD'), findsOneWidget);
    expect(find.text('Add group'), findsOneWidget);
    expect(find.text('Add ingredient'), findsOneWidget);
  });
}
