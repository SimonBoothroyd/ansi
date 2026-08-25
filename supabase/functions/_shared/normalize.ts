// Ingredient-text normalization (docs/product-specs/import-and-matching.md §7).
//
// Turns a raw ingredient string into its `match_text`: the canonical surface
// form the match cascade compares against. This is THE shared normalizer — the
// live import cascade (match.ts), the row writer (ingredient.match_text), and
// the offline batch seed pipeline all call it. Symmetric normalization — the
// same function on both the incoming line and the stored name — is what makes
// the cascade work, so there must be exactly one of these.
//
// It is deterministic and pure: no I/O, no model. Given the same string it
// always returns the same match_text.
//
// What it does, in order:
//   1. lowercase.
//   2. split the trailing comma modifier(s) off the head.
//   3. drop non-identity words: quantities (2, ½, 2–3), articles/filler (a, of),
//      measures/containers (can, handful, clove), sizes (large), prep adverbs
//      (finely) and prep verbs (diced, grated) — none change what the thing IS.
//   4. KEEP form/state words that DO change identity (fresh, ground, canned,
//      boneless) and move them after the noun, so "fresh ginger" and "ginger,
//      fresh" both land on "ginger fresh".
//   5. singularize the remaining nouns (onions → onion, leaves → leaf).
//
// The own-goal §7 warns about is over-stripping: "ground ginger" ≠ "fresh
// ginger", "coconut milk" ≠ "coconut cream". Form/state words are kept for
// exactly this reason — never add one to a strip set to make a match work.

/** Articles and filler words carrying no identity. */
const FILLER = new Set(["a", "an", "the", "of", "or", "and"]);

/** Container / measure / vague-amount words — quantity, not identity. */
const MEASURES = new Set([
  // standard cooking units (also parsed by the miner, but strip them here too
  // for when they appear mid-phrase, e.g. "heaping tablespoon nutritional yeast")
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
  "clove",
  "cloves",
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
]);

/** Size adjectives — they scale the amount, not the ingredient. */
// "extra" is intentionally absent: it changes identity in "extra virgin".
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
]);

/**
 * Prep verbs (past participles) that describe handling, never identity.
 * NOTE: "ground" is deliberately absent — it changes identity (ground vs fresh
 * ginger) and lives in {@link STATE_WORDS}.
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
 * Form/state words that DO change identity. Kept, and moved to the end so the
 * noun leads regardless of where the descriptor sat ("fresh ginger" → "ginger
 * fresh"). This is the §7 KEEP set — the guard against over-stripping.
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

/** Irregular plurals a suffix rule would get wrong. */
const IRREGULAR_PLURALS: Record<string, string> = {
  leaves: "leaf",
  loaves: "loaf",
  halves: "half",
  knives: "knife",
  chillies: "chilli",
  chilies: "chili",
};

/** Normalizes a raw ingredient string to its `match_text` (see file header). */
export function normalize(ingredientText: string): string {
  // Hyphens join compound descriptors ("all-purpose", "extra-virgin"); treat
  // them as word breaks so the parts tokenize rather than fusing ("allpurpose").
  const cleaned = ingredientText.toLowerCase().replace(/[-–—]/g, " ");
  const [head, ...modifiers] = cleaned.split(",");

  const nouns: string[] = [];
  const states: string[] = [];
  classify(head, nouns, states);
  // Comma modifiers are identity only if they're a state word ("…, boneless");
  // a prep modifier ("…, diced") drops out entirely.
  for (const mod of modifiers) classify(mod, nouns, states);

  return [...nouns, ...states].map(singularize).filter(Boolean).join(" ");
}

/** Sorts one segment's words into identity nouns vs trailing state words. */
function classify(segment: string, nouns: string[], states: string[]): void {
  for (const raw of segment.split(/\s+/)) {
    const word = raw.replace(/[^a-z0-9¼½¾⅓⅔⅕⅖⅗⅘⅙⅐⅛⅜⅝⅞/]/g, "");
    if (!word) continue;
    if (QUANTITY.test(word)) continue;
    if (
      FILLER.has(word) || MEASURES.has(word) || SIZES.has(word) ||
      PREP_ADVERBS.has(word) || PREP_VERBS.has(word)
    ) continue;
    if (STATE_WORDS.has(word)) states.push(word);
    else nouns.push(word);
  }
}

/** English singularization, conservative enough to leave non-plurals alone. */
function singularize(word: string): string {
  if (IRREGULAR_PLURALS[word]) return IRREGULAR_PLURALS[word];
  // Words that look plural but aren't: boneless, asparagus, molasses, …
  if (/(ss|us|is|ous)$/.test(word)) return word;
  if (/ies$/.test(word) && word.length > 4) return word.slice(0, -3) + "y";
  if (/ves$/.test(word)) return word.slice(0, -3) + "f";
  if (/(ch|sh|x|z|s)es$/.test(word)) return word.slice(0, -2);
  if (/oes$/.test(word)) return word.slice(0, -2);
  if (/s$/.test(word)) return word.slice(0, -1);
  return word;
}
