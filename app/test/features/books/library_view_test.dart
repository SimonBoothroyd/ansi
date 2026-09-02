import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_collapse_store.dart';
import 'package:ansi/features/books/presentation/library_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_book_repository.dart';

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo(super.books);
}

/// An in-memory [BookCollapseStore] — the fold without a `SharedPreferences`
/// channel, so a widget test can assert what was persisted.
class _FakeCollapseStore implements BookCollapseStore {
  _FakeCollapseStore([Set<String>? initial]) : folded = {...?initial};

  final Set<String> folded;

  @override
  Future<Set<String>> read() async => {...folded};

  @override
  Future<void> write(String bookId, {required bool collapsed}) async {
    collapsed ? folded.add(bookId) : folded.remove(bookId);
  }
}

/// Records the mutations a menu flow reaches for, so a test can assert on the
/// call rather than on a re-render the fake never produces.
class _RecordingBookRepo extends FakeBookRepository {
  _RecordingBookRepo(super.books);

  List<String>? reordered;
  String? renamedTo;
  String? deleted;
  ({String from, String to})? moved;
  int recipesInBook = 0;

  @override
  Future<void> reorderBooks(List<String> orderedBookIds) async =>
      reordered = orderedBookIds;

  @override
  Future<void> renameBook(String bookId, String name) async => renamedTo = name;

  @override
  Future<void> deleteBook(String bookId) async => deleted = bookId;

  @override
  Future<int> countRecipesIn(String bookId) async => recipesInBook;

  @override
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  }) async => moved = (from: fromBookId, to: toBookId);
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
        ],
      ),
    ],
    unsectioned: [RecipeSummary(id: 'r2', title: 'Toast', servingsBase: 1)],
  ),
];

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const LibraryView()),
  ),
);

List<Override> _repo(List<Book> books) => [
  bookRepositoryProvider.overrideWithValue(_FakeBookRepo(books)),
];

/// The library inside a real router, so a menu item can push and the pushed
/// route can be popped again.
Widget _routedHost(List<Override> overrides, void Function(GoRouter) expose) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LibraryView()),
      GoRoute(
        path: '/import',
        builder: (_, _) => const FScaffold(child: Text('import screen')),
      ),
    ],
  );
  addTearDown(router.dispose);
  expose(router);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

