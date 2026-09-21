/// The one rule for matching typed text against a name. Pure Dart.
///
/// [searchRank] has three tiers, first hit wins: exact, word-prefix, then a
/// guarded typo tier that runs only when the first two find nothing. It is a
/// deterministic character comparison over the household's synced vocabulary
/// and never resolves anything (ADR-0004). See
/// `docs/design-docs/search-and-matching.md`.
library;

// The ranking needs the phrase normalizer's tokenizer, which lives beside the
// vocabulary it writes `match_text` for.
import '../../features/ingredients/domain/normalize.dart'
    show matchTextForms, normalizeMatchText;
import 'search_query.dart';

/// The tier a hit came from. Declaration order IS the ranking: a lower tier
/// always outranks a higher one.
enum SearchTier {
  /// The query is the name.
  exact,

  /// Every token starts a word of the name.
  prefix,

  /// The query was guessed at. Runs only when [exact] and [prefix] are empty.
  typo,
}

/// A hit: which tier produced it, and how well it scored inside that tier.
/// Compare tiers first, scores only within a tier.
typedef SearchHit = ({SearchTier tier, double score});

/// Shortest token that may be guessed at when the query is one word.
///
/// Four finds `almnd` → Almonds at the price of real words landing on the
/// wrong food (`beef` → Beets), tolerable only under a "did you mean" header.
const int kMinFuzzTokenLenSingle = 4;

/// Shortest token that may be guessed at in a query of two or more words,
/// where a correctly spelled neighbour corroborates. A shorter token must be
/// an exact word prefix.
const int kMinFuzzTokenLenMulti = 3;

/// The per-token similarity floor a guess must clear. Guards vocabularies
/// with much longer names, where the edit budget alone is too loose.
const double kTypoTokenFloor = 0.75;

/// How many edits a token of a given length may be off: none under 3
/// characters, one up to 7, two from 8. A transposition is one edit
/// ([osaDistance]).
int typoEditBudget(int tokenLength) {
  if (tokenLength >= 8) return 2;
  if (tokenLength >= 3) return 1;
  return 0;
}

/// Ranks [query] against one row's [surfaces], or null when it does not hit.
///
/// [surfaces] are normalized phrases: the row's `match_text`, each live
/// alias's, and the character-normalized raw name (see [nameSurfaces]).
SearchHit? searchRank(String query, List<String> surfaces) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return null;
  final live = [
    for (final surface in surfaces)
      if (surface.trim().isNotEmpty) surface.trim(),
  ];
  if (live.isEmpty) return null;

  // Tier 0. The query as typed OR singularized, against a whole surface.
  final normalized = tokens.join(' ');
  final singular = [for (final t in tokens) matchTextForms(t).last].join(' ');
  for (final surface in live) {
    if (surface == normalized || surface == singular) {
      return (tier: SearchTier.exact, score: 1);
    }
  }

  final words = <String>[
    for (final surface in live)
      for (final word in surface.split(' '))
        if (word.isNotEmpty) word,
  ];

  // Tier 1. Every token word-prefixes some word, raw or singular. The score
  // is how much of the matched words the query spelled, so `onion` ranks
  // Onion above `onion powder`.
  var spelled = 0;
  var matched = 0;
  var everyTokenPrefixes = true;
  for (final token in tokens) {
    final forms = matchTextForms(token);
    var shortest = -1;
    for (final word in words) {
      if (!forms.any(word.startsWith)) continue;
      if (shortest < 0 || word.length < shortest) shortest = word.length;
    }
    if (shortest < 0) {
      everyTokenPrefixes = false;
      break;
    }
    spelled += token.length;
    matched += shortest;
  }
  if (everyTokenPrefixes) {
    final score = matched == 0 ? 1.0 : (spelled / matched).clamp(0.0, 1.0);
    return (tier: SearchTier.prefix, score: score);
  }

  // Tier 2. Nothing was spelled right, so guess — under the guards.
  final minLength = tokens.length == 1
      ? kMinFuzzTokenLenSingle
      : kMinFuzzTokenLenMulti;
  var total = 0.0;
  for (final token in tokens) {
    final mayGuess = token.length >= minLength;
    var best = 0.0;
    for (final word in words) {
      final score = _tokenWordScore(token, word, mayGuess: mayGuess);
      if (score > best) best = score;
    }
    // A token too short to guess at must be a word prefix, which scores 1.0.
    if (best < (mayGuess ? kTypoTokenFloor : 1.0)) return null;
    total += best;
  }
  return (tier: SearchTier.typo, score: total / tokens.length);
}

/// How well one query [token] hits one [word]: 1.0 for a word prefix, else a
/// similarity within the edit budget when [mayGuess], or 0.
double _tokenWordScore(String token, String word, {required bool mayGuess}) {
  if (word.startsWith(token)) return 1;
  if (!mayGuess) return 0;
  final budget = typoEditBudget(token.length);
  if (budget == 0) return 0;

  var best = 0.0;
  final whole = osaDistance(token, word);
  if (whole <= budget) {
    final longest = token.length > word.length ? token.length : word.length;
    best = 1 - whole / longest;
  }
  // A typo'd prefix of a longer word still hits (`almnd` → `almond butter`):
  // compare against the word's leading token.length characters.
  if (word.length > token.length) {
    final lead = osaDistance(token, word.substring(0, token.length));
    if (lead <= budget) {
      final score = 1 - lead / token.length;
      if (score > best) best = score;
    }
  }
  return best;
}

/// Optimal String Alignment distance: Levenshtein where an adjacent
/// transposition costs one edit, since a swap is the most common typo.
int osaDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  // Three rows, not two: a transposition reaches back to row i-2.
  final rows = List.generate(3, (_) => List<int>.filled(b.length + 1, 0));
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    final current = rows[i % 3];
    final previous = rows[(i - 1) % 3];
    final before = rows[(i - 2) % 3];
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = previous[j] + 1;
      if (current[j - 1] + 1 < best) best = current[j - 1] + 1;
      if (previous[j - 1] + cost < best) best = previous[j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
          before[j - 2] + 1 < best) {
        best = before[j - 2] + 1;
      }
      current[j] = best;
    }
  }
  return rows[a.length % 3][b.length];
}

/// The searchable surfaces of a bare [name]: phrase-normalized and
/// character-normalized.
///
/// The phrase normalizer drops measure words, so a title like "Green Goddess
/// Chickpea Jars" would lose "Jars". A typed query is only
/// character-normalized, so the phone searches both.
List<String> nameSurfaces(String name) {
  final phrase = normalizeMatchText(name);
  final raw = normalizeSearchQuery(name);
  return {phrase, raw}.where((s) => s.isNotEmpty).toList();
}

/// How well [query] hits a recipe [title]; the one call every recipe-title
/// picker makes.
SearchHit? recipeTitleHit(String title, String query) =>
    searchRank(query, nameSurfaces(title));

/// The best tier anything in [hits] reached, or null. A caller shows the rows
/// at this tier only, so a list is all spellings or all guesses.
SearchTier? bestTier(Iterable<SearchHit?> hits) {
  SearchTier? best;
  for (final hit in hits) {
    if (hit == null) continue;
    if (best == null || hit.tier.index < best.index) best = hit.tier;
    if (best == SearchTier.exact) break;
  }
  return best;
}
