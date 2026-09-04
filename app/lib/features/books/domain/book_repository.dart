/// The books persistence contract — PURE DART (invariant 2). The data layer
/// implements it over PowerSync's local SQLite; ViewModels depend only on this.
///
/// The Library is the whole aggregate: every book, its ordered sections, and
/// the recipe summaries filed under each (plus each book's unsectioned ones).
/// Mutations are small and targeted (create/rename/reorder a section, file a
/// recipe) — unlike recipes, there is no whole-aggregate replace-on-save.
library;

import 'book.dart';

abstract interface class BookRepository {
  /// Every book with its sections and filed recipes, reacting to local writes.
  /// Books and sections are ordered by `sort_order`; recipes newest-first.
  Stream<List<Book>> watchLibrary();

  /// Ensures a default book exists (creating "Our Cookbook" if the household
  /// has none) and adopts any book-less recipes into it. Idempotent — a no-op
  /// once a book exists. Returns the default (or first existing) book.
  Future<Book> ensureDefaultBook();

  /// Creates a new book; returns its id.
  Future<String> createBook(String name);

  /// Renames a book.
  Future<void> renameBook(String bookId, String name);

  /// Reorders every book to match [orderedBookIds] — the section-reorder
  /// method without the parent scope.
  Future<void> reorderBooks(List<String> orderedBookIds);

  /// How many live recipes are filed in [bookId].
  ///
  /// Read at the moment of the tap so the delete refusal names a count that is
  /// true *now* (the `usedIn` precedent), never the cached Library tree.
  Future<int> countRecipesIn(String bookId);

  /// Re-files every live recipe in [fromBookId] into [toBookId], clearing their
  /// `section_id`: sections belong to the book they were named in, so a moved
  /// recipe lands unsectioned rather than pointing at a shelf it left.
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  });

  /// Soft-deletes a book and its sections.
  ///
  /// A book is a shelf, not a container: this never cascades to recipes.
  /// Callers must refuse the delete when [countRecipesIn] is non-zero, and when
  /// it is the household's last book — `ensureDefaultBook` would re-mint one on
  /// the next launch, and a book that reappears is worse than a refusal.
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
