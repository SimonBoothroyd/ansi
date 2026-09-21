/// Tidying the names a person types. Pure Dart.
///
/// [cleanName] removes stray whitespace and a trailing stop so every surface
/// agrees on what a name looks like. It only ever adds capitals: `BBQ`, `pH`
/// and `McIntosh` are kept as typed. A change of word is
/// `suggestIngredientName`'s job
/// (`features/ingredients/domain/suggest_name.dart`).
library;

/// The kinds of name a person types, and how much each may be recased.
/// Everything a household names gets Title Case; an alias is stored
/// lowercase by the vocabulary, so it is not recased.
enum NameKind {
  /// A name a household gives something: Title Case, small words excepted.
  title,

  /// An alias: whitespace and trailing punctuation only, no recasing.
  alias,
}

/// The words Title Case leaves lowercase when not first. Deliberately short:
/// only words that turn up inside food names.
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

/// [raw] tidied and cased for [kind]: trim, collapse whitespace runs to one
/// space, drop a single trailing `.` or `,`, then recase.
///
/// A run of stops (`Etc...`) is kept, which makes the function idempotent.
String cleanName(String raw, NameKind kind) {
  final collapsed = raw.trim().replaceAll(_whitespace, ' ');
  final trimmed = _dropTrailingStop(collapsed).trim();
  if (trimmed.isEmpty) return trimmed;
  return switch (kind) {
    NameKind.title => _titleCase(trimmed),
    NameKind.alias => trimmed,
  };
}

String _dropTrailingStop(String s) {
  if (s.length < 2) return s;
  final last = s[s.length - 1];
  if (last != '.' && last != ',') return s;
  final before = s[s.length - 2];
  // A run of stops is deliberate.
  if (before == '.' || before == ',') return s;
  return s.substring(0, s.length - 1);
}

/// Uppercases every word's first letter, except a [_smallWords] entry that
/// is not first. Each hyphenated part is capped (`Stir-Fry Sauce`). Only the
/// head is cased: what follows a comma is a qualifier, left as typed
/// (`Chicken Thigh, boneless`).
String _titleCase(String s) {
  final comma = s.indexOf(',');
  if (comma >= 0) {
    return _titleCase(s.substring(0, comma)) + s.substring(comma);
  }
  final words = s.split(' ');
  return [
    for (final (i, word) in words.indexed)
      if (i > 0 && _smallWords.contains(word.toLowerCase()))
        word
      else
        word.split('-').map(_upperFirstLetter).join('-'),
  ].join(' ');
}

/// [s] with its first letter uppercased and everything else untouched.
///
/// Leading punctuation is stepped over. A letter is anything whose upper and
/// lower cases differ. A letter whose uppercase is longer (`ß` → `SS`) is
/// left as typed.
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
