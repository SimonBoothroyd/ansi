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
//   1. lowercase, and fold Latin diacritics onto their base letter
//      ("Jalapeño" -> "jalapeno"), so a line printed without its accents still
//      matches the row that has them (plan 0023 D5).
//   2. split the trailing comma modifier(s) off the head.
//   3. drop non-identity words: quantities (2, ½, 2–3) including an amount
//      fused to its unit (400g), articles/filler (a, of), measures/containers
//      (can, handful, clove), sizes (large), prep adverbs (finely) and prep
//      verbs (diced, grated) — none change what the thing IS.
//   4. KEEP form/state words that DO change identity (fresh, ground, canned,
//      boneless) and move them after the noun, so "fresh ginger" and "ginger,
//      fresh" both land on "ginger fresh". A British surface form folds onto
//      the one the vocabulary stores first (tinned -> canned).
//   5. singularize the remaining nouns (onions → onion, leaves → leaf).
//
// The own-goal §7 warns about is over-stripping: "ground ginger" ≠ "fresh
// ginger", "coconut milk" ≠ "coconut cream". Form/state words are kept for
// exactly this reason — never add one to a strip set to make a match work.

/** Articles and filler words carrying no identity. */
const FILLER = new Set(["a", "an", "the", "of", "or", "and", "desired"]);

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
  "very",
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
 * Cut words that are prep everywhere EXCEPT inside a canned/tinned phrase,
 * where they name the product on the shelf: a can of diced tomatoes and a can
 * of chopped tomatoes are the same SKU, and neither is a can of crushed. The
 * gold conventions already rule this — "Chopped/crushed/diced tomatoes
 * (tinned) are DIFFERENT PRODUCTS" (evals/datasets/extraction/gold/_SCHEMA.md)
 * — and the extraction prompt keeps the word in identity for exactly that
 * reason; this is the matcher catching up, so a canned line lands on the
 * product it names instead of flattening onto one shared row.
 *
 * Same shape as the `clove`/allium and `stick`/cinnamon carve-outs below: a
 * word whose class depends on a noun sharing the phrase. Outside a canned
 * phrase these stay prep — "2 diced tomatoes" is still `tomato`, the fresh
 * one.
 *
 * **"crushed" is deliberately absent.** It is the one cut word already acting
 * as identity: `Canned Crushed Tomatoes` holds the generic `tomato canned`
 * key today, and the seeded measures hang off that key. Adding "crushed" here
 * RE-KEYS that row, so it is a vocabulary move, not a normalizer tweak: the
 * row is renamed in the app, the household re-exported, and the seed
 * regenerated (`gen_seed.ts` asserts every stored match_text against this
 * function and fails naming both sides). Until someone makes that move
 * deliberately, the row keeps the generic slot it already owns.
 */
const CANNED_CUT_WORDS = new Set(["chopped", "diced"]);

/** The canned/tinned marker that turns a cut word into identity. */
const CANNED = /\b(canned|tinned)\b/;

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

/**
 * An amount fused to its unit in one token: "400g", "1.5kg", "½oz". MEASURES
 * lists the unit words bare, and QUANTITY needs the WHOLE token to be numeric,
 * so a printed "400g tin of black beans" used to keep `400g` as a noun and
 * matched nothing at all — the review card then offered a fresh stub for an
 * ingredient the vocabulary already had. Extraction normally splits the amount
 * off, but the same normalizer writes `match_text` for a name a person typed,
 * where nothing splits anything.
 *
 * Only the unambiguous mass/volume abbreviations: a bare "l" or "g" after a
 * number cannot be anything but a unit, while a longer suffix would start
 * eating real words.
 */
const FUSED_AMOUNT = /^[\d¼½¾⅓⅔⅕⅖⅗⅘⅙⅐⅛⅜⅝⅞/.,\-–—]+(?:g|kg|ml|l|oz|lb)$/;

/**
 * British surface forms folded onto the word the vocabulary stores. "tinned"
 * and "canned" name the same thing on the same shelf, but only "canned" is a
 * STATE_WORD — so "tinned chickpeas" used to key as `tinned chickpea`, a
 * leading noun nothing else produces, and missed `chickpea canned` by enough
 * to lose the auto band. Folding here makes the two phrasings land on one row
 * instead of asking every household to write the alias by hand.
 *
 * A word added here changes what is STORED: pair it with a migration that
 * rewrites the old form in place (0031 is the model) and extend the shared
 * vectors, exactly as the INVARIANT_WORDS rule below requires.
 */
const SYNONYMS: Record<string, string> = { tinned: "canned" };

/**
 * Singular words the suffix rules would mangle because they END like a
 * plural. The regex guard below (`-ss`, `-us`, `-is`, `-ous`) already spares
 * boneless, asparagus and hummus; this set is for the words it cannot see —
 * "molasses" ends in `-sses`, so the guard misses it and the sibilant rule
 * used to write `molass`.
 *
 * Admission rule: a word goes in only when it is genuinely singular AND the
 * rules produce a non-word for it. A word the rules reduce to a real stem
 * (grits → grit, brussels → brussel) stays out — the query side reduces it
 * the same way, so the stored key still matches — and would cost every
 * household a `match_text` rewrite for no gain. Adding a word here changes
 * what is stored: pair it with a migration that rewrites the old form in
 * place (0022 is the model) and extend the shared vectors.
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
 * Drops parenthetical asides from a line's identity text, leaving the rest of
 * the words untouched and single-spaced.
 *
 * This exists for the step-8.6 sub-recipe tier (exec plan 0021 D6): a printed
 * component reads `"Romesco Aioli (page 38)"`, and the cross-reference is
 * noise the household's recipe TITLE ("Romesco Aioli") will never carry. The
 * client already treats a parenthetical as prose rather than identity — a raw
 * amount's bracketed aside routes to the notes slot (`amount_text.dart`) — and
 * this is the same judgement on the identity side.
 *
 * Deliberately NOT folded into {@link normalize}: the ingredient cascade's
 * behaviour (and every gold/benchmark number built on it) must not move for a
 * feature that only ever produces a *suggestion*. A `(400 g)` on an ingredient
 * line still reaches `normalize` intact.
 *
 * Unbalanced brackets are left alone rather than guessed at, so a stray "(" in
 * the middle of a name can't swallow the rest of the line.
 */
