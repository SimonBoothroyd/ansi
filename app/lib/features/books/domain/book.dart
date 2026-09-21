/// Books domain entities: the read aggregate the Library renders (pure Dart).
///
/// A [Book] holds ordered [BookSection]s, each holding the [RecipeSummary]s
/// filed under it, plus a synthetic [Book.unsectioned] bucket.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../recipes/domain/recipe.dart' show RecipeSummary;

part 'book.freezed.dart';

@freezed
abstract class Book with _$Book {
  const factory Book({
    required String id,
    required String name,

    /// Ordered, user-named sections. Empty sections are kept.
    @Default(<BookSection>[]) List<BookSection> sections,

    /// Recipes in this book with no `section_id` (or a deleted section). Not
    /// a database row.
    @Default(<RecipeSummary>[]) List<RecipeSummary> unsectioned,
  }) = _Book;
}

/// A user-named section within a book. [name] is always set.
@freezed
abstract class BookSection with _$BookSection {
  const factory BookSection({
    required String id,
    required String name,
    @Default(<RecipeSummary>[]) List<RecipeSummary> recipes,
  }) = _BookSection;
}
