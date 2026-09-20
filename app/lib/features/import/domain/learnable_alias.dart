/// Whether a corrected line's raw text is a NAME the household could learn as
/// an alias — PURE DART (invariant 2).
///
/// The rule is structural. A phrase is refused when it carries a comma, a
/// slash, a bracket or the word *or* ("Olive oil, for frying"), or a word that
/// hands the choice to the cook ("your favourite pasta"): neither can match a
/// future line. It refuses nothing beyond this — a long plain phrase is still
/// a name someone might say.
///
/// It is asked of the RAW text, before `normalizeMatchText`, which would strip
/// the commas and filler words that give a line away. A guard test asks the
/// same question of every alias in the seed template. The server holds no
/// learning path, so this predicate is the whole rule.
library;

/// The word `or` standing alone — not the `or` inside "orange".
final _choice = RegExp(r'\bor\b', caseSensitive: false);

/// Every mark that says the phrase is a line rather than a name.
final _notAName = RegExp(r'[,/()\[\]{}]');

/// Words that point at the COOK rather than the food. A closed set: a word
/// belongs only if it makes the phrase about the reader's choice, which is why
/// "extra" and "good" are absent ("extra virgin olive oil" is a name).
const _aboutTheCook = {
  // Second person and possessive — a name belongs to the food, not the reader.
  'your', 'yours', 'you', 'my', 'mine', 'our', 'ours',
  // Open choice — the line names a category to pick from, not the pick.
  'any', 'either', 'whatever', 'whichever', 'some',
  // Preference — the judgement the cook is being asked to make.
  'favourite', 'favorite', 'choice', 'preferred', 'preference',
  'desired', 'liking', 'taste', 'optional', 'ideally',
};

/// Letter runs, so a word is matched whole and punctuation cannot hide one.
final _words = RegExp('[a-z]+');

/// Whether [candidate] reads as the name of one thing. The caller answers
/// `false` with silence, not an error: the line has already resolved.
bool looksLikeAName(String candidate) =>
    !_notAName.hasMatch(candidate) &&
    !_choice.hasMatch(candidate) &&
    !_namesADecision(candidate);

/// Whether any word of [candidate] hands the choice to the cook.
bool _namesADecision(String candidate) => _words
    .allMatches(candidate.toLowerCase())
    .any((m) => _aboutTheCook.contains(m[0]));
