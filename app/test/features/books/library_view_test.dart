import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_collapse_store.dart';
import 'package:ansi/features/books/presentation/library_view.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/shared/ansi_search_field.dart';
import 'package:ansi/shared/dashed_border_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_book_repository.dart';
import '../../helpers/forui_semantics.dart';

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

/// The book card for [name] — the nearest `ClipRRect` above its herb header,
/// which is the card's own clip (the sim helpers scope the same way).
Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ClipRRect)).first;

/// The `＋` on the label row for [section] — scoped by ancestry, because the
/// empty shelf draws one of its own.
Finder _sectionAdd(String section) => find.descendant(
  of: find.ancestor(of: find.text(section), matching: find.byType(Row)).first,
  matching: find.byIcon(FLucideIcons.plus),
);

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

/// The Library as the app hosts it — the theme and the single [FToaster]
/// ABOVE the navigator, as `app.dart` mounts them, so a write that reports its
/// failure after a dialog (through the root overlay, `hostContextOf`) finds
/// the toaster exactly as it does on the phone.
Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: const LibraryView(),
    builder: (context, child) => FTheme(
      data: ansiThemeData(),
      child: FToaster(child: child!),
    ),
  ),
);

List<Override> _repo(List<Book> books) => [
  bookRepositoryProvider.overrideWithValue(_FakeBookRepo(books)),
];

