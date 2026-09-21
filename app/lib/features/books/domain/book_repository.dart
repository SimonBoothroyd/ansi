/// The books persistence contract (pure Dart). ViewModels depend only on this.
///
/// The Library is the whole aggregate: every book, its ordered sections and
/// the recipe summaries filed under each. Mutations are small and targeted.
library;

import 'book.dart';

abstract interface class BookRepository {
  /// Every book with its sections and filed recipes, reacting to local writes.
  /// Books and sections are ordered by `sort_order`; recipes newest-first.
  Stream<List<Book>> watchLibrary();

  /// Ensures a default book exists and adopts any book-less recipes into it.
  /// Idempotent. Returns the default (or first existing) book.
  Future<Book> ensureDefaultBook();

  /// Creates a new book; returns its id.
  Future<String> createBook(String name);

  /// Renames a book.
  Future<void> renameBook(String bookId, String name);

  /// Reorders every book to match [orderedBookIds].
  Future<void> reorderBooks(List<String> orderedBookIds);

  /// How many live recipes are filed in [bookId], read fresh so a delete
  /// refusal names a true count.
  Future<int> countRecipesIn(String bookId);

  /// Re-files every live recipe in [fromBookId] into [toBookId], clearing
  /// `section_id`: sections belong to the book they were named in.
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  });

  /// Soft-deletes a book and its sections; never cascades to recipes.
  ///
  /// Callers must refuse when [countRecipesIn] is non-zero, and when it is the
  /// household's last book: [ensureDefaultBook] would re-mint one.
  Future<void> deleteBook(String bookId);

  /// Creates a new section at the end of [bookId]; returns its id.
  Future<String> createSection(String bookId, String name);

  /// Renames a section.
  Future<void> renameSection(String sectionId, String name);

  /// Reorders [bookId]'s sections to match [orderedSectionIds].
  Future<void> reorderSections(String bookId, List<String> orderedSectionIds);

  /// Soft-deletes a section; its recipes fall back to the Unsectioned bucket
  /// (their `section_id` is untouched but the library join drops deleted rows).
  Future<void> deleteSection(String sectionId);
}
