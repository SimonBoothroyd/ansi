// Ingredient-text normalization (docs/product-specs/import-and-matching.md §7).
//
// Turns a raw ingredient string into its `match_text`. This is the one shared
// normalizer: the import cascade (match.ts), the row writer and the seed
// pipeline all call it, on both the incoming line and the stored name. Pure
// and deterministic.
//
// In order:
//   1. lowercase, and fold Latin diacritics ("Jalapeño" -> "jalapeno").
//   2. split the trailing comma modifier(s) off the head.
//   3. drop non-identity words: quantities (including a fused "400g"),
//      filler, measures/containers, sizes, prep adverbs and prep verbs.
//   4. keep form/state words that change identity (fresh, ground, canned) and
//      move them after the noun: "fresh ginger" -> "ginger fresh". British
//      forms fold first (tinned -> canned).
//   5. singularize the remaining nouns.
//
// Never add a form/state word to a strip set to make a match work: "ground
// ginger" is not "fresh ginger".

/** Articles and filler words carrying no identity. */
const FILLER = new Set(["a", "an", "the", "of", "or", "and", "desired"]);

/** Container, measure and vague-amount words: quantity, not identity. */
const MEASURES = new Set([
  // Standard cooking units, for when they appear mid-phrase.
  "teaspoon",
  "teaspoons",
  "tsp",
  "tablespoon",
  "tablespoons",
  "tbsp",
  "tbs",
  "cup",
  "cups",
  "gram",
  "grams",
  "g",
  "kg",
  "kilogram",
  "kilograms",
  "ounce",
  "ounces",
  "oz",
  "pound",
  "pounds",
  "lb",
  "lbs",
  "ml",
  "milliliter",
  "milliliters",
  "millilitre",
  "millilitres",
  "liter",
  "liters",
  "litre",
  "litres",
  "l",
  "quart",
  "quarts",
  "pint",
  "pints",
  "gallon",
  "gallons",
  "fl",
  "fluid",
  "can",
  "cans",
  "tin",
  "tins",
  "jar",
  "jars",
  "bottle",
  "bottles",
  "package",
  "packages",
  "packet",
  "packets",
  "box",
  "boxes",
  "bag",
  "bags",
  "bunch",
  "bunches",
  "handful",
  "handfuls",
  "pinch",
  "pinches",
  "dash",
  "dashes",
  "sprig",
  "sprigs",
  "stick",
  "sticks",
  "head",
  "heads",
  "drop",
  "drops",
  "piece",
  "pieces",
  "slices",
  "few",
  "crack",
  "cracks",
  "splash",
  "dollop",
  "knob",
  "glug",
  "sprinkle",
  "drizzle",
  "pack",
  "packs",
  "block",
  "blocks",
  "batch",
  "batches",
  "spoonful",
  "spoonfuls",
]);

/** Size adjectives. "extra" is absent: it is identity in "extra virgin". */
const SIZES = new Set(["large", "small", "medium", "big", "tiny"]);

/** Prep adverbs that only ever modify a prep verb. */
const PREP_ADVERBS = new Set([
  "finely",
  "roughly",
  "thinly",
  "coarsely",
  "freshly",
  "heaping",
  "scant",
  "rounded",
  "generous",
  "packed",
  "drizzling",
  "very",
]);

/**
 * Prep verbs (past participles) that describe handling, never identity.
 * "ground" is absent: it changes identity and lives in {@link STATE_WORDS}.
 */
const PREP_VERBS = new Set([
  "chopped",
  "diced",
  "minced",
  "sliced",
  "grated",
  "shredded",
  "crushed",
  "peeled",
  "cubed",
  "julienned",
  "halved",
  "quartered",
  "trimmed",
  "beaten",
  "melted",
  "drained",
  "rinsed",
  "deseeded",
  "seeded",
  "pitted",
  "cored",
  "mashed",
  "crumbled",
  "softened",
  "cut",
  "torn",
]);

