/// The **phrase-level** ingredient normalizer — PURE DART (invariant 2).
///
/// This is the Dart port of `supabase/functions/_shared/normalize.ts` (plan
/// 0020 D6, spec §7). The server writes every `ingredient.match_text` with
/// those phrase rules; before this port the app could only apply the
/// *character* rules ([normalizeSearchQuery]), so a stub created in the picker
/// carried a `match_text` the server would never have written — and the next
/// import's cascade, searching by the server's rules, missed it.
///
/// **Two mirrors, one fact.** `normalize.ts` stays authoritative for the
/// server; this is its twin. The shared vectors in
/// `test/features/ingredients/normalize_vectors.json` are copied from
/// `normalize.test.ts` and pin the two together — the same habit
/// `default_allowed_units()` and `defaultAllowedUnitSet` already keep. Change
/// one, change both, and extend the vectors.
///
/// What it does, in order (unchanged from the TS):
/// 1. lowercase, hyphens/dashes → word breaks, Latin diacritics folded onto
///    their base letter ("Jalapeño" → `jalapeno`, so a line printed without
///    the tilde still matches — plan 0023 D5);
/// 2. split trailing comma modifier(s) off the head;
/// 3. drop non-identity words — quantities (including an amount fused to its
///    unit, "400g"), filler, measures/containers, sizes, prep adverbs and
///    prep verbs;
/// 4. KEEP form/state words that DO change identity (fresh, ground, canned)
///    and move them after the noun, so "fresh ginger" and "ginger, fresh"
///    both land on "ginger fresh"; a British surface form folds onto the one
///    the vocabulary stores first (tinned → canned);
/// 5. singularize what remains.
///
/// The §7 own-goal is over-stripping: "ground ginger" ≠ "fresh ginger". Never
/// move a word into a strip set to make one match work.
library;

import 'search_query.dart' show foldDiacritics, normalizeSearchQuery;

/// Articles and filler words carrying no identity.
const _filler = {'a', 'an', 'the', 'of', 'or', 'and', 'desired'};

/// Container / measure / vague-amount words — quantity, not identity.
const _measures = {
  // Standard cooking units. The miner parses them separately; they are
  // stripped here too for when they appear mid-phrase ("heaping tablespoon
  // nutritional yeast").
  'teaspoon', 'teaspoons', 'tsp',
  'tablespoon', 'tablespoons', 'tbsp', 'tbs',
  'cup', 'cups',
  'gram', 'grams', 'g',
  'kg', 'kilogram', 'kilograms',
  'ounce', 'ounces', 'oz',
  'pound', 'pounds', 'lb', 'lbs',
  'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres',
  'liter', 'liters', 'litre', 'litres', 'l',
  'quart', 'quarts', 'pint', 'pints', 'gallon', 'gallons',
  'fl', 'fluid',
  'can', 'cans', 'tin', 'tins', 'jar', 'jars', 'bottle', 'bottles',
  'package', 'packages', 'packet', 'packets', 'box', 'boxes',
  'bag', 'bags', 'bunch', 'bunches',
  'handful', 'handfuls', 'pinch', 'pinches', 'dash', 'dashes',
  'sprig', 'sprigs', 'stick', 'sticks', 'head', 'heads',
  'drop', 'drops', 'piece', 'pieces', 'slices', 'few',
  'crack', 'cracks', 'splash', 'dollop', 'knob', 'glug',
  'sprinkle', 'drizzle',
  'pack', 'packs', 'block', 'blocks', 'batch', 'batches',
  'spoonful', 'spoonfuls',
};

/// Size adjectives — they scale the amount, not the ingredient. "extra" is
/// intentionally absent: it changes identity in "extra virgin".
const _sizes = {'large', 'small', 'medium', 'big', 'tiny'};

/// Prep adverbs that only ever modify a prep verb.
const _prepAdverbs = {
  'finely',
  'roughly',
  'thinly',
  'coarsely',
  'freshly',
  'heaping',
  'scant',
  'rounded',
  'generous',
  'packed',
  'drizzling',
  'very',
};