export function stripParentheticals(text: string): string {
  // Collapse the whitespace an excised aside leaves behind, including the gap
  // it opens before a comma ("Garlic Butter (p. 17), melted").
  const tidy = (s: string) =>
    s.replace(/\s+/g, " ").replace(/\s+([,;.])/g, "$1").trim();
  let out = "";
  let depth = 0;
  for (const ch of text) {
    if (ch === "(") depth++;
    else if (ch === ")" && depth > 0) depth--;
    else if (depth === 0) out += ch;
  }
  // An unbalanced "(" leaves `depth > 0` and would have eaten the tail: fall
  // back to the original rather than truncating what the source printed.
  if (depth !== 0) return tidy(text);
  return tidy(out);
}

/**
 * Folds Latin diacritics onto their base letter ("jalapeño" -> "jalapeno").
 *
 * Canonical decomposition splits an accented letter into "base + combining
 * mark"; dropping the marks leaves the base. Letters with no canonical
 * decomposition (æ ø ð þ ß đ ł œ) are letters in their own right and
 * survive untouched. The Dart mirror tables the same set explicitly, because
 * Dart has no Unicode normalizer in its core library — see
 * `foldDiacritics` in `app/lib/features/ingredients/domain/search_query.dart`.
 */
export function foldDiacritics(text: string): string {
  return text.normalize("NFD").replace(/[\u0300-\u036f]/gu, "");
}

/** Normalizes a raw ingredient string to its `match_text` (see file header). */
export function normalize(ingredientText: string): string {
  // Hyphens join compound descriptors ("all-purpose", "extra-virgin"); treat
  // them as word breaks so the parts tokenize rather than fusing ("allpurpose").
  const cleaned = foldDiacritics(ingredientText.toLowerCase())
    .replace(/[-–—]/g, " ");
  // "clove" is both a garlic measure ("2 cloves garlic") and a spice ("ground
  // cloves"). Drop it as a measure only when an allium shares the phrase; else
  // it is the spice and must survive as the noun.
  const alliumPresent = /\b(garlic|shallots?|scallions?)\b/.test(cleaned);
  // "stick" is likewise both a measure ("1 stick butter") and identity next
  // to cinnamon ("2 cinnamon sticks" — the whole quill, a different vocab row
  // from ground cinnamon). Keep it as the noun only when cinnamon shares the
  // phrase; else it stays a measure and is dropped.
  const cinnamonPresent = /\bcinnamon\b/.test(cleaned);
  // "diced"/"chopped" are prep everywhere except in a canned phrase, where
  // they name the product (see CANNED_CUT_WORDS).
  const cannedPresent = CANNED.test(cleaned);
  const [head, ...modifiers] = cleaned.split(",");

  const nouns: string[] = [];
  const states: string[] = [];
  classify(head, nouns, states, alliumPresent, cinnamonPresent, cannedPresent);
  // Comma modifiers are identity only if they're a state word ("…, boneless");
  // a prep modifier ("…, diced") drops out entirely.
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
    // Keep any unicode letter/number — a non-Latin script survives whole, and
    // Latin accents were already folded onto their base letter above. Strip
    // only punctuation; fraction glyphs are kept for the QUANTITY test.
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
    // The cut of a canned tomato is the product, not a prep instruction. It
    // trails like any other state word, so "canned diced tomatoes" and "diced
    // tomatoes, canned" land together.
    if (cannedPresent && CANNED_CUT_WORDS.has(word)) {
      states.push(word);
      continue;
    }
    if (
      FILLER.has(word) || MEASURES.has(word) || SIZES.has(word) ||
      PREP_ADVERBS.has(word) || PREP_VERBS.has(word)
    ) continue;
    // Fold last, so the synonym is classified as the word it folds ONTO: this
    // is what puts "tinned" in the trailing state run rather than leaving it
    // leading the nouns.
    const identity = SYNONYMS[word] ?? word;
    if (STATE_WORDS.has(identity)) states.push(identity);
    else nouns.push(identity);
  }
}

/** English singularization, conservative enough to leave non-plurals alone. */
function singularize(word: string): string {
  if (INVARIANT_WORDS.has(word)) return word;
  if (IRREGULAR_PLURALS[word]) return IRREGULAR_PLURALS[word];
  // Words that look plural but aren't: boneless, asparagus, hummus, … A word
  // this guard cannot see (molasses: `-sses`) belongs in INVARIANT_WORDS.
  if (/(ss|us|is|ous)$/.test(word)) return word;
  if (/ies$/.test(word) && word.length > 4) return word.slice(0, -3) + "y";
  // No general -ves→-f rule: most food -ves are plain -s plurals (chives→chive,
  // olives→olive). The genuine -ves→-f words (leaf, loaf, half, knife) are in
  // IRREGULAR_PLURALS above; falling through to -s handles the rest.
  if (/(ch|sh|x|z|s)es$/.test(word)) return word.slice(0, -2);
  if (/oes$/.test(word)) return word.slice(0, -2);
  if (/s$/.test(word)) return word.slice(0, -1);
  return word;
}
