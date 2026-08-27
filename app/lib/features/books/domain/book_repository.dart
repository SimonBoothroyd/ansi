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

  /// Creates a new section at the end of [bookId]; returns its id.
  Future<String> createSection(String bookId, String name);

  /// Renames a section.
  Future<void> renameSection(String sectionId, String name);

  /// Reorders [bookId]'s sections to match [orderedSectionIds].
  Future<void> reorderSections(String bookId, List<String> orderedSectionIds);

  /// Soft-deletes a section; its recipes fall back to the Unsectioned bucket
  /// (their `section_id` is untouched but the library join drops deleted rows).
  Future<void> deleteSection(String sectionId);

  /// Files a recipe into a book and (optionally) a section. A null [sectionId]
  /// clears the section (Unsectioned).
  Future<void> assignRecipe(
    String recipeId, {
    required String bookId,
    String? sectionId,
  });
}
