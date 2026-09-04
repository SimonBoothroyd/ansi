/// The editor's one door (step 8.6 / D7, board frame c): the shipped
/// ingredient picker with a "Your recipes" section under it — and D5's rule
/// that a cycle-forming target is never offered.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/search/search_rank.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/line_target_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

const _romaTomato = Ingredient(
  id: 'i-roma',
  canonicalName: 'Roma tomato',
  defaultUnit: g,
  status: IngredientStatus.complete,
  category: 'produce',
);

const _aioli = RecipeSummary(
  id: 'aioli',
  title: 'Romesco Aioli',
  servingsBase: 4,
  yieldQty: 1,
  yieldUnit: cup,
);

const _toasts = RecipeSummary(
  id: 'toasts',
  title: 'Romesco Toasts',
  servingsBase: 2,
);

const _library = [
  Book(
    id: 'b1',
    name: 'Our Cookbook',
    sections: [
      BookSection(id: 's1', name: 'Sauces', recipes: [_aioli]),
      BookSection(id: 's2', name: 'Small plates', recipes: [_toasts]),
    ],
  ),
];

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(_library);
}

/// A repository whose cycle guard refuses exactly [cycles].
/// The library the picker searches, with the links that would close a cycle
/// named up front — the refusal is what this suite drives.
class _FakeRecipeRepo extends FakeRecipeRepository {
  _FakeRecipeRepo({this.cycles = const {}})
    : super(summaries: const [_aioli, _toasts]);

  final Set<String> cycles;

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => cycles.contains(subRecipeId);
}

