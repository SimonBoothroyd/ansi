/// Searching the Library by recipe title (pure Dart).
///
/// The aggregate is already in memory, so a search is a fold over it. Results
/// are flat rows with the filing as subtitle. Titles only.
library;

import '../../../core/search/search_query.dart';
import '../../../core/search/search_rank.dart';
import '../../ingredients/domain/normalize.dart' show matchTextForms;
import '../../recipes/domain/recipe.dart' show RecipeSummary;
import 'book.dart';

/// Filing context (book · section) for a recipe: the flat row's subtitle.
typedef Filing = ({String book, String? section});

/// A recipe plus where it is filed.
typedef FiledRecipe = ({RecipeSummary recipe, Filing filing});

/// Where every recipe in [library] is filed, by recipe id. Shared with the
/// planning picker's rows.
Map<String, Filing> filingByRecipe(List<Book> library) {
  final map = <String, Filing>{};
  for (final b in library) {
    for (final s in b.sections) {
      for (final r in s.recipes) {
        map[r.id] = (book: b.name, section: s.name);
      }
    }
    for (final r in b.unsectioned) {
      map[r.id] = (book: b.name, section: null);
    }
  }
  return map;
}

/// Whether a Library search is showing guesses rather than spellings.
///
/// [searchLibrary] keeps only the rows at the best tier reached. When that
/// tier is [SearchTier.typo] the caller labels the list "did you mean".
bool librarySearchIsGuess(List<Book> books, String query) =>
    _bestTier(books, query) == SearchTier.typo;

SearchTier? _bestTier(List<Book> books, String query) => bestTier([
  for (final b in books) ...[
    for (final s in b.sections)
      for (final r in s.recipes) recipeTitleHit(r.title, query),
    for (final r in b.unsectioned) recipeTitleHit(r.title, query),
  ],
]);

/// Every recipe in [books] whose title answers [query], flattened, each
/// carrying its filing.
///
/// A hit that prefixes the title's first word leads; the rest keep the tree's
/// order. A blank query returns nothing.
List<FiledRecipe> searchLibrary(List<Book> books, String query) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return const [];

  final tier = _bestTier(books, query);
  if (tier == null) return const [];
  final filing = filingByRecipe(books);
  final leading = <FiledRecipe>[];
  final rest = <FiledRecipe>[];

  for (final book in books) {
    final inTreeOrder = [
      for (final section in book.sections) ...section.recipes,
      ...book.unsectioned,
    ];
    for (final recipe in inTreeOrder) {
      final hit = recipeTitleHit(recipe.title, query);
      if (hit == null || hit.tier != tier) continue;
      final row = (
        recipe: recipe,
        filing: filing[recipe.id] ?? (book: book.name, section: null),
      );
      (_startsFirstWord(recipe.title, tokens) ? leading : rest).add(row);
    }
  }
  return [...leading, ...rest];
}

/// Whether the query's first token, as typed or singularised, is a prefix of
/// the title's first word.
bool _startsFirstWord(String title, List<String> tokens) {
  final words = normalizeSearchQuery(title).split(' ');
  if (words.isEmpty) return false;
  return matchTextForms(tokens.first).any(words.first.startsWith);
}