/**
 * Cut words that are prep everywhere except inside a canned/tinned phrase,
 * where they name the product: canned diced and canned crushed tomatoes are
 * different products (evals/datasets/extraction/gold/_SCHEMA.md). Outside a
 * canned phrase "2 diced tomatoes" is still `tomato`.
 *
 * "crushed" is absent: `Canned Crushed Tomatoes` holds the generic
 * `tomato canned` key, so adding it re-keys that row. That needs the row
 * renamed, the household re-exported and the seed regenerated (`gen_seed.ts`
 * asserts every stored match_text against this function).
 */
const CANNED_CUT_WORDS = new Set(["chopped", "diced"]);

/** The canned/tinned marker that turns a cut word into identity. */
const CANNED = /\b(canned|tinned)\b/;

/**
 * Form/state words that change identity (§7). Kept, and moved to the end so
 * the noun leads ("fresh ginger" → "ginger fresh").
 */
const STATE_WORDS = new Set([
  "fresh",
  "ground",
  "dried",
  "dry",
  "frozen",
  "canned",
  "smoked",
  "whole",
  "boneless",
  "skinless",
  "ripe",
  "unsalted",
  "salted",
  "raw",
  "toasted",
  "roasted",
  "powdered",
  "cooked",
  "uncooked",
  "shelled",
  "sweetened",
  "unsweetened",
]);

/** Purely a quantity token: digits, unicode fractions, ranges. */
const QUANTITY = /^[\d¼½¾⅓⅔⅕⅖⅗⅘⅙⅐⅛⅜⅝⅞/.,\-–—]+$/;

/**
 * An amount fused to its unit in one token: "400g", "1.5kg", "½oz". Without
 * this, "400g tin of black beans" keeps `400g` as a noun and matches nothing.
 * Only the unambiguous mass/volume abbreviations, so real words are not eaten.
 */
const FUSED_AMOUNT = /^[\d¼½¾⅓⅔⅕⅖⅗⅘⅙⅐⅛⅜⅝⅞/.,\-–—]+(?:g|kg|ml|l|oz|lb)$/;

/**
 * British surface forms folded onto the word the vocabulary stores, so
 * "tinned chickpeas" keys as `chickpea canned`.
 *
 * A word added here changes what is stored: pair it with a migration that
 * rewrites the old form in place (0031 is the model) and extend the shared
 * vectors.
 */
const SYNONYMS: Record<string, string> = { tinned: "canned" };

/**
 * Singular words the suffix rules would mangle and the regex guard below
 * (`-ss`, `-us`, `-is`, `-ous`) cannot see: "molasses" ends in `-sses`.
 *
 * A word goes in only when it is singular and the rules produce a non-word. A
 * word reduced to a real stem (grits → grit) stays out, since the query side
 * reduces it the same way. Adding a word changes what is stored: pair it with
 * a migration (0022 is the model) and extend the shared vectors.
 */
const INVARIANT_WORDS = new Set(["molasses"]);

/** Irregular plurals a suffix rule would get wrong. */
const IRREGULAR_PLURALS: Record<string, string> = {
  leaves: "leaf",
  loaves: "loaf",
  halves: "half",
  knives: "knife",
  chillies: "chilli",
  chilies: "chili",
};

/**
 * Drops parenthetical asides from a line's identity text, for the sub-recipe
 * tier: a printed component reads "Romesco Aioli (page 38)" and the recipe
 * title never carries the cross-reference.
 *
 * Not folded into {@link normalize}: the ingredient cascade must not move for
 * a feature that only suggests. Unbalanced brackets are left alone.
 */
export function stripParentheticals(text: string): string {
  // Collapse the whitespace an excised aside leaves, including before a comma.
  const tidy = (s: string) =>
    s.replace(/\s+/g, " ").replace(/\s+([,;.])/g, "$1").trim();
  let out = "";
  let depth = 0;
  for (const ch of text) {
    if (ch === "(") depth++;
    else if (ch === ")" && depth > 0) depth--;
    else if (depth === 0) out += ch;
  }
  // An unbalanced "(" would have eaten the tail: fall back to the original.
  if (depth !== 0) return tidy(text);
  return tidy(out);
}

/**
 * Folds Latin diacritics onto their base letter ("jalapeño" -> "jalapeno") by
 * canonical decomposition. Letters with none (æ ø ð þ ß đ ł œ) survive. The
 * Dart mirror, `foldDiacritics` in `app/lib/core/search/search_query.dart`,
 * tables the same set.
 */
