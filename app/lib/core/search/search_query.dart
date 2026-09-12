/// Search-query normalization for the local vocab picker (pure Dart).
///
/// `ingredient.match_text` is written server-side by the shared normalizer
/// (`supabase/functions/_shared/normalize.ts`, spec §7): lowercase, hyphens
/// treated as word breaks, punctuation stripped within words, plus phrase-level
/// steps (word classification, singularization). A query typed into the picker
/// must go through the same *character-level* rules or it can never hit —
/// "all-purpose" would miss "all purpose flour" forever.
///
/// This file is the NORMALIZER only. What counts as a hit, and how hits rank,
/// is `search_rank.dart`'s one rule — see it for the three tiers.
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

/// The normalized, order-independent tokens of a query — the unit every tier
/// of `searchRank` reasons in. Empty for a blank query.
List<String> searchTokens(String raw) {
  final n = normalizeSearchQuery(raw);
  return n.isEmpty ? const [] : n.split(' ');
}
