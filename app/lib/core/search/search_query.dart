/// Search-query normalization for the local vocab picker (pure Dart).
///
/// Mirrors the character-level rules of `ingredient.match_text`
/// (`supabase/functions/_shared/normalize.ts`), not the phrase-level ones: a
/// query is a partial prefix. Keep in sync: lowercase; hyphens and dashes
/// become word breaks; Latin diacritics fold; non-alphanumerics are stripped
/// within a word (so `%` and `_` never reach a LIKE); whitespace collapses.
/// Ranking lives in `search_rank.dart`.
library;

final _dashes = RegExp('[-–—]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);
final _whitespace = RegExp(r'\s+');

/// The combining marks a decomposed accented letter leaves behind.
final _combiningMarks = RegExp(r'[\u0300-\u036F]');

/// The precomposed Latin letters whose canonical decomposition is a base
/// letter plus a combining mark, grouped under that base: the set the
/// server's `normalize("NFD")` takes apart. `æ ø ð þ ß đ ħ ł ŋ œ ŧ ı` have no
/// decomposition and are absent.
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

/// Folds Latin diacritics onto their base letter ("jalapeño" → "jalapeno").
///
/// Dart has no Unicode normalizer, so [_accentedLetters] tables Latin-1
/// Supplement and Latin Extended-A. A codepoint outside them folds on the
/// server but not here; extend the table and the shared vectors together.
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

/// The normalized tokens of a query. Empty for a blank query.
List<String> searchTokens(String raw) {
  final n = normalizeSearchQuery(raw);
  return n.isEmpty ? const [] : n.split(' ');
}
