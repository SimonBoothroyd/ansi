/// The Library at `expanded` — the ledger, its A–Z margin, and what stays put.
///
/// The phone's card list is covered by `library_view_test.dart`; this file is
/// only about what the width changes. A book is a heading row with its counts
/// set in a column, its first lines under it and one remainder row; the margin
/// lights the letters that have books and scrolls to them; a search still
/// answers with one ranked column; and below the band nothing moved.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_collapse_store.dart';
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

/// The fold without a `SharedPreferences` channel, so the ledger's chevrons
/// answer the same way on every machine.
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
      BookSection(
        id: 's2',
        name: 'Slow Sundays',
        recipes: [RecipeSummary(id: 'r5', title: 'Porchetta', servingsBase: 8)],
      ),
    ],
    unsectioned: [
      RecipeSummary(id: 'r3', title: 'Miso Salmon', servingsBase: 2),
      RecipeSummary(id: 'r4', title: 'House Ragù', servingsBase: 6),
    ],
  ),
  Book(id: 'b2', name: 'Preserves'),
];

/// Enough books, with enough distinct initials, that the margin has work to do
/// and the ledger is longer than its window.
List<Book> get _manyBooks => [
  for (final name in [
    'Our Cookbook',
    'Baking',
    '30 in 30',
    'Elly’s Plate',
    'Mississippi Vegan',
    'Sunday Roasts',
    'Takeaway at Home',
    'The Grill',
    'Weeknights',
    'Zero Waste',
  ])
    Book(
      id: name,
      name: name,
      unsectioned: [
        for (var i = 1; i <= 4; i++)
          RecipeSummary(id: '$name-$i', title: '$name $i', servingsBase: 2),
      ],
    ),
];

List<Override> _repo(List<Book> books, {Set<String>? folded}) => [
  bookRepositoryProvider.overrideWithValue(FakeBookRepository(books)),
  recipeRepositoryProvider.overrideWithValue(FakeRecipeRepo(null)),
  ingredientRepositoryProvider.overrideWithValue(const _CountingVocab()),
  bookCollapseStoreProvider.overrideWithValue(_FakeCollapseStore(folded)),
];