/// [_host], but the Library can be taken out of the tree while one of its
/// prompts is up — the phone's keyboard-shrinks-the-list case, made exact.
Widget _toggleHost(List<Override> overrides, ValueNotifier<bool> show) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, _) =>
              visible ? const LibraryView() : const SizedBox.shrink(),
        ),
        builder: (context, child) => FTheme(
          data: ansiThemeData(),
          child: FToaster(child: child!),
        ),
      ),
    );

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
      GoRoute(
        path: '/recipes/new',
        builder: (_, _) => const FScaffold(child: Text('editor screen')),
      ),
      GoRoute(
        path: '/account',
        builder: (_, _) => const FScaffold(child: Text('account screen')),
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

    expect(find.text('Library'), findsNothing, reason: 'E1: no screen name');
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

  testWidgets('the ＋ is the two doors that make a recipe, and no more', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    // v2 D1's promise, kept verbatim on the row that now carries it (0028 E2).
    await tester.tap(_sectionAdd('Weeknight'));
    await tester.pumpAndSettle();

    expect(find.text('New recipe'), findsOneWidget);
    expect(find.text('Import a recipe'), findsOneWidget);
    // Creation only. Nothing that changes the shape of the library, and
    // nothing that ends a session, has ever belonged behind a plus.
    expect(find.text('New book'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('the header is a field and a link — no menus at all (0028 E1)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    // The screen name is gone: the lit tab says where you are, the rule Week,
    // Cook and Shop already ship.
    expect(find.text('Library'), findsNothing);
    expect(find.byType(AnsiSearchField), findsOneWidget);
    expect(find.byIcon(FLucideIcons.users), findsOneWidget);

    // Nothing in this header opens a menu: one action, and it is the link.
    // `FHeaderAction` only ever appears in a header, so counting it says the
    // header's whole contract without reaching into the body, which still has
    // a `⋯` per book and a `＋` per section.
    expect(find.byType(FHeaderAction), findsOneWidget);
  });

  testWidgets('the household control opens /account (0028 E6)', (tester) async {
    late GoRouter router;
    await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.users));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/account');
    expect(find.text('account screen'), findsOneWidget);
  });

  testWidgets('a rename lands even when the Library is gone under its prompt '
      '(the keyboard-shrinks-the-list case)', (tester) async {
    // The prompt's keyboard shrinks the list on a phone, so the header row
    // that opened it can be unmounted by the time Rename is tapped. Riverpod
    // 3 throws on a `WidgetRef` used after that; the write now goes through
    // the handles captured before the await (`hostContextOf`).
    filterForuiSemanticsAssertions();
    final repo = _RecordingBookRepo(_library);
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await tester.pumpWidget(
      _toggleHost([bookRepositoryProvider.overrideWithValue(repo)], show),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Weeknights');

    show.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(LibraryView), findsNothing);
    expect(find.text('Rename'), findsOneWidget, reason: 'the prompt stays up');

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.renamedTo, 'Weeknights');
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
      // Scoped to the card: the Ingredients shelf carries a `›` of its own.
      expect(
        find.descendant(
          of: _card('Our Cookbook'),
          matching: find.byIcon(FLucideIcons.chevronRight),
        ),
        findsOneWidget,
      );
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

  group('the book ⋯ (D4)', () {
    /// Opens the FIRST book card's overflow: `⋯` #0 is the screen header's,
    /// #1 is this book's, and anything after belongs to its sections.
    Future<void> openBookMenu(WidgetTester tester) async {
      filterForuiSemanticsAssertions();
      await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
      await tester.pumpAndSettle();
    }

    testWidgets('renaming a book writes the new name', (tester) async {
      final repo = _RecordingBookRepo(_library);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openBookMenu(tester);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // The prompt arrives seeded with the current name — renameSection's
      // idiom, one level up.
      expect(find.text('Rename book'), findsOneWidget);
      // `.last`: the dialog's field, in the overlay above the pinned search.
      await tester.enterText(find.byType(TextField).last, 'Weeknights');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(repo.renamedTo, 'Weeknights');
    });

    testWidgets('deleting a book that holds recipes is refused with the '
        'count and a door', (tester) async {
      final repo = _RecordingBookRepo(const [
        ..._library,
        Book(id: 'b2', name: 'Baking'),
      ])..recipesInBook = 42;
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openBookMenu(tester);
      await tester.tap(find.text('Delete book'));
      await tester.pumpAndSettle();

      expect(find.text('Can’t delete “Our Cookbook” yet'), findsOneWidget);
      expect(
        find.textContaining('It holds 42 recipes.'),
        findsOneWidget,
        reason: 'a count is actionable; "failed" is not',
      );
      expect(find.text('Move them to…'), findsOneWidget);
      // A book is a shelf, not a container: nothing was deleted.
      expect(repo.deleted, isNull);
    });

    testWidgets('the refusal’s door moves the contents, unsectioned', (
      tester,
    ) async {
      final repo = _RecordingBookRepo(const [
        ..._library,
        Book(id: 'b2', name: 'Baking'),
      ])..recipesInBook = 42;
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openBookMenu(tester);
      await tester.tap(find.text('Delete book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move them to…'));
      await tester.pumpAndSettle();

      // The sheet offers the OTHER books, never the one being emptied — one
      // row here, plus the card still painted behind the sheet.
      expect(find.text('Our Cookbook'), findsOneWidget);
      expect(find.text('Baking'), findsNWidgets(2));
      await tester.tap(find.text('Baking').last);
      await tester.pumpAndSettle();

      // It says what it will do before it does it.
      expect(
        find.text('42 recipes will move to “Baking”, unsectioned.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();

      expect(repo.moved, (from: 'b1', to: 'b2'));
    });

    testWidgets('the only book is refused separately, and never deleted', (
      tester,
    ) async {
      final repo = _RecordingBookRepo(_library);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openBookMenu(tester);
      await tester.tap(find.text('Delete book'));
      await tester.pumpAndSettle();

      // ensureDefaultBook() would re-mint one on the next launch, and a book
      // that reappears is worse than being told no.
      expect(
        find.text('This is your only book — every recipe needs a shelf.'),
        findsOneWidget,
      );
      expect(find.text('Move them to…'), findsNothing);
      expect(repo.deleted, isNull);
    });

    testWidgets('an empty, non-last book deletes behind a plain confirm', (
      tester,
    ) async {
      final repo = _RecordingBookRepo(const [
        Book(id: 'b1', name: 'Our Cookbook'),
        Book(id: 'b2', name: 'Baking'),
      ]);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openBookMenu(tester);
      await tester.tap(find.text('Delete book'));
      await tester.pumpAndSettle();

      expect(find.text('Delete “Our Cookbook”?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.deleted, 'b1');
    });

    testWidgets('Move down reorders the whole list, not a swap', (
      tester,
    ) async {
      final repo = _RecordingBookRepo(const [
        ..._library,
        Book(id: 'b2', name: 'Baking'),
      ]);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();

      expect(repo.reordered, ['b2', 'b1']);
    });
  });

  testWidgets('an expanded card carries no dashed furniture (0028 E3)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pumpAndSettle();

    // v2 D5 moved the dashed "new section" row inside the card so its noise
    // would scale with what is open. It never asked why the row existed while
    // `New section` sat in the book `⋯` one row above it — so it is gone, and
    // an open card is books, sections and recipes.
    expect(find.textContaining('new section'), findsNothing);
    expect(
      find.descendant(
        of: _card('Our Cookbook'),
        matching: find.byType(DashedAction),
      ),
      findsNothing,
    );
  });

  testWidgets('New section keeps its one door, on the book ⋯ (0028 E3)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();
    expect(find.text('New section'), findsOneWidget);
  });

  testWidgets('an empty shelf offers the two doors in place (D7)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_repo(const [Book(id: 'b1', name: 'Our Cookbook')])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing on this shelf yet'), findsOneWidget);
    expect(find.text('new recipe'), findsOneWidget);
    expect(find.text('import one'), findsOneWidget);
  });

  group('pinned search (D2)', () {
    Future<void> type(WidgetTester tester, String query) async {
      filterForuiSemanticsAssertions();
      await tester.enterText(find.byType(TextField).first, query);
      await tester.pumpAndSettle();
    }

    testWidgets('a live query replaces the tree with filed rows', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_repo(_library)));
      await tester.pumpAndSettle();

      await type(tester, 'chicken');

      // The tree is gone — no herb card, no section label, no dashed row.
      expect(find.text('Our Cookbook'), findsNothing);
      expect(find.text('Weeknight'), findsNothing);
      expect(find.textContaining('new section'), findsNothing);
      // The filing line is the whole reason the list is flat.
      expect(find.text('Chicken Curry'), findsOneWidget);
      expect(find.text('Our Cookbook · Weeknight'), findsOneWidget);
      expect(find.text('1 recipe'), findsOneWidget);
    });

    testWidgets('an unsectioned hit still says where it lives', (tester) async {
      await tester.pumpWidget(_host(_repo(_library)));
      await tester.pumpAndSettle();

      await type(tester, 'toast');

      expect(find.text('Our Cookbook · Unsectioned'), findsOneWidget);
    });

    testWidgets('clearing the field restores the tree, folds intact', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          ..._repo(_library),
          bookCollapseStoreProvider.overrideWithValue(
            _FakeCollapseStore({'b1'}),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chicken Curry'), findsNothing, reason: 'folded');

      // A live query ignores the fold — there is no tree to fold.
      await type(tester, 'chicken');
      expect(find.text('Chicken Curry'), findsOneWidget);

      await type(tester, '');
      expect(find.text('Our Cookbook'), findsOneWidget);
      expect(find.text('Chicken Curry'), findsNothing, reason: 'still folded');
    });

    testWidgets('no hits echoes the query as typed and offers two doors', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_repo(_library)));
      await tester.pumpAndSettle();

      await type(tester, 'romes');

      expect(find.text('Nothing matches “romes”'), findsOneWidget);
      expect(find.text('new recipe called “romes”'), findsOneWidget);
      expect(find.text('import a recipe instead'), findsOneWidget);
      // Honest about the query, not clever about it: there is no single-token
      // fuzzy matcher to back a "did you mean".
      expect(find.textContaining('did you mean'), findsNothing);
    });

    testWidgets('the no-hits door hands the typed query to the editor', (
      tester,
    ) async {
      late GoRouter router;
      await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
      await tester.pumpAndSettle();

      await type(tester, 'romes');
      await tester.tap(find.text('new recipe called “romes”'));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/recipes/new?title=romes');
    });
  });

  testWidgets('a favourited recipe reports a ★; the rest show none (D6)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _repo(const [
          Book(
            id: 'b1',
            name: 'Our Cookbook',
            unsectioned: [
              RecipeSummary(
                id: 'r1',
                title: 'Romesco Aioli',
                servingsBase: 4,
                favorite: true,
              ),
              RecipeSummary(id: 'r2', title: 'Toast', servingsBase: 1),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    // Never a hollow outline on every line — absence renders as absence.
    expect(find.byIcon(FLucideIcons.star), findsOneWidget);
    // …and it reports only: the row keeps a single tap target.
    expect(find.text('Romesco Aioli'), findsOneWidget);
    // Refused on a browsing row (D6): no shelf-life chip, no macro badge.
    expect(find.textContaining('keeps'), findsNothing);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.text('incomplete'), findsNothing);
  });

  testWidgets('the star survives into a search result row', (tester) async {
    await tester.pumpWidget(
      _host(
        _repo(const [
          Book(
            id: 'b1',
            name: 'Our Cookbook',
            unsectioned: [
              RecipeSummary(
                id: 'r1',
                title: 'Romesco Aioli',
                servingsBase: 4,
                favorite: true,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    filterForuiSemanticsAssertions();
    await tester.enterText(find.byType(TextField).first, 'romesco');
    await tester.pumpAndSettle();

    expect(find.byIcon(FLucideIcons.star), findsOneWidget);
    expect(find.text('Our Cookbook · Unsectioned'), findsOneWidget);
  });

  testWidgets('no books at all points at a door on screen (D7·1)', (
    tester,
  ) async {
    final repo = _RecordingBookRepo(const []);
    await tester.pumpWidget(
      _host([bookRepositoryProvider.overrideWithValue(repo)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No books yet'), findsOneWidget);
    expect(
      find.text('A book is a shelf — name it whatever you call it out loud.'),
      findsOneWidget,
    );
    // The old copy pointed at the ＋, which after D1 no longer makes books.
    expect(find.textContaining('with the + above'), findsNothing);
    expect(find.text('new book'), findsOneWidget);
  });

  group('the section ＋ (0028 E2) files from the tap', () {
    testWidgets('a section door carries its book AND its section', (
      tester,
    ) async {
      late GoRouter router;
      await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
      await tester.pumpAndSettle();

      // Scoped to the label's own row: an empty shelf draws a ＋ too.
      await tester.tap(_sectionAdd('Weeknight'));
      await tester.pumpAndSettle();
      expect(find.text('New recipe'), findsOneWidget);
      expect(find.text('Import a recipe'), findsOneWidget);

      await tester.tap(find.text('New recipe'));
      await tester.pumpAndSettle();

      final uri = router.state.uri;
      expect(uri.path, '/recipes/new');
      expect(uri.queryParameters['book'], 'b1');
      expect(uri.queryParameters['section'], 's1');
    });

    testWidgets('the Unsectioned door carries the book and no section', (
      tester,
    ) async {
      late GoRouter router;
      await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
      await tester.pumpAndSettle();

      await tester.tap(_sectionAdd('Unsectioned'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import a recipe'));
      await tester.pumpAndSettle();

      final uri = router.state.uri;
      expect(uri.path, '/import');
      expect(uri.queryParameters['book'], 'b1');
      expect(uri.queryParameters.containsKey('section'), isFalse);
    });
  });

  testWidgets('the dashed affordances use icons, not a raw ＋ glyph', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    // U+FF0B is missing from the bundled fonts and renders as tofu
    // ([mise-forui-icons-not-unicode-glyphs]). The rule outlived the row that
    // prompted it: `new book` is drawn the same way.
    expect(find.textContaining('＋'), findsNothing);
    expect(find.textContaining('new book'), findsOneWidget);
  });

  group('a write that does not land (the ref.write door)', () {
    /// `⋯` #0 is the first book's, #1 its section's — the header has none.
    Future<void> openSectionMenu(WidgetTester tester) async {
      filterForuiSemanticsAssertions();
      await tester.tap(find.byIcon(FLucideIcons.ellipsis).at(1));
      await tester.pumpAndSettle();
    }

    testWidgets('a section delete that fails says so, and Retry re-runs it', (
      tester,
    ) async {
      // The audit's worst fire-and-forget: one menu tap into an unawaited
      // write, where a refusal left the section on screen and the user
      // uninformed.
      final repo = RefusingBookRepository(_library);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openSectionMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['deleteSection']);
      expect(find.text('Couldn’t delete that section.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Retry re-ran the action — a future can only be awaited again.
      expect(repo.calls, ['deleteSection', 'deleteSection']);
      expect(find.text('Couldn’t delete that section.'), findsNothing);
    });

    testWidgets('a book rename that fails names the book’s own act', (
      tester,
    ) async {
      final repo = RefusingBookRepository(_library);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      filterForuiSemanticsAssertions();
      await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Weeknights');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['renameBook']);
      expect(find.text('Couldn’t rename that book.'), findsOneWidget);
    });

    testWidgets('a book delete that fails leaves the book and says why', (
      tester,
    ) async {
      final repo = RefusingBookRepository(const [
        Book(id: 'b1', name: 'Our Cookbook'),
        Book(id: 'b2', name: 'Baking'),
      ]);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      filterForuiSemanticsAssertions();
      await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['deleteBook']);
      expect(find.text('Couldn’t delete “Our Cookbook”.'), findsOneWidget);
      // The refusal is about the write, not about the shelf: the book is still
      // there, and the library still renders.
      expect(find.text('Our Cookbook'), findsWidgets);
    });

    testWidgets('a write that lands says nothing at all', (tester) async {
      final repo = RefusingBookRepository(_library, failures: 0);
      await tester.pumpWidget(
        _host([bookRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pumpAndSettle();

      await openSectionMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['deleteSection']);
      expect(find.textContaining('Couldn’t'), findsNothing);
    });
  });

  testWidgets('a section ＋ closes behind the page it opens', (tester) async {
    late GoRouter router;
    await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
    await tester.pumpAndSettle();

    // The rule the quickfix lane held for the header menus (0022) still holds
    // now that the doors live on the shelf: every item hides itself before it
    // navigates, so backing out never reveals a menu left hanging open.
    await tester.tap(_sectionAdd('Weeknight'));
    await tester.pumpAndSettle();
    expect(find.text('Import a recipe'), findsOneWidget);

    await tester.tap(find.text('Import a recipe'));
    await tester.pumpAndSettle();
    expect(find.text('import screen'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Import a recipe'), findsNothing);
  });
}
