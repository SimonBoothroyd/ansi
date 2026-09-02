/// A no-op [BookRepository] for widget/state tests that need the Library
/// aggregate but not its mutations.
///
/// Five test files were each hand-rolling the whole interface, so every method
/// added to it cost five identical stubs. Subclass this and override only what
/// the test actually exercises; the constructor's books are what the library
/// stream emits.
library;

import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_repository.dart';

class FakeBookRepository implements BookRepository {
  const FakeBookRepository([this.books = const <Book>[]]);

  final List<Book> books;

  @override
  Stream<List<Book>> watchLibrary() => Stream.value(books);

  @override
  Future<Book> ensureDefaultBook() async =>
      books.isEmpty ? const Book(id: 'b1', name: 'Our Cookbook') : books.first;

  @override
  Future<String> createBook(String name) async => 'new-book';

  @override
  Future<void> renameBook(String bookId, String name) async {}

  @override
  Future<void> reorderBooks(List<String> orderedBookIds) async {}

  @override
  Future<int> countRecipesIn(String bookId) async => 0;

  @override
  Future<int> countBooks() async => books.length;

  @override
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  }) async {}

  @override
  Future<void> deleteBook(String bookId) async {}

  @override
  Future<String> createSection(String bookId, String name) async => 'new-sec';

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
