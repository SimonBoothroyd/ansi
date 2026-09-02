/// Search-query normalization for the local vocab picker (pure Dart).
///
/// `ingredient.match_text` is written server-side by the shared normalizer
/// (`supabase/functions/_shared/normalize.ts`, spec §7): lowercase, hyphens
/// treated as word breaks, punctuation stripped within words, plus phrase-level
/// steps (word classification, singularization). A query typed into the picker
/// must go through the same *character-level* rules or it can never hit —
/// "all-purpose" would miss "all purpose flour" forever.
///
/// Only the character-level rules are mirrored here, deliberately:
/// - The phrase-level steps (dropping measures/prep words, singularizing,
///   reordering state words) operate on complete ingredient phrases; a search
///   query is a partial, in-flight prefix ("all-pu…"), and rewriting it would
///   make matching worse, not better.
/// - ADR-0004 keeps the phone deterministic-only — this is normalization, not
///   fuzzy matching, and it must stay byte-for-byte predictable.
///
/// Mirrored rules (keep in sync with `normalize.ts`):
/// 1. lowercase;
/// 2. hyphens/dashes become word breaks ("all-purpose" → "all purpose");
/// 3. Latin diacritics fold to their base letter ("jalapeño" → "jalapeno");
/// 4. within a word, anything that isn't a Unicode letter or number is
///    stripped ("won't" → "wont"), so `%`/`_` can never leak into a LIKE
///    pattern as wildcards;
/// 5. whitespace collapses to single spaces, trimmed.
library;

final _dashes = RegExp('[-–—]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);
final _whitespace = RegExp(r'\s+');

/// The combining marks a decomposed accented letter leaves behind.
final _combiningMarks = RegExp(r'[\u0300-\u036F]');

/// The Latin letters that carry diacritics, grouped under the base letter they
/// fold to. Each listed character is one Unicode codepoint whose *canonical*
/// decomposition is "base letter + combining mark", which is precisely what
/// the TypeScript mirror's `normalize("NFD")` takes apart — so the two sides
/// fold the same set.
///
/// Deliberately absent: `æ ø ð þ ß đ ħ ł ŋ œ ŧ ı`. They have no canonical
/// decomposition (they are letters in their own right, not accented ones), so
/// NFD leaves them alone and this table must too.
const _accentedLetters = {
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥ',
  'i': 'ìíîïĩīĭį',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľ',
  'n': 'ñńņň',
  'o': 'òóôõöōŏő',
  'r': 'ŕŗř',
  's': 'śŝşš',
  't': 'ţť',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final Map<String, String> _foldTable = {
  for (final entry in _accentedLetters.entries)
    for (final accented in entry.value.split('')) ...{
      accented: entry.key,
      accented.toUpperCase(): entry.key.toUpperCase(),
    },
};

/// Folds Latin diacritics onto their base letter, so a name typed without its
/// accents still hits the row that has them ("jalapeno" → **Jalapeño**).
///
/// The server's twin does this with `normalize("NFD")` plus a combining-mark
/// strip; Dart has no Unicode normalizer in its core library, so the
/// precomposed characters are tabled explicitly ([_accentedLetters]) and any
/// mark that arrives already decomposed is dropped. The stated bound: the
/// table covers Latin-1 Supplement and Latin Extended-A. A codepoint outside
/// them (Vietnamese `ộ`, say) folds on the server and does not fold here —
/// extend the table when a vocabulary needs one, and extend the shared
/// vectors with it.
String foldDiacritics(String raw) {
  final folded = StringBuffer();
  for (final ch in raw.split('')) {
    folded.write(_foldTable[ch] ?? ch);
  }
  return folded.toString().replaceAll(_combiningMarks, '');
}

/// Normalizes a raw picker query to the `match_text` character rules above.
String normalizeSearchQuery(String raw) => foldDiacritics(raw.toLowerCase())
    .replaceAll(_dashes, ' ')
    .split(_whitespace)
    .map((w) => w.replaceAll(_nonWord, ''))
    .where((w) => w.isNotEmpty)
    .join(' ');

/// Whether [rawQuery] hits [text] under the same rules the vocab search
/// applies in SQL: both sides normalized, then EVERY query token must match a
/// word of [text] as a word-prefix (order-independent). So "canned tomatoes"
/// finds "Canned Whole Tomatoes", "chicken" finds "Weeknight Chicken Curry",
/// and "hick" finds nothing. An empty query matches everything, mirroring the
/// browse-the-head behaviour. For in-memory lists (the recipe picker) that
/// have no `match_text` column to LIKE against.
bool matchesSearchQuery(String text, String rawQuery) {
  final tokens = searchTokens(rawQuery);
  if (tokens.isEmpty) return true;
  final words = normalizeSearchQuery(text).split(' ');
  return tokens.every((tok) => words.any((w) => w.startsWith(tok)));
}

/// The normalized, order-independent tokens of a query — the unit the vocab
/// search AND the fuzzy fallback both reason in. Empty for a blank query.
List<String> searchTokens(String raw) {
  final n = normalizeSearchQuery(raw);
  return n.isEmpty ? const [] : n.split(' ');
}

/// The per-token similarity floor a fuzzy (typo-tolerant) fallback accepts:
/// "chikn" → "chicken" clears it, an unrelated word does not.
const double kFuzzyTokenFloor = 0.7;

/// A typo-tolerant score for [rawQuery] against a normalized searchable
/// [text] (an ingredient's `match_text`, optionally with its aliases joined).
///
/// Deterministic, no external index (ADR-0004 stays true — this is a scored
/// character comparison, run only as a FALLBACK when the exact/prefix
/// token-subset search finds nothing). Every query token must find a text
/// word scoring at least [kFuzzyTokenFloor] (a prefix scores 1.0; otherwise a
/// normalized edit-distance similarity), or the score is -1 ("no match").
/// Otherwise the score is the mean of the per-token bests, so the closest
/// rows rank first.
double fuzzyQueryScore(String rawQuery, String text) {
  final tokens = searchTokens(rawQuery);
  if (tokens.isEmpty) return -1;
  final words = normalizeSearchQuery(
    text,
  ).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return -1;
  var total = 0.0;
  for (final tok in tokens) {
    var best = 0.0;
    for (final w in words) {
      final s = w.startsWith(tok) ? 1.0 : _similarity(tok, w);
      if (s > best) best = s;
    }
    if (best < kFuzzyTokenFloor) return -1;
    total += best;
  }
  return total / tokens.length;
}

/// Normalized edit-distance similarity in [0, 1] (1 == identical).
double _similarity(String a, String b) {
  if (a == b) return 1;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1;
  return 1 - _levenshtein(a, b) / maxLen;
}

/// Levenshtein edit distance (two-row DP).
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final del = prev[j + 1] + 1;
      final ins = curr[j] + 1;
      final sub = prev[j] + cost;
      final best = del < ins ? del : ins;
      curr[j + 1] = best < sub ? best : sub;
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}