/// Prep verbs (past participles) that describe handling, never identity.
/// "ground" is deliberately absent — it changes identity (ground vs fresh
/// ginger) and lives in [_stateWords].
const _prepVerbs = {
  'chopped',
  'diced',
  'minced',
  'sliced',
  'grated',
  'shredded',
  'crushed',
  'peeled',
  'cubed',
  'julienned',
  'halved',
  'quartered',
  'trimmed',
  'beaten',
  'melted',
  'drained',
  'rinsed',
  'deseeded',
  'seeded',
  'pitted',
  'cored',
  'mashed',
  'crumbled',
  'softened',
  'cut',
  'torn',
};

/// Cut words that are prep everywhere EXCEPT inside a canned/tinned phrase,
/// where they name the product on the shelf: a can of diced tomatoes and a
/// can of chopped tomatoes are the same SKU, and neither is a can of crushed.
/// The gold conventions already rule this — "Chopped/crushed/diced tomatoes
/// (tinned) are DIFFERENT PRODUCTS"
/// (`evals/datasets/extraction/gold/_SCHEMA.md`) — and the extraction prompt
/// keeps the word in identity for the same reason; this is the matcher
/// catching up.
///
/// Same shape as the `clove`/allium and `stick`/cinnamon carve-outs: a word
/// whose class depends on a noun sharing the phrase. Outside a canned phrase
/// these stay prep — "2 diced tomatoes" is still `tomato`, the fresh one.
///
/// "crushed" is deliberately absent — see the note in `normalize.ts`: it
/// already holds the generic `tomato canned` key that the generated
/// `seed_measures.sql` keys measures on, and that file cannot be regenerated
/// without the uncommitted FDC bundles.
const _cannedCutWords = {'chopped', 'diced'};

/// Form/state words that DO change identity. Kept, and moved to the end so
/// the noun leads regardless of where the descriptor sat. The §7 KEEP set —
/// the guard against over-stripping.
const _stateWords = {
  'fresh',
  'ground',
  'dried',
  'dry',
  'frozen',
  'canned',
  'smoked',
  'whole',
  'boneless',
  'skinless',
  'ripe',
  'unsalted',
  'salted',
  'raw',
  'toasted',
  'roasted',
  'powdered',
  'cooked',
  'uncooked',
  'shelled',
  'sweetened',
  'unsweetened',
};

/// Singular words the suffix rules would mangle because they END like a
/// plural. The regex guard ([_looksSingular]: `-ss`, `-us`, `-is`, `-ous`)
/// already spares boneless, asparagus and hummus; this set is for the words
/// it cannot see — "molasses" ends in `-sses`, so the guard misses it and the
/// sibilant rule used to write `molass`.
///
/// Admission rule: a word goes in only when it is genuinely singular AND the
/// rules produce a non-word for it. A word the rules reduce to a real stem
/// (grits → grit, brussels → brussel) stays out — the query side reduces it
/// the same way, so the stored key still matches — and would cost every
/// household a `match_text` rewrite for no gain. Adding a word here changes
/// what is stored: pair it with a migration that rewrites the old form in
/// place (`0022_singularize_invariants.sql` is the model), mirror it in
/// `normalize.ts`, and extend the shared vectors.
const _invariantWords = {'molasses'};

/// Irregular plurals a suffix rule would get wrong.
const _irregularPlurals = {
  'leaves': 'leaf',
  'loaves': 'loaf',
  'halves': 'half',
  'knives': 'knife',
  'chillies': 'chilli',
  'chilies': 'chili',
};

const _fractionGlyphs = '¼½¾⅓⅔⅕⅖⅗⅘⅙⅐⅛⅜⅝⅞';

/// Purely a quantity token: digits, unicode fractions, ranges.
final _quantity = RegExp('^[0-9$_fractionGlyphs/.,\\-–—]+\$');

