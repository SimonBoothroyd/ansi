/// The book page — `/books/:id`, in both layouts.
///
/// On a phone it is the Library card's tree without the card: the name, the
/// count line, the sections in order with Unsectioned last, and the same
/// controls, which are the same widgets (`book_rows.dart`). At `expanded` the
/// sections move into an index beside the recipes, and the index scrolls that
/// one list rather than filtering it.
library;

import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/presentation/book_page_view.dart';
import 'package:ansi/features/books/presentation/book_rows.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_book_repository.dart';
import '../../helpers/pump_app.dart';

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
        recipes: [
          RecipeSummary(id: 'r3', title: 'Roast Chicken', servingsBase: 8),
        ],
      ),
    ],
    unsectioned: [
      RecipeSummary(id: 'r4', title: 'Miso Salmon', servingsBase: 10),
    ],
  ),
  Book(id: 'b2', name: 'Baking'),
];

/// A book with enough in it to scroll past one screenful at `expanded`.
List<Book> _tall() => [
  Book(
    id: 'b1',
    name: 'Everyday',
    sections: [
      for (final (i, name) in ['Pasta', 'Traybakes', 'Curries'].indexed)
        BookSection(
          id: 's$i',
          name: name,
          recipes: [
            for (var n = 0; n < 5; n++)
              RecipeSummary(
                id: 'r$i$n',
                title: '$name dish $n',
                servingsBase: 4,
              ),
          ],
        ),
    ],
    unsectioned: const [
      RecipeSummary(id: 'ru', title: 'Chicken Stock', servingsBase: 8),
    ],
  ),
];

List<Override> _repo(List<Book> books) => [
  bookRepositoryProvider.overrideWithValue(FakeBookRepository(books)),
  recipeRepositoryProvider.overrideWithValue(FakeRecipeRepo(null)),
];

/// The page under a real router, deep-linked straight at a book: the arrival a
/// pasted URL makes, and the one a tile's push makes once the Library is behind
/// it.
Widget _host(
  List<Book> books, {
  String initial = '/books/b1',
  void Function(GoRouter)? expose,
}) => routedHost(
  initial: initial,
  overrides: _repo(books),
  expose: expose,
  routes: {
    '/': (_, _) => const FScaffold(child: Text('library screen')),
    '/books/:id': (_, state) =>
        BookPageView(bookId: state.pathParameters['id']!),
    '/import': (_, _) => const FScaffold(child: Text('import screen')),
    '/recipes/new': (_, _) => const FScaffold(child: Text('editor screen')),
    '/recipes/:id': (_, _) => const FScaffold(child: Text('recipe screen')),
  },
);

