/// Whether a corrected line's raw text is a NAME the household could learn —
/// PURE DART (invariant 2).
///
/// The learning loop writes the raw string back as an alias on the row the
/// person picked (import spec §8). That is nearly free and worth a lot when
/// the string is a name someone would say — "dried sage" onto *Sage*, "brown
/// onions" onto *Onion*. It is worth nothing, and costs vocabulary, when the
/// string is the whole printed LINE:
///
/// > fresh basil, reserved for garnish
/// > stone-ground mustard or Creole mustard
/// > olive oil or cooking oil of choice
/// > Olive oil, for frying
/// > vegan cheddar or American cheese
///
/// Those are real rows in the owner's cloud vocabulary. None of them can ever
/// match a future line, because no future line will print that sentence again;
/// and each one normalizes into a bag of words ("olive oil cooking oil choice")
/// that the exact tier will never ask for. They are noise a person then has to
/// prune by hand.
///
/// **The rule is structural, not semantic**, and it asks two questions of the
/// phrase. First, four marks that say the phrase is doing more than naming one
/// thing:
///
/// * a **comma** — a modifier hangs off the name ("Olive oil, for frying");
/// * the word **or** — the line offered a choice, so it names two things;
/// * a **slash** — the same choice, punctuated ("butter/margarine");
/// * a **bracket** — an aside, which is not part of any name.
///
/// Second — and this is the half the marks cannot see — whether the phrase
/// names a **thing** at all, or names a **decision**:
///
/// > your favourite pasta
/// > desired berries
/// > pasta of your choice
/// > any plant milk
///
/// Also real rows in the owner's vocabulary. "your favourite pasta" carries no
/// comma, no *or*, no slash and no bracket, and it got through on that alone:
/// the marks test how a phrase is PUNCTUATED, and this phrase is punctuated
/// like a name. What it is not is a name. The recipe deferred the choice to
/// whoever is cooking, so the words point at the cook rather than at anything
/// on a shelf, and no future line can print them meaning this row — the next
/// cook's favourite pasta is a different pasta.
///
/// So a small closed set of words is refused outright, in three groups, none of
/// which appears in the name of any food:
///
/// * **second person and possessive** — *your*, *my*, *our*: a name belongs to
///   the food, never to the reader;
/// * **open choice** — *any*, *either*, *whatever*, *whichever*, *some*: the
///   line names a category to pick from, not the pick;
/// * **preference** — *favourite*, *choice*, *preferred*, *desired*, *liking*,
///   *taste*, *optional*, *ideally*: the judgement the cook is being asked to
///   make.
///
/// Beyond those two questions it deliberately refuses nothing. A long plain
/// phrase is still a name a household might say ("sweet white sorghum flour"),
/// and guessing at which plain phrases are "too descriptive" would be taste,
/// not a rule. "cooking oil spray" is learned: it is a thing a shop sells and a
/// page can print again, however loosely it names a brand.
///
/// **It judges the phrase, not the phrase's relation to the printed line.** The
/// earlier framing — "never the whole printed LINE" — could not be implemented
/// as written, and that is the second half of how "your favourite pasta" got
/// through. The candidate reaching this loop is the extractor's
/// `ingredientText`, which already has the amount split off it ("1 lb your
/// favourite pasta" arrives as "your favourite pasta"), and the printed line
/// itself is never persisted — `ReconLine.sourceSpan` is additive and the
/// server omits it whenever the words cannot be pointed at unambiguously. There
/// is no line here to compare against, before or after amount stripping, so the
/// phrase has to answer for itself.
///
/// Asked of the RAW text, before `normalizeMatchText`: normalization strips
/// commas, drops "or" and "desired" as filler, and would erase half of what
/// gives a line away before it could be seen.
///
/// There is no second implementation to keep in step. The server holds no
/// learning path — the correction alias arrives through the sync queue, and
/// `supabase/functions/_shared/match_db.ts` §8 says why the server-side
/// contract was deleted — so this predicate is the whole of the rule.
library;

/// The word `or` standing alone — the choice, not the `or` inside "orange" or
/// the one ending "cilantro r…". Case-insensitive, because a line printed in
/// title case says "Or" just as often.
final _choice = RegExp(r'\bor\b', caseSensitive: false);

/// Every mark that says the phrase is a line rather than a name.
final _notAName = RegExp(r'[,/()\[\]{}]');

/// Words that point at the COOK rather than at the food, so the phrase names a
/// decision and not a thing. Three groups — second person and possessive, open
/// choice, preference — and no food name carries any of them.
///
/// A closed set on purpose. It is not a stop-word list to be grown whenever a
/// phrase looks untidy: a word earns its place here only by making the phrase
/// about the reader's choice, which is why "extra", "best" and "good" are
/// absent ("extra virgin olive oil" is a name, and "good olive oil" says
/// something about the oil).
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
/// Deliberately blind to digits and diacritics: every word of [_aboutTheCook]
/// is plain ASCII, and a token like "400g" can only fail to match.
final _words = RegExp('[a-z]+');

/// Whether [candidate] reads as the name of one thing, and so is worth
/// learning as an alias.
///
/// The caller's answer to `false` is **silence**, not an error: the line has
/// already resolved to the row the person picked, which is the whole of what
/// they asked for (import spec §8).
bool looksLikeAName(String candidate) =>
    !_notAName.hasMatch(candidate) &&
    !_choice.hasMatch(candidate) &&
    !_namesADecision(candidate);

/// Whether any word of [candidate] hands the choice to the cook.
bool _namesADecision(String candidate) => _words
    .allMatches(candidate.toLowerCase())
    .any((m) => _aboutTheCook.contains(m[0]));