/// An amount fused to its unit in one token: "400g", "1.5kg", "½oz".
/// [_measures] lists the unit words bare and [_quantity] needs the WHOLE token
/// to be numeric, so a printed "400g tin of black beans" used to keep `400g`
/// as a noun and matched nothing at all. Only the unambiguous mass/volume
/// abbreviations: a bare "l" or "g" after a number can only be a unit, while a
/// longer suffix would start eating real words.
final _fusedAmount = RegExp(
  '^[0-9$_fractionGlyphs/.,\\-–—]+(g|kg|mg|ml|l|oz|lb)\$',
);

/// British surface forms folded onto the word the vocabulary stores. "tinned"
/// and "canned" name the same thing on the same shelf, but only "canned" is a
/// state word — so "tinned chickpeas" used to key as `tinned chickpea`, a
/// leading noun nothing else produces, and missed `chickpea canned` by enough
/// to lose the auto band.
///
/// A word added here changes what is STORED: pair it with a migration that
/// rewrites the old form in place (`0031_tinned_is_canned.sql` is the model),
/// mirror it in `normalize.ts`, and extend the shared vectors.
const _synonyms = {'tinned': 'canned'};

/// Everything a word may keep: unicode letters/numbers, `/`, fraction glyphs
/// (kept so [_quantity] can still recognise "1/2" and "½").
final _punctuation = RegExp('[^\\p{L}\\p{N}/$_fractionGlyphs]', unicode: true);

final _dashes = RegExp('[-–—]');
final _whitespace = RegExp(r'\s+');
final _allium = RegExp(r'\b(garlic|shallots?|scallions?)\b');
final _cinnamon = RegExp(r'\bcinnamon\b');

/// The canned/tinned marker that turns a cut word into identity.
final _canned = RegExp(r'\b(canned|tinned)\b');

/// Normalizes a raw ingredient string to its `match_text` (see the library
/// doc). Deterministic and pure: same string in, same string out.
///
/// This is what every locally authored vocab row's `match_text` must be
/// written with — stub creation and rename alike — so the server's cascade
/// can find it. [normalizeSearchQuery] stays the right tool for an in-flight
/// *search* prefix, which must not be singularized or reordered.
String normalizeMatchText(String ingredientText) {
  // Hyphens join compound descriptors ("all-purpose"); treat them as word
  // breaks so the parts tokenize rather than fusing ("allpurpose"). Diacritics
  // fold here rather than in [_classify] so every downstream test — the
  // allium/cinnamon/canned probes below — sees the folded spelling too.
  final cleaned = foldDiacritics(
    ingredientText.toLowerCase(),
  ).replaceAll(_dashes, ' ');
  // "clove" is both a garlic measure ("2 cloves garlic") and a spice ("ground
  // cloves"). Drop it as a measure only when an allium shares the phrase.
  final alliumPresent = _allium.hasMatch(cleaned);
  // "stick" is likewise both a measure ("1 stick butter") and identity next
  // to cinnamon ("2 cinnamon sticks" — the whole quill, a different vocab row
  // from ground cinnamon).
  final cinnamonPresent = _cinnamon.hasMatch(cleaned);
  // "diced"/"chopped" are prep everywhere except in a canned phrase, where
  // they name the product (see [_cannedCutWords]).
  final cannedPresent = _canned.hasMatch(cleaned);

  final nouns = <String>[];
  final states = <String>[];
  // Comma modifiers are identity only if they're a state word ("…, boneless");
  // a prep modifier ("…, diced") drops out entirely — same classifier, so the
  // head and its modifiers are treated alike.
  for (final segment in cleaned.split(',')) {
    _classify(
      segment,
      nouns: nouns,
      states: states,
      alliumPresent: alliumPresent,
      cinnamonPresent: cinnamonPresent,
      cannedPresent: cannedPresent,
    );
  }

  return [
    ...nouns,
    ...states,
  ].map(_singularize).where((w) => w.isNotEmpty).join(' ');
}