void main() {
  testWidgets('LibraryView renders the book, its sections and recipes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('2 recipes · 1 section'), findsOneWidget);
    expect(find.text('Weeknight'), findsOneWidget);
    expect(find.text('Chicken Curry'), findsOneWidget);
    // The book-less recipe shows under the synthetic Unsectioned bucket.
    expect(find.text('Unsectioned'), findsOneWidget);
    expect(find.text('Toast'), findsOneWidget);
  });

  testWidgets('LibraryView shows an empty state with no books', (tester) async {
    await tester.pumpWidget(_host(_repo(const [])));
    await tester.pump();

    expect(find.text('No books yet'), findsOneWidget);
  });

  testWidgets('the + menu is the two doors that make a recipe, and no more', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();

    expect(find.text('New recipe'), findsOneWidget);
    expect(find.text('Import a recipe'), findsOneWidget);
    // D1: creation only. Navigation and the account action moved to `⋯`.
    expect(find.text('Ingredients'), findsNothing);
    expect(find.text('New book'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('the ⋯ menu changes the shape of the library', (tester) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();

    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('New book'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('New recipe'), findsNothing);
  });

  testWidgets('Reorder books is absent on a one-book library', (tester) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();
    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();

    expect(find.text('Reorder books'), findsNothing);
  });

  testWidgets('Reorder books appears once there is an order', (tester) async {
    await tester.pumpWidget(
      _host(_repo(const [..._library, Book(id: 'b2', name: 'Baking')])),
    );
    await tester.pump();
    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();

    expect(find.text('Reorder books'), findsOneWidget);
  });

  testWidgets('a stub dot rides ⋯ while the vocabulary needs work (D8)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        ..._repo(_library),
        stubCountProvider.overrideWith((ref) => Stream.value(3)),
      ]),
    );
    await tester.pump();

    expect(find.byKey(kStubDotKey), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();
    expect(find.text('3 stubs'), findsOneWidget);
  });

  testWidgets('the dot is absent — not grey — at zero stubs', (tester) async {
    await tester.pumpWidget(
      _host([
        ..._repo(_library),
        stubCountProvider.overrideWith((ref) => Stream.value(0)),
      ]),
    );
    await tester.pump();

    expect(find.byKey(kStubDotKey), findsNothing);
  });

  testWidgets('the reorder sheet moves a book with the sections’ idiom', (
    tester,
  ) async {
    final repo = _RecordingBookRepo(const [
      ..._library,
      Book(id: 'b2', name: 'Baking'),
    ]);
    await tester.pumpWidget(
      _host([bookRepositoryProvider.overrideWithValue(repo)]),
    );
    await tester.pump();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder books'));
    await tester.pumpAndSettle();

    // Move "Baking" up: the second row's up-arrow.
    await tester.tap(find.byIcon(FLucideIcons.arrowUp).last);
    await tester.pumpAndSettle();

    expect(repo.reordered, ['b2', 'b1']);
  });

  group('folding a book (D3)', () {
    testWidgets('the chevron hides the contents and keeps the count', (
      tester,
    ) async {
      final store = _FakeCollapseStore();
      await tester.pumpWidget(
        _host([
          ..._repo(_library),
          bookCollapseStoreProvider.overrideWithValue(store),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chicken Curry'), findsOneWidget);

      await tester.tap(find.byIcon(FLucideIcons.chevronDown));
      await tester.pumpAndSettle();

      expect(find.text('Chicken Curry'), findsNothing);
      expect(find.text('Weeknight'), findsNothing);
      // A fold that hides how much it hides is a fold you stop trusting.
      expect(find.text('2 recipes · 1 section'), findsOneWidget);
      // The dashed row goes with the card it belongs to.
      expect(find.textContaining('new section'), findsNothing);
      expect(store.folded, {'b1'});
    });

    testWidgets('a book folded on this device arrives folded', (tester) async {
      await tester.pumpWidget(
        _host([
          ..._repo(_library),
          bookCollapseStoreProvider.overrideWithValue(
            _FakeCollapseStore({'b1'}),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chicken Curry'), findsNothing);
      expect(find.byIcon(FLucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('a book with nothing in it says so, never "0 recipes"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_repo(const [Book(id: 'b1', name: 'Our Cookbook')])),
      );
      await tester.pumpAndSettle();

      expect(find.text('no recipes yet'), findsOneWidget);
      expect(find.textContaining('0 recipes'), findsNothing);
    });

    testWidgets('an empty book with sections counts only what it has', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _repo(const [
            Book(
              id: 'b1',
              name: 'Baking',
              sections: [
                BookSection(id: 's1', name: 'Bread'),
                BookSection(id: 's2', name: 'Cakes'),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('no recipes yet · 2 sections'), findsOneWidget);
    });
  });

  testWidgets('the add-section affordance uses an icon, not a raw ＋ glyph', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    // U+FF0B is missing from the bundled fonts and renders as tofu.
    expect(find.textContaining('＋'), findsNothing);
    expect(find.textContaining('new section'), findsOneWidget);
  });

  testWidgets('the + menu closes behind the page it opens', (tester) async {
    late GoRouter router;
    await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();
    expect(find.text('Import a recipe'), findsOneWidget);

    await tester.tap(find.text('Import a recipe'));
    await tester.pumpAndSettle();
    expect(find.text('import screen'), findsOneWidget);

    // Backing out of the pushed page must not reveal a menu left hanging open.
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Import a recipe'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });
}
