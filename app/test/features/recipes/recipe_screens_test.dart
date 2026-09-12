import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
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
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// The library and the page both read the one recipe under test, so the list
/// is derived from it rather than canned separately.
class _FakeRecipeRepo extends FakeRecipeRepository {
  _FakeRecipeRepo(Recipe? recipe) : super(recipe: recipe);

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    if (recipe != null)
      RecipeSummary(
        id: recipe!.id,
        title: recipe!.title,
        servingsBase: recipe!.servingsBase,
      ),
  ]);
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
      'identity column', (tester) async {
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

  testWidgets('RecipeView shows a line whose ingredient was retired — last '
      'known name, and the tag that says what to do', (tester) async {
    const recipe = Recipe(
      id: '4',
      title: 'Smashed Edamame Toast',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          items: [
            // The incident's shape: a live line, `to taste`, no quantity,
            // pointing at a vocab row an import duplicated and a hand pass
            // retired.
            LineItem(
              id: 'i1',
              ingredientId: 'sauerkraut',
              ingredientName: 'Sauerkraut',
              unit: toTaste,
              ingredientDeleted: true,
            ),
            LineItem(
              id: 'i2',
              ingredientId: 'bread',
              ingredientName: 'Bread',
              unit: g,
              quantity: 200,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(const RecipeView(recipeId: '4'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipe)),
      ]),
    );
    await tester.pump();

    // Named, not blanked, and not dropped: the reader can see which line
    // broke and what the recipe last called it.
    expect(
      find.textContaining('Sauerkraut', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(RemovedIngredientTag), findsOneWidget);
    expect(find.text('ingredient removed · pick again'), findsOneWidget);
    // The live neighbour is untouched — one broken link is not a broken page.
    expect(find.textContaining('Bread', findRichText: true), findsOneWidget);
    expect(find.text('200 g'), findsOneWidget);
  });

  testWidgets('the EDITOR tags an optional line too — an ingredient row and a '
      'component row alike', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const recipe = Recipe(
      id: '1',
      title: 'Sliders',
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
            LineItem(
              id: 'i3',
              subRecipeId: 'aioli',
              subRecipe: SubRecipeTarget(
                id: 'aioli',
                title: 'Romesco Aioli',
                yieldQty: 1,
                yieldUnit: cup,
              ),
              ingredientName: 'Romesco Aioli',
              unit: cup,
              quantity: 0.25,
              optional: true,
            ),
            LineItem(
              id: 'i4',
              subRecipeId: 'salsa',
              subRecipe: SubRecipeTarget(id: 'salsa', title: 'Green Salsa'),
              ingredientName: 'Green Salsa',
              unit: cup,
              quantity: 0.5,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(const RecipeEditorView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipe)),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();

    // Two optional lines, two tags — the flag is a fact about the line, so the
    // screen that EDITS the line has to show it as plainly as the page does.
    // Four lines, two tags: the other two say nothing.
    expect(find.byType(OptionalTag), findsNWidgets(2));

    // …and each tag is on its own line, not floating over the list. In tree
    // order the first belongs to the ingredient row and the second to the
    // component row.
    final rice = tester.getRect(find.textContaining('Rice').first);
    final salsa = tester.getRect(find.text('Green Salsa'));
    for (final (index, row) in [
      tester.getRect(find.textContaining('Lime').first),
      tester.getRect(find.text('Romesco Aioli')),
    ].indexed) {
      final tag = tester.getRect(find.byType(OptionalTag).at(index));
      expect(tag.top < row.bottom && row.top < tag.bottom, isTrue);
      expect(tag.top < rice.bottom && rice.top < tag.bottom, isFalse);
      expect(tag.top < salsa.bottom && salsa.top < tag.bottom, isFalse);
    }
  });

  group("an ingredient's name is a door onto its own page", () {
    /// The page under a real router, so the tap has an observable
    /// destination — a stand-in stands at `/ingredients/:id`.
    Widget routed(Recipe recipe, void Function(GoRouter) expose) => routedHost(
      initial: '/recipes/${recipe.id}',
      overrides: [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipe)),
      ],
      expose: expose,
      routes: {
        '/recipes/:id': (_, state) =>
            RecipeView(recipeId: state.pathParameters['id']!),
        '/ingredients/:id': (_, state) =>
            FScaffold(child: Text('ingredient ${state.pathParameters['id']}')),
      },
    );

    testWidgets('tapping the name pushes that ingredient', (tester) async {
      late GoRouter router;
      await tester.pumpWidget(routed(_recipe, (r) => router = r));
      await tester.pump();

      await tester.tapOnText(find.textRange.ofSubstring('Chicken thigh'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/ingredients/chicken');
      expect(find.text('ingredient chicken'), findsOneWidget);
    });

    testWidgets('a folded multi-use row has ONE door, and the note is not '
        'it', (tester) async {
      const recipe = Recipe(
        id: '2',
        title: 'Two Ways',
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

      late GoRouter router;
      await tester.pumpWidget(routed(recipe, (r) => router = r));
      await tester.pump();

      // The note is a fact about the line, not the identity — it goes nowhere.
      await tester.tapOnText(
        find.textRange.ofSubstring('finely chopped + sliced'),
      );
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/recipes/2');

      // The one name the fold left standing is the door for both uses.
      await tester.tapOnText(find.textRange.ofSubstring('Garlic'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/ingredients/garlic');
    });
  });

  testWidgets('RecipeEditorView builds a blank create form', (tester) async {
    filterForuiSemanticsAssertions();

    await tester.pumpWidget(
      _host(const RecipeEditorView(), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(null)),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
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

  testWidgets('an unresolved measure says WHICH kind it is — deleted, or not '
      'here yet', (tester) async {
    filterForuiSemanticsAssertions();
    // The form is one long scroll; give it room so both lines are built.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const withGhosts = Recipe(
      id: '1',
      title: 'Weeknight Curry',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          items: [
            LineItem(
              id: 'i-onion',
              ingredientId: 'ing-onion',
              ingredientName: 'Onion',
              unit: pieces,
              quantity: 2,
              measureId: 'm-gone',
              measureDeleted: true,
            ),
            LineItem(
              id: 'i-carrot',
              ingredientId: 'ing-carrot',
              ingredientName: 'Carrot',
              unit: pieces,
              quantity: 3,
              measureId: 'm-unsynced',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(const RecipeEditorView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(withGhosts)),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();

    // Both lines fall back to the stored count; only one of them is waiting
    // on anything, and the other must not promise a sync that never comes.
    expect(find.text('2 piece · measure deleted'), findsOneWidget);
    expect(find.text('3 piece · measure pending sync'), findsOneWidget);
  });

  testWidgets('the EDITOR names a retired ingredient and its identity cell '
      'opens the picker, so the line can be re-pointed', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const broken = Recipe(
      id: '1',
      title: 'Smashed Edamame Toast',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          items: [
            LineItem(
              id: 'i1',
              ingredientId: 'sauerkraut',
              ingredientName: 'Sauerkraut',
              unit: toTaste,
              ingredientDeleted: true,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(const RecipeEditorView(recipeId: '1'), [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(broken)),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();

    final name = find.textContaining('Sauerkraut', findRichText: true);
    expect(name, findsOneWidget);
    expect(find.byType(RemovedIngredientTag), findsOneWidget);

    // "pick again" is a door, not a diagnosis: the identity cell the tag
    // hangs off is the shipped target picker, and the line keeps its id
    // through the swap (which is what stops every method chip going
    // dangling).
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(find.text('Change Sauerkraut to'), findsOneWidget);
  });

  testWidgets('the editor draws the second MAKES denomination, with the ✕ that '
      'drops it', (tester) async {
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
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
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

  testWidgets(
    'the recipe page prints the stated times as chips, and only the stated '
    'ones',
    (tester) async {
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
    },
  );
}
