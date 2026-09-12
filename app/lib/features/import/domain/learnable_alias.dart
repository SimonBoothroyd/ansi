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
/// **The rule is structural, not semantic** — four marks that say the phrase
/// is doing more than naming one thing:
///
/// * a **comma** — a modifier hangs off the name ("Olive oil, for frying");
/// * the word **or** — the line offered a choice, so it names two things;
/// * a **slash** — the same choice, punctuated ("butter/margarine");
/// * a **bracket** — an aside, which is not part of any name.
///
/// It deliberately refuses nothing else. A long plain phrase is still a name a
/// household might say ("sweet white sorghum flour"), and guessing at which
/// plain phrases are "too descriptive" would be taste, not a rule.
///
/// Asked of the RAW text, before `normalizeMatchText`: normalization strips
/// commas and drops "or" as filler, so by then every one of these marks is
/// gone and the damage is already done.
library;

/// The word `or` standing alone — the choice, not the `or` inside "orange" or
/// the one ending "cilantro r…". Case-insensitive, because a line printed in
/// title case says "Or" just as often.
final _choice = RegExp(r'\bor\b', caseSensitive: false);

/// Every mark that says the phrase is a line rather than a name.
final _notAName = RegExp(r'[,/()\[\]{}]');

/// Whether [candidate] reads as the name of one thing, and so is worth
/// learning as an alias.
///
/// The caller's answer to `false` is **silence**, not an error: the line has
/// already resolved to the row the person picked, which is the whole of what
/// they asked for (import spec §8).
bool looksLikeAName(String candidate) =>
    !_notAName.hasMatch(candidate) && !_choice.hasMatch(candidate);
