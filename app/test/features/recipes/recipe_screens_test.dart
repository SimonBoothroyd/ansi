import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_repository.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_ingredient_repository.dart';

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

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}

class _FakeIngredientRepo
    with IngredientManagerStubs
    implements IngredientRepository {
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
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => const {};

  @override
  Future<Ingredient> createStub(
    String name, {
    String source = 'manual',
    Macros? macros,
    MacrosBasis macrosBasis = MacrosBasis.perG,
  }) async => Ingredient(
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
    home: FTheme(data: ansiThemeData(), child: child),
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

  testWidgets('RecipeView folds two uses of one ingredient into one row', (
    tester,
  ) async {
    const recipe = Recipe(
      id: '2',
      title: 'Garlic Two Ways',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          items: [
            LineItem(
              id: 'i1',
              ingredientId: 'garlic',
              ingredientName: 'Garlic',
              unit: pieces,
              quantity: 2,
              note: 'finely chopped',
            ),
            LineItem(
              id: 'i2',
              ingredientId: 'garlic',
              ingredientName: 'Garlic',
              unit: pieces,
              quantity: 1,
              note: 'sliced',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '2'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipe)),
      ]),
    );
    await tester.pump();

    // One folded row: the two garlic uses share a single amount cell whose
    // amounts are joined "2 + 1" (never summed to 3).
    expect(find.text('2 + 1'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    // The ingredient identity renders in a rich line (amount + name + notes).
    expect(find.textContaining('Garlic', findRichText: true), findsWidgets);
  });

  testWidgets('RecipeEditorView builds a blank create form', (tester) async {
    // Scrolling a Forui FSelect out of view with the semantics tree live trips
    // a framework assertion (tracker row `app/ui`) — the MAKES row (8.6) put a
    // third one in this form. Filter exactly that, as the quantity-sheet and
    // edit-top-up tests do.
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('semantics.dart')) return;
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

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
    // What a batch MAKES sits under SERVES, optional (8.6, board frame h) —
    // and the second denomination is only addable once the first is stated.
    expect(find.text('SERVES'), findsOneWidget);
    expect(find.text('MAKES'), findsOneWidget);
    expect(find.text('· optional'), findsOneWidget);
    expect(find.text('Another denomination'), findsNothing);
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

  testWidgets('the editor draws the second MAKES denomination, with the ✕ that '
      'drops it (8.6, board frame h)', (tester) async {
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('semantics.dart')) return;
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

    const butter = Recipe(
      id: '1',
      title: 'Garlic Butter',
      servingsBase: 4,
      yieldQty: 250,
      yieldUnit: g,
      yieldQty2: 16,
      yieldUnit2: tbsp,
    );
    await tester.pumpWidget(
      _host(const RecipeEditorView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(butter)),
        ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();

    // Both denominations, and the note that pins the family rule.
    expect(find.text('250'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(
      find.textContaining('only offers the other families'),
      findsOneWidget,
    );
    // The second slot's remove affordance is the only ✕ in the numbers block.
    expect(find.byIcon(FLucideIcons.x), findsWidgets);
    // With a second denomination already stated, nothing offers to add one.
    expect(find.text('Another denomination'), findsNothing);
  });
}
