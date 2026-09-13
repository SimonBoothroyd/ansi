/// The Library at `expanded` — the shelf of book tiles, and what stays put.
///
/// The phone's card list is covered by `library_view_test.dart`; this file is
/// only about what the width changes. A tile is the name, the count line and
/// the titles on the shelf; the doors under the grid are the phone's own; and a
/// search still answers with one ranked column.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/presentation/book_rows.dart';
import 'package:ansi/features/books/presentation/library_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/shared/dashed_border_box.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// A vocabulary that answers only its counts — what the shelf's row reads.
class _CountingVocab extends ReadOnlyIngredientRepo {
  const _CountingVocab();

  @override
  Stream<int> watchVocabularyCount() => Stream.value(319);

  @override
  Stream<int> watchStubCount() => Stream.value(3);
}

const _library = [
  Book(
    id: 'b1',
    name: 'Our Cookbook',
    sections: [
      BookSection(
        id: 's1',
        name: 'Weeknight',
        recipes: [
          RecipeSummary(id: 'r1', title: 'Chicken Curry', servingsBase: 4),
          RecipeSummary(
            id: 'r2',
            title: 'Harissa Chicken',
            servingsBase: 6,
            favorite: true,
          ),
        ],
      ),
    ],
    unsectioned: [
      RecipeSummary(id: 'r3', title: 'Miso Salmon', servingsBase: 2),
      RecipeSummary(id: 'r4', title: 'House Ragù', servingsBase: 6),
    ],
  ),
  Book(id: 'b2', name: 'Preserves'),
];

List<Override> _repo(List<Book> books) => [
  bookRepositoryProvider.overrideWithValue(FakeBookRepository(books)),
  recipeRepositoryProvider.overrideWithValue(FakeRecipeRepo(null)),
  ingredientRepositoryProvider.overrideWithValue(const _CountingVocab()),
];

Widget _host(List<Book> books, [void Function(GoRouter)? expose]) => routedHost(
  initial: '/',
  overrides: _repo(books),
  expose: expose,
  routes: {
    '/': (_, _) => const LibraryView(),
    '/books/:id': (_, state) =>
        FScaffold(child: Text('book ${state.pathParameters['id']}')),
    '/import': (_, _) => const FScaffold(child: Text('import screen')),
    '/recipes/new': (_, _) => const FScaffold(child: Text('editor screen')),
    '/recipes/:id': (_, _) => const FScaffold(child: Text('recipe screen')),
    '/account': (_, _) => const FScaffold(child: Text('account screen')),
    '/ingredients': (_, _) => const FScaffold(child: Text('vocabulary')),
  },
);

/// A desk-sized window: the only thing that turns the card list into a shelf.
void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A phone, for the "nothing moved down here" half.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a tile carries the name, the count line, the first titles and '
      'the count of the rest', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('4 recipes · 1 section'), findsOneWidget);
    // Titles only, in the order the book page lists them, and three of them.
    expect(find.text('Chicken Curry'), findsOneWidget);
    expect(find.text('Harissa Chicken'), findsOneWidget);
    expect(find.text('Miso Salmon'), findsOneWidget);
    expect(find.text('House Ragù'), findsNothing);
    expect(find.text('+ 1 more'), findsOneWidget);
    // The ★ reports here as it does on a row.
    expect(find.byIcon(FLucideIcons.star), findsOneWidget);
    // No stats line, and no section tree: the page a tile opens draws those.
    expect(find.text('serves 4'), findsNothing);
    expect(find.byType(BookSectionBlock), findsNothing);
    expect(find.byType(LibraryRecipeRow), findsNothing);
    // And no fold: a tile is the folded book already.
    expect(find.byIcon(FLucideIcons.chevronDown), findsNothing);
  });

  testWidgets('every tile is the same height, whatever it holds', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    final full = tester.getRect(
      find.ancestor(
        of: find.text('Our Cookbook'),
        matching: find.byType(ClipRRect),
      ),
    );
    final empty = tester.getRect(
      find.ancestor(
        of: find.text('Preserves'),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(full.height, kBookTileHeight);
    expect(empty.height, kBookTileHeight);
    expect(full.width, lessThanOrEqualTo(kBookTileMaxWidth));
    expect(
      empty.top,
      full.top,
      reason: 'four tiles fit this window, so both are on the first row',
    );
  });

  testWidgets('an empty book says so and offers the ＋ that files into it', (
    tester,
  ) async {
    late GoRouter router;
    _wide(tester);
    await tester.pumpWidget(_host(_library, (r) => router = r));
    await tester.pumpAndSettle();

    expect(find.text('no recipes yet'), findsOneWidget);

    await tester.tap(find.text('new recipe'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/recipes/new');
    expect(router.state.uri.queryParameters['book'], 'b2');
  });

  testWidgets('a tile opens the book page', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Our Cookbook'));
    await tester.pumpAndSettle();

    expect(find.text('book b1'), findsOneWidget);
  });

  testWidgets('the ＋ new book door and the Ingredients shelf run full width '
      'under the grid', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    final tile = tester.getRect(
      find.ancestor(
        of: find.text('Our Cookbook'),
        matching: find.byType(ClipRRect),
      ),
    );
    final door = tester.getRect(find.byType(DashedAction).last);
    final vocab = tester.getRect(find.text('INGREDIENTS'));

    expect(door.top, greaterThan(tile.bottom));
    expect(
      door.width,
      greaterThan(kBookTileMaxWidth),
      reason: 'the door closes the whole shelf, not one column of it',
    );
    expect(vocab.top, greaterThan(door.top));
    expect(find.text('319 ingredients · 3 stubs'), findsOneWidget);
  });

  testWidgets('a search answers with one ranked column, each row filed', (
    tester,
  ) async {
    // The framework's own semantics assertion fires on a live field here, as
    // it does on every Forui sheet the suite drives.
    filterForuiSemanticsAssertions();
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'chicken');
    await tester.pumpAndSettle();

    expect(find.text('2 recipes'), findsOneWidget);
    expect(find.text('Our Cookbook · Weeknight'), findsNWidgets(2));
    expect(find.byType(LibraryRecipeRow), findsNWidgets(2));
    // One column: the tiles are gone, and both rows start at the same edge.
    expect(find.text('+ 1 more'), findsNothing);
    final rows = tester.widgetList<LibraryRecipeRow>(
      find.byType(LibraryRecipeRow),
    );
    expect(rows.length, 2);
    expect(
      tester.getRect(find.byType(LibraryRecipeRow).at(0)).left,
      tester.getRect(find.byType(LibraryRecipeRow).at(1)).left,
    );
  });

  testWidgets('on a phone the Library is the card list, untouched', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    expect(find.byType(BookSectionBlock), findsWidgets);
    expect(find.byType(LibraryRecipeRow), findsWidgets);
    expect(find.text('+ 1 more'), findsNothing);
    expect(find.byIcon(FLucideIcons.chevronDown), findsWidgets);
  });
}
