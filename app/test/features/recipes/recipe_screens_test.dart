import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';

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
  Future<void> setFiling(String id, String bookId, String? sectionId) async {}

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
  Future<Ingredient?> saveForm(String? ingredientId, IngredientFormEdit edit) =>
      throw UnimplementedError();

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      (rows: const <Ingredient>[], guessed: false);

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async =>
      null;

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Future<Ingredient?> byId(String id) async => null;

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => const {};
}

/// The editor defaults new recipes into a book and renders a section picker.
class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(const [Book(id: 'b1', name: 'Our Cookbook')]);
}

Widget _host(Widget child, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: child),
  ),
);

/// The editor as it is actually reached: pushed from a page that must still be
/// there when the save lands.
Widget _routedHost(GoRouter router, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp.router(
    routerConfig: router,
    builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
  ),
);

/// Pumps frames until [finder] matches, then keeps pumping long enough for the
/// route transition to land.
///
/// `pumpAndSettle` is not usable on these screens — they carry perpetual
/// animations, which is why the sibling tests pump rather than settle. And a
/// widget is findable the moment it is BUILT, which here is while its page is
/// still sliding in: a tap taken then lands beside the target, off-screen.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int frames = 60,
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      for (var settle = 0; settle < 10; settle++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return;
    }
  }
  fail('never found $finder');
}

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

  testWidgets('RecipeView tags an optional line after its note, in the '
      'identity column (plan 0025 / D6b)', (tester) async {
    const recipe = Recipe(
      id: '3',
      title: 'Curry',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          items: [
            LineItem(
              id: 'i1',
              ingredientId: 'lime',
              ingredientName: 'Lime',
              unit: pieces,
              quantity: 1,
              note: 'to serve',
              optional: true,
            ),
            LineItem(
              id: 'i2',
              ingredientId: 'rice',
              ingredientName: 'Rice',
              unit: g,
              quantity: 200,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '3'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipe)),
      ]),
    );
    await tester.pump();

    // One tag, on the lime row only — and the amount column still says "1":
    // the tag is a fact about the line, not about its amount.
    expect(find.byType(OptionalTag), findsOneWidget);
    expect(find.text('optional'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('200 g'), findsOneWidget);
  });

  testWidgets('RecipeEditorView builds a blank create form', (tester) async {
    filterForuiSemanticsAssertions();

    await tester.pumpWidget(
      _host(const RecipeEditorView(), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(null)),
        ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
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
    filterForuiSemanticsAssertions();

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
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
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

  testWidgets('saving replaces the editor, so back returns to where it was '
      'opened from', (tester) async {
    filterForuiSemanticsAssertions();
    // A phone-sized surface: at the default 800x600 the header's Save sits off
    // the right edge and the tap misses it.
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const FScaffold(child: Text('the library')),
        ),
        GoRoute(
          path: '/recipes/new',
          builder: (_, _) => const RecipeEditorView(),
        ),
        GoRoute(
          path: '/recipes/:id',
          builder: (_, state) =>
              RecipeView(recipeId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routedHost(router, [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(_recipe)),
        ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ]),
    );
    await _pumpUntil(tester, find.text('the library'));

    // NOT awaited: a push's future completes when the route is POPPED, so
    // awaiting it here would block the test before a frame could be pumped.
    unawaited(router.push('/recipes/new'));
    await _pumpUntil(tester, find.text('New recipe'));
    await tester.enterText(find.byType(EditableText).first, 'Curry');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await _pumpUntil(tester, find.text('Weeknight Chicken Curry'));

    // The editor was REPLACED, not stacked on and not flattened away: the
    // saved recipe is on top and the page it was opened from is still under
    // it, which is what keeps back (and the iOS edge swipe) working.
    expect(router.routerDelegate.currentConfiguration.matches.length, 2);
    expect(find.text('New recipe'), findsNothing);

    router.pop();
    await _pumpUntil(tester, find.text('the library'));
    expect(router.state.uri.toString(), '/');
  });

  testWidgets('the recipe page prints the stated times as chips, and only '
      'the stated ones (plan 0025 #4)', (tester) async {
    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(
          _FakeRecipeRepo(
            _recipe.copyWith(cookTimeSeconds: 2100, totalTimeSeconds: 4200),
          ),
        ),
      ]),
    );
    await tester.pump();
    expect(find.text('cook 35 min'), findsOneWidget);
    expect(find.text('1 h 10 min total'), findsOneWidget);

    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(
          _FakeRecipeRepo(_recipe.copyWith(cookTimeSeconds: 2100)),
        ),
      ]),
    );
    await tester.pump();
    expect(find.text('cook 35 min'), findsOneWidget);
    expect(find.textContaining('total'), findsNothing);
  });
}
