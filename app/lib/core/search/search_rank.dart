/// **The** rule for matching typed text against a name — PURE DART.
///
/// One function, [searchRank], answers *how well does this query hit this
/// name*. Every place on the phone that searches typed text calls it: the
/// ingredient picker's SQL fallback, the planning recipe picker, the editor's
/// "Your recipes" section, and (tiers 0/1 only) the import re-match seam. The
/// corpus a caller passes differs; the rule never does — one rule per site is
/// how they end up failing in opposite directions
/// (`docs/design-docs/search-and-matching.md`).
///
/// **Three tiers, first hit wins.** A tier-2 hit can never outrank a tier-0 or
/// tier-1 hit whatever the scores say — that is what makes "did you mean"
/// honest:
///
/// 0. **exact** — the normalized query (raw or singularized) IS one of the
///    row's surfaces. Score 1.0.
/// 1. **prefix** — every query token, raw or singular, word-prefixes some word
///    of the surface, order-independent. Score = how much of the matched words
///    the query actually spelled, so `onion` outranks `onion powder`.
/// 2. **typo** — per-token guarded edit distance, and only when 0 and 1 found
///    nothing at all. See [SearchTier.typo] for the guards and why each one is
///    the value it is.
///
/// **ADR-0004 still holds.** This is a deterministic, scored character
/// comparison over the household's own synced vocabulary — no index, no model,
/// no reference set. It also never *resolves* anything: tier 2 is retrieval
/// for a human to pick, never a resolution, which is why the import re-match
/// seam is given tiers 0/1 and nothing more.
library;

// The phrase normalizer is the server's rule ported to Dart, and it still
// lives beside the vocabulary it writes `match_text` for. The ranking
// needs its tokenizer, so this one edge points at the feature; the rest
// of the search rule has no feature above it.
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

  /// The query was guessed at. Runs only when [exact] and [prefix] are empty,
  /// and every token must clear the guards below.
  typo,
}

/// A hit: which tier produced it, and how well it scored inside that tier.
/// Compare tiers first, scores only within a tier.
typedef SearchHit = ({SearchTier tier, double score});

/// Shortest token that may be *guessed at* when the query is one word.
///
/// Four characters is where the phone starts guessing: it finds `almnd` →
/// Almonds, `nion` → Onion and `aoli` → Romesco Aioli, and measured over the
/// 308-row seed vocabulary it lifts right-family recall at rank 1 from 80 % to
/// 93 %. The price is real words landing on the wrong food (`beef` → Beets),
/// which is tolerable only because they appear under a "did you mean" header.
const int kMinFuzzTokenLenSingle = 4;

/// Shortest token that may be guessed at when the query has two or more words.
///
/// Lower than [kMinFuzzTokenLenSingle] because a correctly spelled neighbour
/// corroborates: `coconut mlk` and `soy suace` resolve, while a lone `mlk`
/// stays silent. A token under this length is not refused — it simply has to
/// be spelled right (an exact word prefix, scoring 1.0).
const int kMinFuzzTokenLenMulti = 3;

/// The per-token similarity floor a guess must clear. Belt and braces: on the
/// current vocabulary the edit budget rejects everything this would, but it is
/// the guard that still holds on a vocabulary of much longer names.
const double kTypoTokenFloor = 0.75;

/// How badly a token of a given length may be misspelled, in edits.
///
/// Length-relative, so a long word gets proportionally more forgiveness
/// without a short one getting any: nothing under 3 characters, one edit to 7,
/// two from 8. A transposition is ONE edit ([osaDistance]).
int typoEditBudget(int tokenLength) {
  if (tokenLength >= 8) return 2;
  if (tokenLength >= 3) return 1;
  return 0;
}

/// Ranks [query] against one row's [surfaces], or null when it does not hit.
///
/// [surfaces] is the row's whole searchable surface, each entry a normalized
/// phrase: its `match_text`, each live alias's `match_text`, and the
/// character-normalized raw name — see [nameSurfaces] for why the raw name is
/// not redundant.
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

  // Tier 1. Every token word-prefixes some word, raw or singular. The score is
  // how much of the matched words the query spelled — `onion` scores 1.0
  // against Onion and 0.42 against `onion powder`, which is the ranking the
  // old `length(canonical_name)` proxy was reaching for.
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
    // A token too short to guess at is not refused — it just has to be spelled
    // right, which is a word prefix, which scores exactly 1.0.
    if (best < (mayGuess ? kTypoTokenFloor : 1.0)) return null;
    total += best;
  }
  return (tier: SearchTier.typo, score: total / tokens.length);
}

/// How well one query [token] hits one [word] of the surface: 1.0 for a word
/// prefix, else — when the token is long enough to be guessed at — a
/// similarity within the edit budget, or 0.
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
  // Prefix tolerance: a typo'd PREFIX of a longer name should still hit —
  // `almnd` names `almond butter` as much as it names `almond`. Scored
  // against the word's leading token.length characters, so the rest of a long
  // name is not counted as a difference.
  if (word.length > token.length) {
    final lead = osaDistance(token, word.substring(0, token.length));
    if (lead <= budget) {
      final score = 1 - lead / token.length;
      if (score > best) best = score;
    }
  }
  return best;
}

/// Optimal String Alignment distance — Damerau-Levenshtein restricted to
/// adjacent transpositions, where a swapped pair costs **one** edit, not two.
///
/// This is the single highest-value guard in the rule. Under plain
/// Levenshtein a swap costs double, which is why `soy suace` and `parsely`
/// found nothing at all: transposition is the most common human typo, and
/// charging it twice refuses exactly the class of mistake the tier exists for.
/// Measured over 477 generated one-edit typos, switching the metric moves
/// right-family recall from 47 % to 80 %.
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

/// The searchable surface of a bare [name] — a recipe title, or a vocab row
/// whose stored `match_text` the caller does not have to hand.
///
/// Two spellings, and the second is NOT redundant. The phrase normalizer drops
/// measure words, so `normalizeMatchText('Green Goddess Chickpea Jars')` is
/// `green goddess chickpea` — "Jars" is in the measure strip-set and vanishes.
/// Indexing a title through the phrase normalizer alone silently deletes any
/// name word that happens to be a measure: Jars, Sticks, Blocks, Head, Bunch,
/// Packs, Slices. The server escapes this because it normalizes both sides
/// identically; the phone cannot, because a typed query is deliberately only
/// character-normalized. So the phone searches both surfaces.
List<String> nameSurfaces(String name) {
  final phrase = normalizeMatchText(name);
  final raw = normalizeSearchQuery(name);
  return {phrase, raw}.where((s) => s.isNotEmpty).toList();
}

/// How well [query] hits a recipe [title] — the one call both recipe-title
/// pickers make, so the planning picker and the editor's "Your recipes"
/// section can never disagree again.
SearchHit? recipeTitleHit(String title, String query) =>
    searchRank(query, nameSurfaces(title));

/// The best tier anything in [hits] reached, or null when nothing hit.
///
/// A caller shows the rows at this tier and drops the rest. That is what makes
/// the band honest across a whole corpus rather than just per row: a list is
/// all spellings or all guesses, never a guess trailing under a spelling.
SearchTier? bestTier(Iterable<SearchHit?> hits) {
  SearchTier? best;
  for (final hit in hits) {
    if (hit == null) continue;
    if (best == null || hit.tier.index < best.index) best = hit.tier;
    if (best == SearchTier.exact) break;
  }
  return best;
}
