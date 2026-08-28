import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/features/books/data/book_providers.dart';
import 'package:mise/features/books/domain/book.dart';
import 'package:mise/features/books/domain/book_repository.dart';
import 'package:mise/features/books/presentation/library_view.dart';
import 'package:mise/features/recipes/domain/recipe.dart';

class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this.books);

  final List<Book> books;

  @override
  Stream<List<Book>> watchLibrary() => Stream.value(books);

  @override
  Future<Book> ensureDefaultBook() async => books.first;

  @override
  Future<String> createBook(String name) async => 'new-book';

  @override
  Future<String> createSection(String bookId, String name) async => 'new-sec';

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
    home: FTheme(data: miseThemeData(), child: const LibraryView()),
  ),
);

List<Override> _repo(List<Book> books) => [
  bookRepositoryProvider.overrideWithValue(_FakeBookRepo(books)),
];

void main() {
  testWidgets('LibraryView renders the book, its sections and recipes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('2 recipes'), findsOneWidget);
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

  testWidgets('the + menu offers Sign out', (tester) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();

    expect(find.text('New recipe'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
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
}