export function foldDiacritics(text: string): string {
  return text.normalize("NFD").replace(/[\u0300-\u036f]/gu, "");
}

/** Normalizes a raw ingredient string to its `match_text` (see file header). */
export function normalize(ingredientText: string): string {
  // Hyphens are word breaks, so "all-purpose" tokenizes as two words.
  const cleaned = foldDiacritics(ingredientText.toLowerCase())
    .replace(/[-–—]/g, " ");
  // "clove" is a garlic measure and a spice. Drop it as a measure only when an
  // allium shares the phrase.
  const alliumPresent = /\b(garlic|shallots?|scallions?)\b/.test(cleaned);
  // "stick" is a measure ("1 stick butter") and identity next to cinnamon.
  // Keep it as the noun only when cinnamon shares the phrase.
  const cinnamonPresent = /\bcinnamon\b/.test(cleaned);
  // "diced"/"chopped" are prep everywhere except in a canned phrase, where
  // they name the product (see CANNED_CUT_WORDS).
  const cannedPresent = CANNED.test(cleaned);
  const [head, ...modifiers] = cleaned.split(",");

  const nouns: string[] = [];
  const states: string[] = [];
  classify(head, nouns, states, alliumPresent, cinnamonPresent, cannedPresent);
  // A comma modifier is identity only if it is a state word ("…, boneless").
  for (const mod of modifiers) {
    classify(mod, nouns, states, alliumPresent, cinnamonPresent, cannedPresent);
  }

  return [...nouns, ...states].map(singularize).filter(Boolean).join(" ");
}

/** Sorts one segment's words into identity nouns vs trailing state words. */
function classify(
  segment: string,
  nouns: string[],
  states: string[],
  alliumPresent: boolean,
  cinnamonPresent: boolean,
  cannedPresent: boolean,
): void {
  for (const raw of segment.split(/\s+/)) {
    // Keep any unicode letter or number; strip only punctuation. Fraction
    // glyphs are kept for the QUANTITY test.
    const word = raw.replace(/[^\p{L}\p{N}/¼½¾⅓⅔⅕⅖⅗⅘⅙⅐⅛⅜⅝⅞]/gu, "");
    if (!word) continue;
    if (QUANTITY.test(word) || FUSED_AMOUNT.test(word)) continue;
    if (word === "clove" || word === "cloves") {
      if (alliumPresent) continue; // garlic-clove measure
      nouns.push(word); // the spice
      continue;
    }
    if ((word === "stick" || word === "sticks") && cinnamonPresent) {
      nouns.push(word); // the cinnamon quill — identity, not a measure
      continue;
    }
    // The cut of a canned tomato is the product. It trails like a state word.
    if (cannedPresent && CANNED_CUT_WORDS.has(word)) {
      states.push(word);
      continue;
    }
    if (
      FILLER.has(word) || MEASURES.has(word) || SIZES.has(word) ||
      PREP_ADVERBS.has(word) || PREP_VERBS.has(word)
    ) continue;
    // Fold last, so the synonym is classified as the word it folds onto.
    const identity = SYNONYMS[word] ?? word;
    if (STATE_WORDS.has(identity)) states.push(identity);
    else nouns.push(identity);
  }
}

/** English singularization, conservative enough to leave non-plurals alone. */
function singularize(word: string): string {
  if (INVARIANT_WORDS.has(word)) return word;
  if (IRREGULAR_PLURALS[word]) return IRREGULAR_PLURALS[word];
  // Words that look plural but are not (boneless, asparagus). One this guard
  // cannot see belongs in INVARIANT_WORDS.
  if (/(ss|us|is|ous)$/.test(word)) return word;
  if (/ies$/.test(word) && word.length > 4) return word.slice(0, -3) + "y";
  // No general -ves→-f rule: most food -ves are plain -s plurals (olives). The
  // genuine ones (leaf, loaf, half, knife) are in IRREGULAR_PLURALS.
  if (/(ch|sh|x|z|s)es$/.test(word)) return word.slice(0, -2);
  if (/oes$/.test(word)) return word.slice(0, -2);
  if (/s$/.test(word)) return word.slice(0, -1);
  return word;
}