Widget _host(
  List<Book> books, {
  void Function(GoRouter)? expose,
  Set<String>? folded,
}) => routedHost(
  initial: '/',
  overrides: _repo(books, folded: folded),
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

/// A desk-sized window: the only thing that turns the card list into a ledger.
void _wide(WidgetTester tester, {double height = 1000}) {
  tester.view.physicalSize = Size(1440, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A phone, for the "nothing moved down here" half.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The letter [letter] in the A–Z margin.
Finder _letter(String letter) => find.byWidgetPredicate(
  (w) => w is LibraryIndexLetter && w.letter == letter,
);

bool _isLit(WidgetTester tester, String letter) =>
    tester.widget<LibraryIndexLetter>(_letter(letter)).lit;

/// Where the ledger's own list has been scrolled to — asked of the list
/// itself, since the field at the head of the column is a scrollable too.
double _offset(WidgetTester tester) => tester
    .widget<Scrollable>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .controller!
    .offset;

void main() {
  testWidgets('a heading row carries the book and its counts, and the lines '
      'under it carry their stats', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    // The column heads say what the right-hand column holds.
    expect(find.text('BOOKS · 2'), findsOneWidget);
    expect(find.text('COUNTS · STATS'), findsOneWidget);

    // One heading row per book, each with the phone's own count line.
    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('5 recipes · 2 sections'), findsOneWidget);
    expect(find.text('Preserves'), findsOneWidget);
    expect(find.text('no recipes yet'), findsOneWidget);

    // Three lines, in the book page's own order, each the Library's row with
    // its stats set in the counts column rather than dropped.
    expect(find.byType(LibraryRecipeRow), findsNWidgets(3));
    expect(find.text('Chicken Curry'), findsOneWidget);
    expect(find.text('Harissa Chicken'), findsOneWidget);
    expect(find.text('Porchetta'), findsOneWidget);
    expect(find.text('Miso Salmon'), findsNothing);
    expect(find.text('serves 4'), findsOneWidget);
    expect(find.text('serves 8'), findsOneWidget);
    // The ★ reports here as it does on the phone's row.
    expect(find.byIcon(FLucideIcons.star), findsOneWidget);
    // Sections are counts, not blocks: the tree stays on the phone and on the
    // book page.
    expect(find.byType(BookSectionBlock), findsNothing);
    expect(find.text('Weeknight'), findsNothing);
  });

  testWidgets('a book’s counts and a recipe’s stats end on one edge — it is a '
      'column, not a row of loose numbers', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    // The leader is the row's only flexible cell. Give the name a flex of its
    // own and it halves the free space with the leader, leaving every count
    // short of the column it is ruled to — which is the whole ledger.
    final counts = tester.getRect(find.text('5 recipes · 2 sections'));
    final stats = tester.getRect(find.text('serves 4'));
    expect(counts.right, stats.right);
  });

  testWidgets('the remainder row counts what the lines did not show, and the '
      'sections still holding it', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    // Five recipes, three drawn: two left, and both of them unsectioned —
    // `Slow Sundays` gave up its only recipe to the third line.
    expect(find.text('2 more'), findsOneWidget);

    // The row is the door to the book's own page, where the sections are named.
    await tester.tap(find.text('2 more'));
    await tester.pumpAndSettle();
    expect(find.text('book b1'), findsOneWidget);
  });

  testWidgets('a remainder still inside a section says which', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _host(const [
        Book(
          id: 'b1',
          name: 'Our Cookbook',
          sections: [
            BookSection(
              id: 's1',
              name: 'Weeknight',
              recipes: [
                RecipeSummary(id: 'r1', title: 'One', servingsBase: 2),
                RecipeSummary(id: 'r2', title: 'Two', servingsBase: 2),
                RecipeSummary(id: 'r3', title: 'Three', servingsBase: 2),
                RecipeSummary(id: 'r4', title: 'Four', servingsBase: 2),
              ],
            ),
            BookSection(
              id: 's2',
              name: 'Sundays',
              recipes: [
                RecipeSummary(id: 'r5', title: 'Five', servingsBase: 2),
              ],
            ),
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 more, in 2 sections'), findsOneWidget);
  });

  testWidgets('the fold is the phone’s own: a folded book is its heading row '
      'alone, and the chevron opens it again', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library, folded: {'b1'}));
    await tester.pumpAndSettle();

    // Arrived folded: the count line reads the same shut as open, and there is
    // nothing under it.
    expect(find.text('5 recipes · 2 sections'), findsOneWidget);
    expect(find.byType(LibraryRecipeRow), findsNothing);
    expect(find.text('2 more'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.chevronRight).first);
    await tester.pumpAndSettle();
    expect(find.byType(LibraryRecipeRow), findsNWidgets(3));
  });

  testWidgets('the heading row’s name opens the book page', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Our Cookbook'));
    await tester.pumpAndSettle();

    expect(find.text('book b1'), findsOneWidget);
  });

  testWidgets('the A–Z margin lights the letters that have books, and only '
      'those', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_manyBooks));
    await tester.pumpAndSettle();

    // Every letter is drawn — the gaps are the point.
    expect(find.byType(LibraryIndexLetter), findsNWidgets(27));
    // `30 in 30` files under #; the rest under their own first letter.
    for (final letter in ['#', 'B', 'E', 'M', 'O', 'S', 'T', 'W', 'Z']) {
      expect(_isLit(tester, letter), isTrue, reason: '$letter has a book');
    }
    for (final letter in ['A', 'C', 'D', 'F', 'Q', 'X']) {
      expect(_isLit(tester, letter), isFalse, reason: '$letter has none');
    }
  });

  testWidgets('a letter scrolls the ledger to its book', (tester) async {
    // Ten books of four recipes is longer than any window, which is the only
    // state in which scrolling means anything.
    _wide(tester);
    await tester.pumpWidget(_host(_manyBooks));
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(ListView));
    expect(_offset(tester), 0);

    await tester.tap(_letter('M'));
    await tester.pumpAndSettle();

    expect(_offset(tester), greaterThan(0));
    // The book it indexes is now at the head of the column — the index is a
    // jump, so the ledger stays in the household's own order under it.
    final book = tester.getRect(find.text('Mississippi Vegan'));
    expect(book.top - list.top, inInclusiveRange(0, 40));
  });

  testWidgets('an unlit letter is not a door', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_manyBooks));
    await tester.pumpAndSettle();

    await tester.tap(_letter('Q'));
    await tester.pumpAndSettle();

    expect(_offset(tester), 0);
  });

  testWidgets('an empty book says so and offers the ＋ that files into it', (
    tester,
  ) async {
    late GoRouter router;
    _wide(tester);
    await tester.pumpWidget(_host(_library, expose: (r) => router = r));
    await tester.pumpAndSettle();

    expect(find.text('no recipes yet'), findsOneWidget);
    expect(find.text('Nothing on this shelf yet'), findsOneWidget);

    await tester.tap(find.text('new recipe'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/recipes/new');
    expect(router.state.uri.queryParameters['book'], 'b2');
  });

  testWidgets('the head strip is a field measured to what is typed into it, '
      'with the quiet door that makes a book', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    // No header bar at all up there, so no household door either: Account is
    // the sidebar's footer item.
    expect(find.byType(FHeaderAction), findsNothing);
    expect(find.byIcon(FLucideIcons.users), findsNothing);

    final field = tester.getRect(find.byType(EditableText).first);
    expect(field.width, lessThanOrEqualTo(kLedgerFieldWidth));

    // The door is a word, not the phone's dashed slab (the empty book below
    // still draws its own two, which is why this asks about THIS door).
    expect(find.text('new book'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('new book'),
        matching: find.byType(DashedAction),
      ),
      findsNothing,
    );
  });

  testWidgets('the ledger and its margin are capped and centred in the pane', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_host(_library));
    await tester.pumpAndSettle();

    final heads = tester.getRect(find.text('BOOKS · 2'));
    final margin = tester.getRect(find.byType(LibraryIndexLetter).first);
    expect(
      margin.left - heads.left,
      lessThanOrEqualTo(kLedgerWidth + kAzIndexGap),
    );
    expect(
      heads.left,
      greaterThan(60),
      reason: 'the column is centred in the pane, not pinned to its edge',
    );
    // The Ingredients shelf closes the ledger, under the books.
    expect(find.text('INGREDIENTS'), findsOneWidget);
    expect(find.text('319 ingredients · 3 stubs'), findsOneWidget);
    expect(
      tester.getRect(find.text('INGREDIENTS')).top,
      greaterThan(tester.getRect(find.text('Preserves')).top),
    );
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
    // The books are gone, and so is the margin that indexes them.
    expect(find.text('BOOKS · 2'), findsNothing);
    expect(find.byType(LibraryIndexLetter), findsNothing);
    // One column: both rows start at the same edge.
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
    expect(find.text('Weeknight'), findsOneWidget);
    // Nothing of the ledger reaches down here.
    expect(find.byType(LibraryIndexLetter), findsNothing);
    expect(find.text('BOOKS · 2'), findsNothing);
    expect(find.text('2 more'), findsNothing);
    // The phone's own header and its dashed doors are where they were.
    expect(find.byIcon(FLucideIcons.users), findsOneWidget);
    expect(find.byType(DashedAction), findsWidgets);
  });
}
