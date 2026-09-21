/// The phrase-level ingredient normalizer. Pure Dart.
///
/// A port of `supabase/functions/_shared/normalize.ts`, which stays
/// authoritative for the server. The shared vectors in
/// `test/features/ingredients/normalize_vectors.json` pin the two together:
/// change one, change both, and extend the vectors.
///
/// In order, it: 1. lowercases, turns hyphens into word breaks and folds Latin
/// diacritics; 2. splits trailing comma modifiers off the head; 3. drops
/// non-identity words: quantities (fused ones like "400g" too), filler,
/// measures, sizes, prep adverbs and prep verbs; 4. keeps state words that
/// change identity (fresh, ground, canned) and moves them after the noun,
/// folding British forms first (tinned → canned); 5. singularizes what remains.
///
/// Never move a word into a strip set to make one match work: "ground ginger"
/// is not "fresh ginger". [displayWords] reads the same classes to pick the
/// words a person should still see.
library;

import '../../../core/search/search_query.dart'
    show foldDiacritics, normalizeSearchQuery;

/// Articles and filler words carrying no identity.
const _filler = {'a', 'an', 'the', 'of', 'or', 'and', 'desired'};

/// Container / measure / vague-amount words — quantity, not identity.
const _measures = {
  // Standard cooking units, stripped here for when they appear mid-phrase
  // ("heaping tablespoon nutritional yeast").
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

/// Prep verbs that describe handling, never identity. "ground" changes identity
/// and lives in [_stateWords].
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

/// Cut words that are prep everywhere except inside a canned phrase, where they
/// name the product: canned diced tomatoes are a different product from canned
/// crushed. Outside a canned phrase "2 diced tomatoes" is still `tomato`.
///
/// "crushed" is absent on purpose (see `normalize.ts`): it already holds the
/// generic `tomato canned` key, so adding it would re-key that row.
const _cannedCutWords = {'chopped', 'diced'};

/// State words that change identity. Kept, and moved to the end so the noun
/// leads.
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

/// Singular words the suffix rules would mangle and the [_looksSingular] guard
/// cannot see ("molasses" → `molass`).
///
/// Add a word only when it is singular and the rules produce a non-word for it.
/// Adding one changes what is stored: pair it with a migration that rewrites
/// the old form (`0022_singularize_invariants.sql` is the model), mirror it in
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

/// An amount fused to its unit in one token: "400g", "1.5kg", "½oz". Only the
/// unambiguous mass/volume abbreviations; a longer suffix would eat real words.
final _fusedAmount = RegExp(
  '^[0-9$_fractionGlyphs/.,\\-–—]+(g|kg|ml|l|oz|lb)\$',
);

/// British surface forms folded onto the word the vocabulary stores, so "tinned
/// chickpeas" keys as `chickpea canned`.
///
/// Adding a word changes what is stored: pair it with a migration
/// (`0031_tinned_is_canned.sql` is the model), mirror it in `normalize.ts`, and
/// extend the shared vectors.
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
/// doc). Deterministic and pure.
///
/// Every locally authored vocab row's `match_text` must be written with this so
/// the server's cascade can find it. Use [normalizeSearchQuery] for an
/// in-flight search prefix, which must not be singularized or reordered.
String normalizeMatchText(String ingredientText) {
  final cleaned = _fold(ingredientText);
  final phrase = _PhraseContext.of(cleaned);

  final nouns = <String>[];
  final states = <String>[];
  // A comma modifier is identity only if it is a state word ("…, boneless"); a
  // prep modifier ("…, diced") drops out.
  for (final segment in cleaned.split(',')) {
    for (final raw in segment.split(_whitespace)) {
      final word = raw.replaceAll(_punctuation, '');
      if (word.isEmpty) continue;
      final wordClass = phrase.classify(word);
      if (wordClass == _WordClass.drop) continue;
      // Fold first, so "tinned" lands in the trailing state run as "canned".
      final identity = _synonyms[word] ?? word;
      (wordClass == _WordClass.state ? states : nouns).add(identity);
    }
  }

  return [
    ...nouns,
    ...states,
  ].map(_singularize).where((w) => w.isNotEmpty).join(' ');
}

/// The words of [phrase] a person should still see, as typed and in order.
///
/// Keeps every word [normalizeMatchText] keeps as identity, plus a [_filler]
/// word standing between two of them ("cream of tartar"). A word is a
/// whitespace-separated token and survives when any hyphenated part carries
/// identity, so a compound is kept or dropped whole.
List<String> displayWords(String phrase) {
  final context = _PhraseContext.of(_fold(phrase));
  final tokens = [
    for (final token in phrase.trim().split(_whitespace))
      if (token.isNotEmpty) token,
  ];
  final classes = [for (final t in tokens) _tokenClass(t, context)];
  final first = classes.indexOf(_TokenClass.identity);
  if (first < 0) return const [];
  final last = classes.lastIndexOf(_TokenClass.identity);
  return [
    for (var i = first; i <= last; i++)
      if (classes[i] != _TokenClass.drop) tokens[i],
  ];
}

/// What one whitespace token of a phrase is worth to a display name.
enum _TokenClass { identity, connective, drop }

_TokenClass _tokenClass(String token, _PhraseContext context) {
  var connective = false;
  for (final part in _fold(token).split(_whitespace)) {
    final word = part.replaceAll(_punctuation, '');
    if (word.isEmpty) continue;
    if (context.classify(word) != _WordClass.drop) return _TokenClass.identity;
    if (_filler.contains(word)) connective = true;
  }
  return connective ? _TokenClass.connective : _TokenClass.drop;
}

/// Hyphens become word breaks so compounds tokenize ("all-purpose"). Diacritics
/// fold here so every downstream probe sees the folded spelling.
String _fold(String text) =>
    foldDiacritics(text.toLowerCase()).replaceAll(_dashes, ' ');

/// What one word contributes to a phrase: nothing, the identity noun run, or
/// the trailing state run.
enum _WordClass { drop, noun, state }

/// The three carve-outs whose verdict depends on a noun sharing the phrase, so
/// they are decided once for the whole phrase rather than per word.
class _PhraseContext {
  const _PhraseContext({
    required this.allium,
    required this.cinnamon,
    required this.canned,
  });

  /// [cleaned] must already be folded by [_fold].
  factory _PhraseContext.of(String cleaned) => _PhraseContext(
    allium: _allium.hasMatch(cleaned),
    cinnamon: _cinnamon.hasMatch(cleaned),
    canned: _canned.hasMatch(cleaned),
  );

  /// "clove" is both a garlic measure ("2 cloves garlic") and a spice ("ground
  /// cloves").
  final bool allium;

  /// "stick" is a measure ("1 stick butter") but identity next to cinnamon ("2
  /// cinnamon sticks").
  final bool cinnamon;

  /// Whether [_cannedCutWords] name the product rather than the prep.
  final bool canned;

  /// [word] must be folded and stripped of [_punctuation].
  _WordClass classify(String word) {
    if (_quantity.hasMatch(word) || _fusedAmount.hasMatch(word)) {
      return _WordClass.drop;
    }
    if (word == 'clove' || word == 'cloves') {
      return allium ? _WordClass.drop : _WordClass.noun;
    }
    if ((word == 'stick' || word == 'sticks') && cinnamon) {
      return _WordClass.noun;
    }
    // The cut of a canned tomato is the product, and trails like any other
    // state word.
    if (canned && _cannedCutWords.contains(word)) return _WordClass.state;
    if (_filler.contains(word) ||
        _measures.contains(word) ||
        _sizes.contains(word) ||
        _prepAdverbs.contains(word) ||
        _prepVerbs.contains(word)) {
      return _WordClass.drop;
    }
    return _stateWords.contains(_synonyms[word] ?? word)
        ? _WordClass.state
        : _WordClass.noun;
  }
}

final _looksSingular = RegExp(r'(ss|us|is|ous)$');
final _ies = RegExp(r'ies$');
final _sibilantEs = RegExp(r'(ch|sh|x|z|s)es$');
final _oes = RegExp(r'oes$');

/// The normalizer's singularization, exposed for search. `match_text` is
/// singularized and a search query is not, so a query token is also tried in
/// this form; see [matchTextForms].
String singularizeToken(String word) => _singularize(word);

/// The forms of a normalized query [token] that may word-prefix a `match_text`:
/// the token as typed, plus its singular when that differs. Neither form can
/// carry a LIKE wildcard.
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
  // No general -ves→-f rule: most food -ves are plain -s plurals (chives,
  // olives). The genuine ones are in [_irregularPlurals].
  if (_sibilantEs.hasMatch(word) || _oes.hasMatch(word)) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s')) return word.substring(0, word.length - 1);
  return word;
}
