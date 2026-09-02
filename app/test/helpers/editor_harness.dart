/// The recipe-editor widget harness the 0022 method-editor suites share: the
/// fakes, two specimen recipes (an imported, tokenized one and a legacy
/// plain-text one), and the scroll that reaches the METHOD slot.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_repository.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import 'fake_ingredient_repository.dart';

class FakeRecipeRepo implements RecipeRepository {
  FakeRecipeRepo(this.recipe);

  final Recipe? recipe;
  final saved = <Recipe>[];

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(const []);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(recipe);

  @override
  Future<void> saveRecipe(Recipe r) async => saved.add(r);

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

class FakeIngredientRepo
    with IngredientManagerStubs
    implements IngredientRepository {
  @override
  Future<List<Ingredient>> search(String query, {int limit = 30}) async => [
    if (query.isNotEmpty)
      const Ingredient(
        id: 'ing-new',
        canonicalName: 'Pork sausage',
        defaultUnit: g,
        status: IngredientStatus.complete,
      ),
  ];

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

class FakeBookRepo implements BookRepository {
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

/// The editor form trips a framework semantics assertion in the test binding
/// (the same one `recipe_screens_test.dart` has muted since 8.6). Mute it for
/// the duration of one test rather than restating the dance in each suite.
void ignoreSemanticsAsserts() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

/// The editor under a real router, because Save navigates to the recipe page
/// and the card's sheets are opened on the ROOT navigator.
Widget hostEditor(String? recipeId, List<Override> overrides) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => RecipeEditorView(recipeId: recipeId),
      ),
      GoRoute(path: '/recipes/:id', builder: (_, _) => const SizedBox()),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) =>
          FTheme(data: ansiThemeData(), child: child ?? const SizedBox()),
    ),
  );
}

/// Two lines and a tokenized two-step method — the sausage-sliders shape,
/// small enough to assert against.
const importedRecipe = Recipe(
  id: '1',
  title: 'Sausage Sliders',
  servingsBase: 4,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'l1',
          ingredientId: 'fennel',
          ingredientName: 'Fennel bulb',
          unit: pieces,
          quantity: 1,
        ),
        LineItem(
          id: 'l2',
          ingredientId: 'buns',
          ingredientName: 'Pretzel Buns',
          unit: pieces,
          quantity: 8,
        ),
      ],
    ),
  ],
  methodSteps: [
    MethodStep(
      tokens: [
        MethodText(s: 'Halve the '),
        MethodRef(refs: ['l1'], label: 'fennel bulb'),
        MethodText(s: ' and roast for '),
        MethodTimer(lowSeconds: 1500, highSeconds: 1800),
        MethodText(s: '.'),
      ],
    ),
    MethodStep(tokens: [MethodText(s: 'Then slice the buns.')]),
  ],
);

/// A method whose chip points at a line the recipe does not have — the shape
/// a delete + re-add used to leave behind.
const danglingRecipe = Recipe(
  id: '1',
  title: 'Sliders',
  servingsBase: 4,
  groups: [IngredientGroup(id: 'g1')],
  methodSteps: [
    MethodStep(
      tokens: [
        MethodText(s: 'Brown the '),
        MethodRef(refs: ['gone'], label: 'sausage'),
        MethodText(s: ' well.'),
      ],
    ),
  ],
);

/// The other shape the editor used to have: plain `steps`, no tokens.
const legacyRecipe = Recipe(
  id: '1',
  title: 'Weeknight Curry',
  servingsBase: 4,
  groups: [IngredientGroup(id: 'g1')],
  steps: ['Dice the onion.', 'Simmer gently.'],
);

/// Brings the METHOD slot into view — it sits below the shelf-life and
/// ingredient sections.
Future<void> scrollToMethod(WidgetTester tester) => tester.scrollUntilVisible(
  find.text('METHOD'),
  240,
  scrollable: find.byType(Scrollable).first,
);

/// Gives the test a surface tall enough to hold the whole editor form, so a
/// suite can tap anything without scrolling. (Scrolling the form disposes
/// Forui's `FSelect` items mid-frame, which throws from inside the package.)
void tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Scrolls back to Save and taps it, so a suite can assert on what the
/// notifier actually wrote.
Future<void> saveEditor(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Save'),
    -240,
    scrollable: find.byType(Scrollable).first,
  );
  await tapSave(tester);
}

/// Taps Save on a surface where it is already visible.
Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

/// Every step card's editable, in card order — told apart from the form's
/// other fields by the controller that paints the chips.
Finder methodFields() => find.byWidgetPredicate(
  (w) =>
      w is EditableText &&
      w.controller.runtimeType.toString() == 'MethodSpanController',
);

/// The text the step card at [index] is showing.
String methodFieldText(WidgetTester tester, int index) =>
    tester.widgetList<EditableText>(methodFields()).elementAt(index)
        .controller
        .text;
