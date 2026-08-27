/// Books domain entities — the read aggregate the Library screen renders.
///
/// PURE DART (invariant 2): no `package:flutter`. A [Book] holds ordered
/// [BookSection]s (user-named groupings like "Weeknight"), each holding the
/// [RecipeSummary]s filed under it, plus a synthetic [Book.unsectioned] bucket
/// for recipes with no section. Sections are their own database rows carrying a
/// `sort_order`; the repository assembles them into this aggregate.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../recipes/domain/recipe.dart' show RecipeSummary;

part 'book.freezed.dart';

@freezed
abstract class Book with _$Book {
  const factory Book({
    required String id,
    required String name,

    /// Ordered, user-named sections. Empty sections are kept (they still show
    /// as a labelled, recipe-less row).
    @Default(<BookSection>[]) List<BookSection> sections,

    /// Recipes in this book with no `section_id` (or a deleted section).
    /// Rendered under an "Unsectioned" label; not a real database row.
    @Default(<RecipeSummary>[]) List<RecipeSummary> unsectioned,
  }) = _Book;
}

/// A user-named section within a book. [name] is always set (unlike an
/// ingredient group, a section exists to carry a label the user typed).
@freezed
abstract class BookSection with _$BookSection {
  const factory BookSection({
    required String id,
    required String name,
    @Default(<RecipeSummary>[]) List<RecipeSummary> recipes,
  }) = _BookSection;
}
