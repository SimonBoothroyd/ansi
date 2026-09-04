/// Searching the Library by recipe title — PURE DART (invariant 2).
///
/// The whole aggregate is already in memory (the Library screen streams
/// `List<Book>`), so a search is a fold over it rather than SQL. A live query
/// replaces the tree with these flat rows: filing is the subtitle precisely
/// *because* the tree is not on screen — two recipes called "Ragù" in two books
/// are otherwise the same row twice.
///
/// **Titles only in v1, said out loud.** "Recipes with almonds" is a different
/// query shape — a `recipe_line_item → ingredient` join, and after 8.6 a
/// transitive one through `sub_recipe_id` — and a hit on a field the row does
/// not show needs a "matched: almonds" line to explain itself, which is a new
/// row anatomy. It ships as its own slice.
library;

import '../../../core/search/search_query.dart';
import '../../../core/search/search_rank.dart';
import '../../ingredients/domain/normalize.dart' show matchTextForms;
import '../../recipes/domain/recipe.dart' show RecipeSummary;
import 'book.dart';

/// Filing context (book · section) for a recipe — the flat row's subtitle, and
/// the recipe picker's.
typedef Filing = ({String book, String? section});

/// A recipe plus where it is filed.
typedef FiledRecipe = ({RecipeSummary recipe, Filing filing});

/// Where every recipe in [library] is filed, by recipe id.
///
/// One function, two callers: this list and the planning picker's rows. A
/// second copy is how a "book · section" that disagrees with itself starts.
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
/// [searchLibrary] keeps only the rows at the best tier the corpus reached
/// (search & matching v1, D2/D3): a list is all spellings or all guesses,
/// never a guess trailing under a spelling. When the best tier is
/// [SearchTier.typo] the caller labels the list "did you mean".
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
/// Ordering: a hit that is an exact prefix of the title's FIRST word leads
/// ("chicken" → "Chicken Stock" before "Weeknight Chicken Curry"); the rest
/// keep the tree's own order (book order, then section order), so the flat
/// list is never arbitrary.
///
/// An empty (or whitespace-only) query returns nothing — the tree renders
/// instead. The flat list is a search result, never the browse view.
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

/// Whether the query's first token is a prefix of the title's first word —
/// in the token's own spelling or its singular, so "onions" leads with
/// *Onion Soup* the way the tier that found it already folds them together.
bool _startsFirstWord(String title, List<String> tokens) {
  final words = normalizeSearchQuery(title).split(' ');
  if (words.isEmpty) return false;
  return matchTextForms(tokens.first).any(words.first.startsWith);
}
