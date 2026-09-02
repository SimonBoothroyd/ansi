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

/// A [FakeBookRepository] whose writes refuse the first [failures] calls.
///
/// The `ref.write` door (`lib/shared/write.dart`) only shows itself when a
/// write throws, so every test of the toast and its Retry needs a repository
/// that fails on purpose — and one that then succeeds, so Retry has something
/// to prove.
class RefusingBookRepository extends FakeBookRepository {
  RefusingBookRepository(super.books, {this.failures = 1});

  /// How many calls throw before one is let through.
  final int failures;

  /// Every write this fake has been asked for, in order — so a test can assert
  /// that Retry really re-ran the action rather than re-showing the toast.
  final calls = <String>[];

  Future<void> _attempt(String name) async {
    calls.add(name);
    if (calls.where((c) => c == name).length <= failures) {
      throw StateError('RLS denied');
    }
  }

  @override
  Future<void> deleteSection(String sectionId) => _attempt('deleteSection');

  @override
  Future<void> renameSection(String sectionId, String name) =>
      _attempt('renameSection');

  @override
  Future<void> reorderSections(String bookId, List<String> orderedSectionIds) =>
      _attempt('reorderSections');

  @override
  Future<void> renameBook(String bookId, String name) => _attempt('renameBook');

  @override
  Future<void> reorderBooks(List<String> orderedBookIds) =>
      _attempt('reorderBooks');

  @override
  Future<void> deleteBook(String bookId) => _attempt('deleteBook');

  @override
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  }) => _attempt('moveBookContents');

  @override
  Future<String> createBook(String name) async {
    await _attempt('createBook');
    return 'new-book';
  }

  @override
  Future<String> createSection(String bookId, String name) async {
    await _attempt('createSection');
    return 'new-sec';
  }
}