/// Widens the window past `lg` — the only thing that turns the page into two
/// panes.
void _wide(WidgetTester tester, {double height = 900}) {
  tester.view.physicalSize = Size(1440, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The index pane — the first list in the tree, which is the one the Row draws
/// on the left.
Finder _index() => find.byType(ListView).first;

/// A section's own label, inside the block it heads, as opposed to its name in
/// the index.
Finder _label(String section) => find.descendant(
  of: find.byType(BookSectionBlock),
  matching: find.text(section),
);

void main() {
  group('the page, on a phone', () {
    testWidgets('names the book, counts it, and lists every section with '
        'Unsectioned last', (tester) async {
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      expect(find.text('Our Cookbook'), findsOneWidget);
      expect(find.text('4 recipes · 2 sections'), findsOneWidget);
      expect(find.text('Weeknight'), findsOneWidget);
      expect(find.text('Slow Sundays'), findsOneWidget);
      expect(find.text('Unsectioned'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Unsectioned')).dy,
        greaterThan(tester.getTopLeft(find.text('Slow Sundays')).dy),
        reason: 'the synthetic bucket files after every named section',
      );
    });

    testWidgets('draws the Library row whole — the title, the stats line, the '
        '★ that only reports, and the row’s own ⋯', (tester) async {
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      expect(find.text('Chicken Curry'), findsOneWidget);
      expect(find.text('serves 4'), findsOneWidget);
      expect(find.text('Miso Salmon'), findsOneWidget);
      expect(find.byType(LibraryRecipeRow), findsNWidgets(4));
      expect(find.byIcon(FLucideIcons.star), findsOneWidget);
    });

    testWidgets('a recipe row opens the recipe', (tester) async {
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      await tester.tap(find.text('Roast Chicken'));
      await tester.pumpAndSettle();

      expect(find.text('recipe screen'), findsOneWidget);
    });

    testWidgets('every section keeps its ＋ and its ⋯, and Unsectioned keeps '
        'the ＋ alone', (tester) async {
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      // Three labels, three `＋`; the two named sections carry a `⋯` each and
      // the bucket carries none — the header bar's `⋯` is the book's own.
      expect(find.byType(SectionAddMenu), findsNWidgets(3));
      expect(find.byType(SectionMenu), findsNWidgets(2));
    });

    testWidgets('the header ⋯ is the book’s own menu', (tester) async {
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      expect(find.byType(BookMenu), findsOneWidget);
      await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('New section'), findsOneWidget);
      expect(find.text('Delete book'), findsOneWidget);
    });

    testWidgets('an empty book offers the two doors in place', (tester) async {
      await tester.pumpWidget(_host(_library, initial: '/books/b2'));
      await tester.pump();

      expect(find.text('no recipes yet'), findsOneWidget);
      expect(find.byType(EmptyShelf), findsOneWidget);
    });

    testWidgets('back returns to the Library', (tester) async {
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      await tester.tap(find.byType(FHeaderAction).first);
      await tester.pumpAndSettle();

      expect(find.text('library screen'), findsOneWidget);
    });

    testWidgets('a book that is not there says so instead of drawing a page '
        'about nothing', (tester) async {
      await tester.pumpWidget(_host(_library, initial: '/books/gone'));
      await tester.pump();

      expect(find.text('Book not found'), findsOneWidget);
      expect(find.byType(BookSectionBlock), findsNothing);
    });
  });

  group('the page, at expanded', () {
    testWidgets('puts the sections in an index beside the recipes, each with '
        'what it holds', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      // Every section is named twice over: once in the index, once on the block
      // it heads.
      expect(find.text('Weeknight'), findsNWidgets(2));
      expect(find.text('Unsectioned'), findsNWidgets(2));
      expect(
        find.descendant(of: _index(), matching: find.text('Slow Sundays')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _index(), matching: find.text('2')),
        findsOneWidget,
        reason: 'Weeknight holds two recipes and the index says so',
      );
      // The rows are the phone's rows, not a wider variant of them.
      expect(find.byType(LibraryRecipeRow), findsNWidgets(4));
    });

    testWidgets('the recipes hold the measure however wide the window is', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(_host(_library));
      await tester.pump();

      final row = tester.getRect(find.byType(LibraryRecipeRow).first);
      expect(row.width, lessThanOrEqualTo(640));
      expect(
        row.left,
        greaterThanOrEqualTo(kSectionIndexWidth),
        reason: 'the recipes sit beside the index, not under it',
      );
    });

    testWidgets('tapping a name in the index scrolls the one list to it, and '
        'lights it', (tester) async {
      _wide(tester, height: 500);
      await tester.pumpWidget(_host(_tall()));
      await tester.pump();

      // The first section is what the list opens on; the third is far enough
      // down that it has not been built at all.
      expect(_label('Pasta'), findsOneWidget);
      expect(_label('Curries'), findsNothing);

      await tester.tap(
        find.descendant(of: _index(), matching: find.text('Curries')),
      );
      await tester.pumpAndSettle();

      expect(_label('Curries'), findsOneWidget);
      expect(
        tester.getTopLeft(_label('Curries')).dy,
        lessThan(tester.getTopLeft(find.byType(LibraryRecipeRow).first).dy + 8),
        reason: 'the list scrolled that section to the top of itself',
      );
      final lit = tester.widget<Text>(
        find.descendant(of: _index(), matching: find.text('Curries')),
      );
      expect(
        lit.style?.color,
        AnsiColors.herbDeep,
        reason: 'the index lights whichever section the list is showing',
      );

      // Scrolled, not filtered: the sections above are still in the list, and
      // dragging back to the top finds the first one where it always was.
      await tester.drag(
        find.byType(LibraryRecipeRow).first,
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(_label('Pasta'), findsOneWidget);
    });
  });
}
