/// **The** test this lane exists for: the planning picker and the editor's
/// "Your recipes" section, driven over the SAME corpus with the SAME query,
/// must render the same titles.
///
/// They used to carry different rules one screen apart, and they failed in
/// opposite directions — the planner found "pasta tomato" and "jalapeño" but
/// not "fungi"; the editor found "fungi" and neither of the others, because it
/// split words on `[^a-z0-9]+` so an accented letter was a word break. Neither
/// found "almonds" in "Almond Cake", which the ingredient picker one screen
/// away found fine. Both now call `recipeTitleHit`; this is what would catch
/// the next attempt to give one of them a rule of its own.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_repository.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/planning_repository.dart';
import 'package:ansi/features/planning/presentation/recipe_picker_sheet.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/line_target_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';

/// One corpus, drawn from the extraction gold set — an apostrophe, an accent,
/// a plural, and a title word ("Jars") the phrase normalizer would eat.
const _titles = [
  'Romesco Aioli',
  'Green Goddess Chickpea Jars',
  'Weeknight Tomato Pasta',
  'Almond Cake',
  'Grilled Jalapeño Poppers',
  "Gumbo z'Fungi",
];

final _recipes = [
  for (final (i, title) in _titles.indexed)
    RecipeSummary(id: 'r$i', title: title, servingsBase: 2),
];

/// The queries the audit measured the two pickers disagreeing on, plus the
/// owner's own probe (`aoli`) that neither answered.
const _queries = [
  'romesco',
  'goddess chickpea',
  'chickpea goddess',
  'tomato pasta',
  'pasta tomato',
  'jars',
  'almonds',
  'jalapeño',
  'jalapeno',
  'fungi',
  'aoli',
  'wekenight',
  'qqqq',
];

class _FakeRecipeRepo implements RecipeRepository {
  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(_recipes);
  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);
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

class _FakeBookRepo implements BookRepository {
  @override
  Stream<List<Book>> watchLibrary() => Stream.value([
    Book(id: 'b1', name: 'Our Cookbook', unsectioned: _recipes),
  ]);
  @override
  Future<Book> ensureDefaultBook() async =>
      const Book(id: 'b1', name: 'Our Cookbook');
  @override
  Future<String> createBook(String name) async => 'b';
  @override
  Future<String> createSection(String bookId, String name) async => 's';
  @override
  Future<void> renameSection(String sectionId, String name) async {}
  @override
  Future<void> reorderSections(String bookId, List<String> ordered) async {}
  @override
  Future<void> deleteSection(String sectionId) async {}
  @override
  Future<void> assignRecipe(
    String recipeId, {
    required String bookId,
    String? sectionId,
  }) async {}

  @override
  Future<int> countBooks() => throw UnimplementedError();

  @override
  Future<int> countRecipesIn(String bookId) => throw UnimplementedError();

  @override
  Future<void> deleteBook(String bookId) => throw UnimplementedError();

  @override
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  }) => throw UnimplementedError();

  @override
  Future<void> renameBook(String bookId, String name) =>
      throw UnimplementedError();

  @override
  Future<void> reorderBooks(List<String> orderedBookIds) =>
      throw UnimplementedError();
}

class _FakePlanningRepo implements PlanningRepository {
  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(null);
  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async => null;
  @override
  Future<List<Member>> members() async => const [];

  @override
  Stream<List<Member>> watchMembers() => Stream.fromFuture(members());

  @override
  Future<void> setPortionFactor(String memberId, double factor) async {}
  @override
  Stream<Map<String, DateTime>> watchLastPlanned() => Stream.value(const {});
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

  @override
  Future<void> setPortions(String entryId, int? portions) =>
      throw UnimplementedError();
}

/// Opening a Forui sheet with the semantics tree live trips a framework
/// assertion (tracker row `app/ui`); filter exactly that.
void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

Widget _host(Widget Function(BuildContext) open) => ProviderScope(
  overrides: [
    recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
    bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
    planningRepositoryProvider.overrideWithValue(_FakePlanningRepo()),
    ingredientRepositoryProvider.overrideWithValue(
      FakeIngredientRepo(const []),
    ),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: Builder(builder: (context) => Center(child: open(context))),
    ),
  ),
);

/// The titles a picker actually renders.
Set<String> _shown(WidgetTester tester) => {
  for (final title in _titles)
    if (tester.any(find.text(title))) title,
};

Future<Set<String>> _planningPickerShows(
  WidgetTester tester,
  String query,
) async {
  _filterSemanticsAssertions();
  // Tear down whatever the previous call left mounted: a sheet still on the
  // route stack would swallow the tap that opens the next one.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  // A surface tall enough for the whole corpus. Both pickers scroll, and a
  // row that never got laid out is a row `find.text` cannot see — which would
  // make this comparison about viewport height rather than about the rule.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      (context) => GestureDetector(
        onTap: () =>
            showRecipePickerSheet(context, dayOfWeek: 2, slot: 'Dinner'),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText).first, query);
  await tester.pumpAndSettle();
  return _shown(tester);
}

Future<Set<String>> _linePickerShows(WidgetTester tester, String query) async {
  _filterSemanticsAssertions();
  // Tear down whatever the previous call left mounted: a sheet still on the
  // route stack would swallow the tap that opens the next one.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  // A surface tall enough for the whole corpus. Both pickers scroll, and a
  // row that never got laid out is a row `find.text` cannot see — which would
  // make this comparison about viewport height rather than about the rule.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      (context) => GestureDetector(
        onTap: () => showLineTargetPicker(context, editingRecipeId: 'none'),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText).first, query);
  await tester.pumpAndSettle();
  return _shown(tester);
}

void main() {
  for (final query in _queries) {
    testWidgets('"$query" — both pickers show the same titles', (tester) async {
      final planning = await _planningPickerShows(tester, query);
      final line = await _linePickerShows(tester, query);
      expect(
        line,
        planning,
        reason:
            'the planning picker and the editor\'s "Your recipes" section '
            'disagreed on "$query"',
      );
    });
  }

  testWidgets('and they agree on the band, not just the rows', (tester) async {
    // "aoli" is the owner's probe: no title spells it, so both pickers guess
    // and both say so.
    await _planningPickerShows(tester, 'aoli');
    expect(find.text('DID YOU MEAN'), findsOneWidget);
    expect(find.text('Romesco Aioli'), findsOneWidget);

    await _linePickerShows(tester, 'aoli');
    expect(find.text('DID YOU MEAN'), findsOneWidget);
    expect(find.text('Romesco Aioli'), findsOneWidget);
  });

  testWidgets('every divergence the audit measured is gone', (tester) async {
    // Each of these found nothing in at least one of the two pickers before
    // they shared a rule — so the equality above is not two empty lists
    // agreeing with each other.
    for (final query in [
      'goddess chickpea',
      'chickpea goddess',
      'pasta tomato',
      'jars',
      'almonds',
      'jalapeno',
      'fungi',
    ]) {
      expect(
        await _linePickerShows(tester, query),
        isNotEmpty,
        reason: '"$query" found no title',
      );
    }
  });

  testWidgets('a spelled query is never labelled a guess', (tester) async {
    await _planningPickerShows(tester, 'romesco');
    expect(find.text('DID YOU MEAN'), findsNothing);

    await _linePickerShows(tester, 'romesco');
    expect(find.text('DID YOU MEAN'), findsNothing);
  });
}