Future<PickedLineTarget?> _open(
  WidgetTester tester, {
  required String editingRecipeId,
  Set<String> cycles = const {},
  List<Ingredient> vocabulary = const [_romaTomato],
}) async {
  filterForuiSemanticsAssertions();
  PickedLineTarget? picked;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ingredientRepositoryProvider.overrideWithValue(
          FakeIngredientRepo(vocabulary),
        ),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
        recipeRepositoryProvider.overrideWithValue(
          _FakeRecipeRepo(cycles: cycles),
        ),
      ],
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () async => picked = await showLineTargetPicker(
                  context,
                  editingRecipeId: editingRecipeId,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  group('the title rule is the SHARED one now', () {
    // `recipeTitleMatches` is gone; `recipeTitleHit` answers for both recipe
    // pickers, and `cross_picker_search_test.dart` is what holds them
    // together. What survives here is the behaviour this section owns.
    test('hits a title, or any word inside it', () {
      for (final q in ['rom', 'aio', 'ROMESCO A']) {
        expect(recipeTitleHit('Romesco Aioli', q)?.tier, SearchTier.prefix);
      }
    });

    test('a mid-word fragment is never a spelled hit', () {
      expect(
        recipeTitleHit('Romesco Aioli', 'esco')?.tier,
        isNot(SearchTier.prefix),
      );
    });

    test('no query, no section: this list is not a browse surface', () {
      expect(recipeTitleHit('Romesco Aioli', '  '), isNull);
    });
  });

  test('recipeCandidates carries the book · section filing', () {
    final candidates = recipeCandidates(_library);
    expect(candidates.map((c) => c.filing), [
      'Our Cookbook · Sauces',
      'Our Cookbook · Small plates',
    ]);
  });

  testWidgets('the "Your recipes" section appears only once the query hits a '
      'title, under the ingredient results', (tester) async {
    await _open(tester, editingRecipeId: 'sliders');

    // Before a query: the shipped picker, unchanged.
    expect(find.text('YOUR RECIPES'), findsNothing);
    expect(find.text('INGREDIENTS'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'rom');
    await tester.pumpAndSettle();

    expect(find.text('YOUR RECIPES'), findsOneWidget);
    expect(find.text('INGREDIENTS'), findsOneWidget);
    expect(find.text('Romesco Aioli'), findsOneWidget);
    expect(find.text('Our Cookbook · Sauces'), findsOneWidget);
    // A yield is the row's hint; a recipe without one still links and says so.
    expect(find.text('makes 1 cup'), findsOneWidget);
    expect(find.text('no yield yet'), findsOneWidget);
  });

  testWidgets('the recipe being edited is never offered as its own component', (
    tester,
  ) async {
    await _open(tester, editingRecipeId: 'aioli');
    await tester.enterText(find.byType(TextField).first, 'rom');
    await tester.pumpAndSettle();

    expect(find.text('Romesco Toasts'), findsOneWidget);
    expect(find.text('Romesco Aioli'), findsNothing);
  });

  testWidgets('a cycle-forming target is not offered (D5)', (tester) async {
    await _open(tester, editingRecipeId: 'sliders', cycles: {'toasts'});
    await tester.enterText(find.byType(TextField).first, 'rom');
    await tester.pumpAndSettle();

    expect(find.text('Romesco Aioli'), findsOneWidget);
    expect(find.text('Romesco Toasts'), findsNothing);
  });

  testWidgets('picking a recipe hands back the target with its yields', (
    tester,
  ) async {
    PickedLineTarget? picked;
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo(const [_romaTomato]),
          ),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        ],
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: Builder(
              builder: (context) => Center(
                child: GestureDetector(
                  onTap: () async => picked = await showLineTargetPicker(
                    context,
                    editingRecipeId: 'sliders',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'romesco a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romesco Aioli'));
    await tester.pumpAndSettle();

    expect(picked, isA<PickedSubRecipe>());
    final target = (picked! as PickedSubRecipe).target;
    expect(target.id, 'aioli');
    expect(target.yields, [(qty: 1.0, unit: cup)]);
  });

  testWidgets('an ingredient still comes back as an ingredient', (
    tester,
  ) async {
    PickedLineTarget? picked;
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo(const [_romaTomato]),
          ),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        ],
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: Builder(
              builder: (context) => Center(
                child: GestureDetector(
                  onTap: () async => picked = await showLineTargetPicker(
                    context,
                    editingRecipeId: 'sliders',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roma tomato'));
    await tester.pumpAndSettle();

    expect(picked, isA<PickedIngredient>());
    expect((picked! as PickedIngredient).ingredient.id, 'i-roma');
  });

  testWidgets('add-new is the one chain (plan 0025 D3): sheet → form → back, '
      'and the editor gets an ingredient carrying the units the form set', (
    tester,
  ) async {
    // The editor's `_addLine` awaits this picker and then opens the quantity
    // sheet on whatever comes back — so the picker must not resolve until
    // the form has popped, and must resolve with the re-read row.
    filterForuiSemanticsAssertions();
    final repo = FakeIngredientRepo(const [_romaTomato]);
    final picked = <PickedLineTarget?>[];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => FScaffold(
            child: Builder(
              builder: (context) => FButton(
                onPress: () async => picked.add(
                  await showLineTargetPicker(
                    context,
                    editingRecipeId: 'sliders',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        // The create form, stubbed: since plan 0029 C2 the picker pushes it
        // directly instead of opening a sheet that made the row first, and
        // it pops with the row its one Save made.
        GoRoute(
          path: '/ingredients/new',
          builder: (context, state) => FScaffold(
            child: FButton(
              onPress: () async {
                final saved = await repo.saveForm(
                  null,
                  IngredientFormEdit(
                    row: IngredientEdit(
                      canonicalName: state.uri.queryParameters['name'] ?? '',
                      defaultUnit: g,
                      macrosBasis: MacrosBasis.perG,
                      allowedUnits: {g, kg},
                    ),
                  ),
                );
                if (context.mounted) context.pop(saved);
              },
              child: const Text('create'),
            ),
          ),
        ),
        GoRoute(
          path: '/ingredients/:id',
          builder: (context, state) => FScaffold(
            child: FButton(
              onPress: () => context.pop(),
              child: Text('form ${state.pathParameters['id']}'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingredientRepositoryProvider.overrideWithValue(repo),
          measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
          usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              FTheme(data: ansiThemeData(), child: child!),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'curry leaves');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('add "curry leaves"'));
    await tester.pumpAndSettle();
    // One screen, not two: the FORM opens, and nothing resolves until it
    // pops with the row its Save made.
    expect(find.text('create'), findsOneWidget);
    expect(picked, isEmpty, reason: 'nothing resolves before the form pops');

    await tester.tap(find.text('create'));
    await tester.pumpAndSettle();
    final created = repo.rows.last;

    expect(picked.single, isA<PickedIngredient>());
    final ingredient = (picked.single! as PickedIngredient).ingredient;
    expect(ingredient.id, created.id);
    expect(ingredient.allowedUnits, [g, kg]);
  });
}
