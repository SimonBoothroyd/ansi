/// The ingredient form's name suggestion — PURE DART (invariant 2).
///
/// A person filling in the ingredients manager types what the recipe said:
/// "2 cups flour", "chopped onions". Those are *lines*, not catalogue entries,
/// and the catalogue is what every other screen reads — the picker, the
/// shopping list, a method chip. So when the name field is left, the form
/// offers the entry the line was about: `Flour`, `Onion`.
///
/// **It is a suggestion, and it says so.** [cleanName] may recase silently
/// because case is not a word; this changes *which words are there*, and the
/// form prints `was “chopped onions” · keep the old word` under the field so
/// one tap puts the typed name back. Guessing quietly is how a vocabulary
/// fills up with names nobody chose.
///
/// **One vocabulary, not two.** Which words are quantity, measure, size, prep
/// or filler is already decided by [normalizeMatchText] — the port of the
/// server's `normalize.ts` (spec §7). This borrows that verdict through
/// [displayWords] rather than keeping a second list of stop words that could
/// drift from it.
///
/// What it deliberately does NOT do:
/// - **reorder.** The normalizer moves state words behind the noun so
///   "fresh ginger" and "ginger, fresh" key alike. A display name is read, not
///   keyed: `Fresh Ginger` stays as typed.
/// - **look for a twin.** Whether the household already has an `Onion` is the
///   picker's search to answer, in front of a person.
library;

import '../../../core/text/name_clean.dart';
import 'normalize.dart';

/// A better display name for an already-[cleanName]ed ingredient name, or null
/// when [cleaned] is already the entry it describes.
///
/// Two rules, in order:
/// 1. the words that are quantity, measure, size, prep or filler drop out
///    ("2 cups flour" → "flour");
/// 2. the last word is singularized ("onions" → "onion") by the normalizer's
///    own singularizer, so what it leaves alone — `hummus`, `couscous` — is
///    left alone here too.
///
/// Returns null rather than a name nobody would want: when the result matches
/// [cleaned] but for case, and when every word was a stop word ("2 cups"),
/// which would otherwise suggest nothing at all.
String? suggestIngredientName(String cleaned) {
  final kept = displayWords(cleaned);
  if (kept.isEmpty) return null;
  final words = [...kept.take(kept.length - 1), _singularizeTyped(kept.last)];
  final suggestion = cleanName(words.join(' '), NameKind.ingredient);
  if (suggestion.isEmpty) return null;
  return suggestion.toLowerCase() == cleaned.toLowerCase() ? null : suggestion;
}

/// [typed] singularized without disturbing the case the person used.
///
/// [singularizeToken] works on the normalizer's folded lowercase; feeding a
/// typed word straight through would return `bbq` for `BBQs`. Singularization
/// only ever rewrites the END of a word, so when the singular is a prefix of
/// the plural the typed word can simply be cut to length; the handful of forms
/// that rewrite instead (`-ies` → `-y`, the irregulars) fall back to the
/// singular as the normalizer spells it.
///
/// Trailing punctuation rides along untouched — the last word of
/// "Tomatoes, canned" is `canned`, but of "Tomatoes," it is `Tomatoes,`.
String _singularizeTyped(String typed) {
  final core = typed.replaceFirst(_trailingPunctuation, '');
  final suffix = typed.substring(core.length);
  final lower = core.toLowerCase();
  final singular = singularizeToken(lower);
  if (singular == lower) return typed;
  return lower.startsWith(singular)
      ? core.substring(0, singular.length) + suffix
      : singular + suffix;
}

final _trailingPunctuation = RegExp(r'[^\p{L}\p{N}]+$', unicode: true);
