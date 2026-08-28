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
/// 3. within a word, anything that isn't a Unicode letter or number is
///    stripped ("won't" → "wont"), so `%`/`_` can never leak into a LIKE
///    pattern as wildcards;
/// 4. whitespace collapses to single spaces, trimmed.
library;

final _dashes = RegExp('[-–—]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);
final _whitespace = RegExp(r'\s+');

/// Normalizes a raw picker query to the `match_text` character rules above.
String normalizeSearchQuery(String raw) => raw
    .toLowerCase()
    .replaceAll(_dashes, ' ')
    .split(_whitespace)
    .map((w) => w.replaceAll(_nonWord, ''))
    .where((w) => w.isNotEmpty)
    .join(' ');
