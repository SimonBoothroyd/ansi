/// Tidying the names a person types — PURE DART.
///
/// A name typed into an editor arrives with the debris of typing: a stray
/// leading space, a double space where a word was rewritten, a full stop at
/// the end because the finger was already there. None of it is meaningful, and
/// all of it survives into every list, every search and every printed line.
/// [cleanName] is the one place that debris is removed, so the Library, the
/// ingredients manager and the recipe page cannot disagree about what a name
/// looks like.
///
/// **It only ever adds capitals.** Case is evidence: `BBQ`, `pH`, `McIntosh`
/// and `Cream Of Tartar` are all things a person meant, and a rule that
/// lowercases them to fit a house style is a rule that corrupts data to look
/// tidy. So the only case change here is uppercasing a letter that is
/// lowercase — never the reverse.
///
/// Its counterpart, `suggestIngredientName`, is where a *word* may change; it
/// is told, not silent, and lives beside the normalizer whose vocabulary it
/// borrows (`features/ingredients/domain/suggest_name.dart`).
library;

/// The kinds of name a person types, and how much each may be recased.
///
/// The kinds differ only in case, because they differ only in what a person
/// expects: an ingredient is a catalogue entry and reads as a label
/// (`Cream of Tartar`), while a recipe, a book or a section is a title
/// somebody wrote and keeps its own shape (`Wild garlic pesto`). An alias is
/// stored lowercase by the vocabulary (`supabase/seed/vocab.jsonl`), so
/// recasing it would only be undone.
enum NameKind {
  /// An ingredient's canonical name — Title Case, small words excepted.
  ingredient,

  /// A recipe title — first letter only.
  recipe,

  /// A book name — first letter only.
  book,

  /// A section name — first letter only.
  section,

  /// An alias — whitespace and trailing punctuation only, no recasing.
  alias,
}

/// The words Title Case leaves alone when they are not the first word.
///
/// Short, and deliberately not a general English list: these are the words
/// that actually turn up inside food names. A longer list buys nothing and
/// starts making decisions about words a person may have meant.
const _smallWords = {
  'of',
  'and',
  'with',
  'in',
  'the',
  'a',
  'an',
  'for',
  'on',
  'or',
  'to',
};

final _whitespace = RegExp(r'\s+');

/// [raw] with the debris of typing removed, cased for [kind].
///
/// In order: trim, collapse every run of whitespace (tabs and newlines
/// included) to one space, drop a single trailing `.` or `,`, then recase.
///
/// The trailing stop is dropped only when it stands alone — `Etc...` keeps its
/// ellipsis and `1, 2,,` keeps its commas — which is both the kinder reading
/// and what makes this function **idempotent**: `cleanName(cleanName(x)) ==
/// cleanName(x)` for every input and kind.
String cleanName(String raw, NameKind kind) {
  final collapsed = raw.trim().replaceAll(_whitespace, ' ');
  final trimmed = _dropTrailingStop(collapsed).trim();
  if (trimmed.isEmpty) return trimmed;
  return switch (kind) {
    NameKind.ingredient => _titleCase(trimmed),
    NameKind.recipe ||
    NameKind.book ||
    NameKind.section => _upperFirstLetter(trimmed),
    NameKind.alias => trimmed,
  };
}

String _dropTrailingStop(String s) {
  if (s.length < 2) return s;
  final last = s[s.length - 1];
  if (last != '.' && last != ',') return s;
  final before = s[s.length - 2];
  // A run of stops is a deliberate mark, not a slip of the finger.
  if (before == '.' || before == ',') return s;
  return s.substring(0, s.length - 1);
}

/// Every word's first letter uppercased, except a [_smallWords] entry that is
/// not the first word.
///
/// A word is a space-separated token; each hyphenated part of one is capped in
/// its own right, so `stir-fry sauce` reads `Stir-Fry Sauce`.
String _titleCase(String s) {
  final words = s.split(' ');
  return [
    for (final (i, word) in words.indexed)
      if (i > 0 && _smallWords.contains(word.toLowerCase()))
        word
      else
        word.split('-').map(_upperFirstLetter).join('-'),
  ].join(' ');
}

/// [s] with its first *letter* uppercased and everything else untouched.
///
/// Leading punctuation is stepped over, so `(optional)` caps the `o`. A letter
/// is anything whose upper and lower cases differ — the same test `chipWord`
/// makes, which keeps digits, glyphs and CJK out of it without a table.
///
/// A letter whose uppercase is longer than itself (`ß` → `SS`) is left as
/// typed: growing a word is not recasing it.
String _upperFirstLetter(String s) {
  final runes = s.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final c = String.fromCharCode(runes[i]);
    if (c.toUpperCase() == c.toLowerCase()) continue;
    final upper = c.toUpperCase();
    if (upper == c || upper.length != c.length) return s;
    return String.fromCharCodes(runes.take(i)) +
        upper +
        String.fromCharCodes(runes.skip(i + 1));
  }
  return s;
}
