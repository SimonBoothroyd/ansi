// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/core/units/macros.dart';
import 'package:mise/features/books/data/book_providers.dart';
import 'package:mise/features/books/domain/book.dart';
import 'package:mise/features/books/domain/book_repository.dart';
import 'package:mise/features/planning/data/planning_providers.dart';
import 'package:mise/features/planning/domain/planning.dart';
import 'package:mise/features/planning/domain/planning_repository.dart';
import 'package:mise/features/planning/presentation/recipe_picker_sheet.dart';
import 'package:mise/features/recipes/data/recipe_providers.dart';
import 'package:mise/features/recipes/domain/recipe.dart';
import 'package:mise/features/recipes/domain/recipe_macros.dart';
import 'package:mise/features/recipes/domain/recipe_repository.dart';
import 'package:mise/shared/incomplete_macros.dart';

/// The picker's read models, canned: two recipes — a favorite with complete
/// per-serving macros planned 3 days ago, and an unplanned one whose macros
/// are honestly incomplete (one stub line).
const _curry = RecipeSummary(
  id: 'r1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
  keepsForDays: 4,
  freezable: true,
  favorite: true,
  macros: RecipeMacroSummary(
    perServing: Macros(kcal: 520.2, protein: 31.4, carb: 40, fat: 18),
  ),
);
const _salad = RecipeSummary(
  id: 'r2',
  title: 'Halloumi Salad',
  servingsBase: 2,
  macros: RecipeMacroSummary(stubLines: 1),
);
const _bare = RecipeSummary(
  id: 'r3',
  title: 'Bare Idea',
  servingsBase: 4,
  macros: RecipeMacroSummary(noLines: true),
);

class _FakeRecipeRepo implements RecipeRepository {
  _FakeRecipeRepo([this.recipes = const [_curry, _salad]]);

  final List<RecipeSummary> recipes;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(recipes);
  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);
  @override
  Future<void> saveRecipe(Recipe recipe) async {}
  @override
  Future<void> deleteRecipe(String id) async {}
  @override
  Future<void> setFavorite(String id, bool favorite) async {}
}

class _FakePlanningRepo implements PlanningRepository {
  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(null);
  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async => null;
  @override
  Future<List<Member>> members() async => const [
    Member(id: 'm1', displayName: 'Ada'),
    Member(id: 'm2', displayName: 'Jun'),
  ];
  @override
  Stream<Map<String, DateTime>> watchLastPlanned() =>
      Stream.value({'r1': DateTime.now().subtract(const Duration(days: 3))});
  @override
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  }) async => 'e';
  @override
  Future<void> setEaters(String entryId, List<String> eaterIds) async {}
  @override
  Future<void> removeEntry(String entryId) async {}
  @override
  Future<int> copyLastWeek(DateTime weekStart) async => 0;
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
  Future<void> reorderSections(
    String bookId,
    List<String> orderedSectionIds,
  ) async {}
  @override
  Future<void> deleteSection(String sectionId) async {}
  @override
  Future<void> assignRecipe(
    String recipeId, {
    required String bookId,
    String? sectionId,
  }) async {}
}

/// A host whose button opens the picker sheet for Wednesday dinner.
Widget _host({List<RecipeSummary> recipes = const [_curry, _salad]}) =>
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo(recipes)),
        planningRepositoryProvider.overrideWithValue(_FakePlanningRepo()),
        bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
      ],
      child: MaterialApp(
        home: FTheme(
          data: miseThemeData(),
          child: FScaffold(
            child: Builder(
              builder: (context) => Center(
                child: GestureDetector(
                  onTap: () => showRecipePickerSheet(
                    context,
                    dayOfWeek: 2,
                    slot: 'Dinner',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(
  WidgetTester tester, {
  List<RecipeSummary> recipes = const [_curry, _salad],
}) async {
  await tester.pumpWidget(_host(recipes: recipes));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rows are information-honest: recency, macros, incomplete', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Add a meal'), findsOneWidget);
    expect(find.textContaining('Wednesday, Dinner'), findsOneWidget);
    // The complete recipe: per-serving macros + recency; honest rounding.
    expect(find.textContaining('serves 4 · ~520 kcal · 31P'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);
    // The incomplete one: the badge and the reason — never zeros.
    expect(find.text('incomplete'), findsOneWidget);
    expect(find.textContaining('1 stub line'), findsOneWidget);
    expect(find.textContaining('~0 kcal'), findsNothing);
    // The eating footer names the household.
    expect(find.textContaining('Eating: '), findsOneWidget);
    expect(find.textContaining('Ada & Jun'), findsOneWidget);
  });

  testWidgets('a line-less recipe reads "no ingredients yet", never ~0 kcal', (
    tester,
  ) async {
    await _open(tester, recipes: const [_bare]);

    expect(find.text('incomplete'), findsOneWidget);
    expect(find.textContaining('no ingredients yet'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  test('incompleteNote never returns an empty string', () {
    // Every incomplete cause carries a reason — a reasonless badge would
    // leave a dangling separator on the row.
    expect(
      incompleteNote(const RecipeMacroSummary(noLines: true)),
      'no ingredients yet',
    );
    expect(
      // Servings ≤ 0 with zero stub/unconvertible lines (the DB check makes
      // this near-unreachable, but the note must stay total).
      incompleteNote(const RecipeMacroSummary()),
      'servings not set',
    );
    expect(
      incompleteNote(const RecipeMacroSummary(stubLines: 2)),
      '2 stub lines',
    );
  });

  testWidgets('Recent orders by last-planned, created order as fallback', (
    tester,
  ) async {
    // Incoming list order is created_at DESC (salad newer), but the rows
    // display last-planned recency — so the planned curry must lead, and
    // the never-planned salad follows in its created position (M11).
    await _open(tester, recipes: const [_salad, _curry]);

    final curryY = tester.getTopLeft(find.text('Weeknight Chicken Curry')).dy;
    final saladY = tester.getTopLeft(find.text('Halloumi Salad')).dy;
    expect(curryY, lessThan(saladY));
  });

  testWidgets('search matches word boundaries via the 7.4 normalizer', (
    tester,
  ) async {
    // Focusing a field in a live Forui sheet trips a framework semantics
    // assertion (tracker row `app/ui`); filter exactly that, as the
    // integration smoke does.
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('semantics.dart')) return;
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

    await _open(tester);

    await tester.enterText(find.byType(EditableText).first, 'chicken');
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('Halloumi Salad'), findsNothing);

    // Mid-word fragments never match (deterministic search, ADR-0004).
    await tester.enterText(find.byType(EditableText).first, 'hick');
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsNothing);
  });

  testWidgets('the Favorites tab shows only starred recipes', (tester) async {
    await _open(tester);

    expect(find.text('Halloumi Salad'), findsOneWidget);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('Halloumi Salad'), findsNothing);
  });

  testWidgets('an empty Favorites tab explains the affordance', (tester) async {
    await _open(tester, recipes: const [_salad]); // nothing starred
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.textContaining('star a recipe'), findsOneWidget);
  });
}