/// Sorts one segment's words into identity nouns vs trailing state words.
void _classify(
  String segment, {
  required List<String> nouns,
  required List<String> states,
  required bool alliumPresent,
  required bool cinnamonPresent,
  required bool cannedPresent,
}) {
  for (final raw in segment.split(_whitespace)) {
    final word = raw.replaceAll(_punctuation, '');
    if (word.isEmpty) continue;
    if (_quantity.hasMatch(word) || _fusedAmount.hasMatch(word)) continue;
    if (word == 'clove' || word == 'cloves') {
      if (alliumPresent) continue; // the garlic-clove measure
      nouns.add(word); // the spice
      continue;
    }
    if ((word == 'stick' || word == 'sticks') && cinnamonPresent) {
      nouns.add(word); // the cinnamon quill — identity, not a measure
      continue;
    }
    // The cut of a canned tomato is the product, not a prep instruction. It
    // trails like any other state word, so "canned diced tomatoes" and "diced
    // tomatoes, canned" land together.
    if (cannedPresent && _cannedCutWords.contains(word)) {
      states.add(word);
      continue;
    }
    if (_filler.contains(word) ||
        _measures.contains(word) ||
        _sizes.contains(word) ||
        _prepAdverbs.contains(word) ||
        _prepVerbs.contains(word)) {
      continue;
    }
    // Fold last, so the synonym is classified as the word it folds ONTO: this
    // is what puts "tinned" in the trailing state run rather than leaving it
    // leading the nouns.
    final identity = _synonyms[word] ?? word;
    if (_stateWords.contains(identity)) {
      states.add(identity);
    } else {
      nouns.add(identity);
    }
  }
}

final _looksSingular = RegExp(r'(ss|us|is|ous)$');
final _ies = RegExp(r'ies$');
final _sibilantEs = RegExp(r'(ch|sh|x|z|s)es$');
final _oes = RegExp(r'oes$');

/// The normalizer's own singularization, exposed for the search seam.
///
/// `match_text` is singularized ("Almonds" → `almond`) while a search query
/// deliberately is not ([normalizeSearchQuery] mirrors the character rules
/// only, because a query is an in-flight prefix). A query token therefore has
/// to be tried in this form too, or a plural query could never word-prefix the
/// very row it names — see [matchTextForms].
///
/// A thin wrapper on purpose: [_singularize] is half of the shared-vector port
/// of `normalize.ts` and its rules belong to that mirror, not to search.
String singularizeToken(String word) => _singularize(word);

/// The forms of an already-normalized query [token] that may legitimately
/// word-prefix a phrase-normalized `match_text`: the token as typed, plus its
/// singular when [singularizeToken] changes it.
///
/// Both forms derive from a [normalizeSearchQuery]-normalized token, and
/// singularization only ever drops or rewrites trailing letters — so the
/// `%`/`_`-stripping guarantee survives: neither form can carry a LIKE
/// wildcard.
List<String> matchTextForms(String token) {
  final singular = singularizeToken(token);
  return singular == token ? [token] : [token, singular];
}

/// English singularization, conservative enough to leave non-plurals alone.
String _singularize(String word) {
  if (_invariantWords.contains(word)) return word;
  final irregular = _irregularPlurals[word];
  if (irregular != null) return irregular;
  // Words that look plural but aren't: boneless, asparagus, hummus, … A word
  // this guard cannot see (molasses: `-sses`) belongs in [_invariantWords].
  if (_looksSingular.hasMatch(word)) return word;
  if (_ies.hasMatch(word) && word.length > 4) {
    return '${word.substring(0, word.length - 3)}y';
  }
  // No general -ves→-f rule: most food -ves are plain -s plurals
  // (chives→chive, olives→olive). The genuine -ves→-f words are in
  // [_irregularPlurals]; falling through to -s handles the rest.
  if (_sibilantEs.hasMatch(word) || _oes.hasMatch(word)) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s')) return word.substring(0, word.length - 1);
  return word;
}
