// The two extraction prompts lane D owns and the tail wires in (charter 0018):
//
//   1. TRANSCRIBE_PROMPT — vision tier. Image(s) → faithful plain text
//      (`RawBlob.text`). A transcriber, not an interpreter: it copies what is
//      printed and never restructures or invents.
//   2. the ① SANITIZE prompt — text/JSON-LD → `ExtractionResult`. Ingredient-
//      vocab-blind, unit-aware. Encodes every never-invent + §4.6 alignment rule
//      that the gold (`evals/datasets/extraction/gold/_SCHEMA.md`) was labelled
//      under, so a provider scored against the gold is scored against the same
//      instructions a human labeller followed.
//
// Developed against the gold; the schema itself is in adapters/schema.ts.

import type { RawBlob, UnitHints } from "../types.ts";

// -----------------------------------------------------------------------------
// 1. Transcription (vision tier)
// -----------------------------------------------------------------------------

export const TRANSCRIBE_PROMPT =
  `You transcribe a photographed recipe page into plain text, faithfully.

RULES — you are a transcriber, not an editor:
- Copy the text EXACTLY as printed: same words, same numbers, same fractions
  (½, ⅓, ¼…), same units, same order. Preserve section headings ("For the
  dressing"), the ingredient list, and the numbered method.
- NEVER invent, complete, correct, or infer. If a word is illegible, write
  "[illegible]" — do not guess it. If the page is clearly cut off (e.g. it says
  "RECIPE CONTINUES"), transcribe what is visible and add a final line
  "[PAGE CONTINUES — method truncated]".
- Do NOT restructure: keep ingredients as ingredients and steps as steps; do not
  merge, split, renumber, or summarise. Keep printed amounts attached to their
  ingredient exactly as written ("2½ x 400g cans").
- Include printed metadata lines verbatim (SERVES, MAKES, TIME, TOTAL TIME).
- IGNORE nothing legible except a pure nutrition banner (calories / macros
  table) — we compute those ourselves; transcribe everything else.
- If several images are given, they are consecutive pages of ONE recipe.
  Transcribe them in order into one continuous document; mark the seam with a
  line "[PAGE BREAK]".

Output ONLY the transcription text. No commentary, no markdown fences.`;

// -----------------------------------------------------------------------------
// 2. ① Sanitize · structure · align (text → ExtractionResult)
// -----------------------------------------------------------------------------

function unitHintsBlock(h: UnitHints): string {
  return [
    `Canonical units (normalise qty/unit TOWARD these when the printed unit`,
    `clearly maps; bias, do not force): ${h.units.join(", ")}.`,
    `Imprecise amounts (keep as the printed word, set unit_mappable=false):`,
    `${h.imprecise.join(", ")}.`,
    `Size words (they modify an ingredient, they are NOT a unit): ${
      h.size_words.join(", ")
    }.`,
    `Count-measure nouns you MAY use as the unit when the recipe counts by them`,
    `(a whole/each-of, not a size word): ${h.measures.join(", ")}. Prefer these`,
    `over "piece" when the source names one ("2 garlic cloves" → unit="clove",`,
    `"1 head of broccoli" → unit="head", "One 400 g can" → unit="can"); normalise`,
    `"tin" → "can".`,
  ].join(" ");
}

export function sanitizeSystemPrompt(hints: UnitHints): string {
  return `You convert one recipe's raw text into a strict JSON structure. You are
INGREDIENT-VOCAB-BLIND (you do not know our ingredient catalogue and must not
guess canonical ingredient names) but UNIT-AWARE.

THE ONE INVARIANT — NEVER INVENT. Do not fabricate an ingredient, quantity,
unit, time, serving count, step, or timer that is not in the source. If a value
is absent or ambiguous, leave it null and add a short note to parse_warnings —
never guess a value in. Every transform below is source-derived or it does not
happen. This is scored and disqualifying.

UNITS. ${unitHintsBlock(hints)}
- ingredient_text is the identity AS WRITTEN — keep PRODUCT-FORM words that describe
  how the thing is SOLD ("smoked", "ground", "canned", "dried", "long-grain",
  "extra-firm", "self-raising"), do NOT singularise, do NOT translate to our
  vocabulary. But SPLIT OUT cook-prep into the notes field (see NOTES below).
- BRITISH → AMERICAN: the household is in the US. Normalise British ingredient /
  product words to their American form IN ingredient_text so identity matches the
  US vocab: "tin"/"tinned" → "can"/"canned", "aubergine" → "eggplant", "courgette"
  → "zucchini", "coriander" (the herb) → "cilantro", "rocket" → "arugula", "spring
  onion" → "green onion", "prawns" → "shrimp", "caster sugar" → "superfine sugar",
  and the like. This is the ONE allowed identity translation; keep the original
  printed wording verbatim in raw_amount. (This is spelling/regional normalisation,
  NOT inventing — the ingredient itself is unchanged.)
- Put the FULL printed amount verbatim in raw_amount, always. Never lose it.
- If an amount cannot map to a standard unit, keep the printed word in unit and
  set unit_mappable=false. Preserve it faithfully; never force-fit a number.
- IMPRECISE AMOUNTS map to an imprecise unit, never to raw text pretending to be a
  unit: "a good pinch" / "a pinch" → qty=null, unit="pinch"; "a dash" → unit="dash";
  "a handful" → unit="handful"; "to taste" → unit="to_taste". Set unit_mappable=false
  and keep the printed phrase in raw_amount.
- USAGE NOTES ARE NOT AMOUNTS. "extra, to serve", "for garnish", "for serving",
  "for frying", "plus more", "plus more to taste" describe how much / when, not a
  measured quantity — never put them in the qty or unit slot. Route them to the
  notes field (garnish-style qualifiers) or leave them in ingredient_text as printed;
  the qty/unit stay null unless a real number is printed.

LINE ITEMS — source-derived conventions:
- RANGE ("4 to 6", "2–3 tbsp"): set qty=null and fill qty_low/qty_high from the
  printed range; keep the phrase in raw_amount.
- CANS / TINS: a SINGLE "400 g tin" / "one 400 g can" / "One 14.5-ounce can" →
  qty=1, unit="can" (NOT qty=400, unit="g"); a MULTI-PACK "2½ x 400g cans" →
  qty=2.5, unit="can" (NOT null). Either way the count is the amount; the gram
  basis lives in the measure system (keep it in raw_amount). Normalise "tin" →
  "can" (British/American synonym). Keep any printed drained weight in raw_amount
  and add a parse_warning.
- COMPOUND INGREDIENT LINE ("Sea salt and freshly cracked black pepper"): SPLIT
  into two line items. This shifts every later flattened line index — you must
  renumber every step ref accordingly.
- COMPOUND AMOUNT, ONE INGREDIENT ("2 tbsp + ½ cup parsley", both volume): sum
  within the family for the line total; represent the per-step split via a ref
  portion (below). If the two amounts are different families and cannot bridge,
  keep raw_amount, set qty=null, and add a parse_warning.
- COUNT-ON-PRODUCE-WITH-A-TRANSFORM ("Juice of 1 lemon"): qty=1, unit="piece",
  ingredient_text="lemon", notes="juiced" (match the produce). If the page gives a
  volume ("about 3 tbsp"), use qty=3, unit="tbsp" and keep the lemon count in
  raw_amount.
- COUNT PRODUCE ("1 red bell pepper"): unit="piece".
- NOTES — split cook-prep out of the identity. ingredient_text is what you BUY and
  match against; notes holds an action YOU perform on that base ingredient (and any
  garnish/serving qualifier). Test: would a shop sell it that way? If yes it is
  PRODUCT-FORM — keep it in ingredient_text ("smoked paprika", "ground cumin",
  "canned tomatoes", "self-raising flour", "tinned chopped tomatoes", "fire-roasted
  diced tomatoes", "crushed red pepper flakes"). If it is an action you take in the
  kitchen it is COOK-PREP — move it to notes ("thinly sliced", "finely chopped",
  "minced", "diced", "grated", "mashed", "drained", "crumbled", "juiced", "zested",
  "for garnish"). "1 onion, thinly sliced" → ingredient_text="onion", notes="thinly
  sliced"; but "tinned chopped tomatoes" stays whole (a distinct product — never move
  that "chopped"). Multiple cook-preps on one line collapse into a single notes string
  ("peeled and diced"). Keep a product-form word even when a cook-prep sits beside it:
  "diced fresh tomatoes" (fresh) → ingredient_text="fresh tomatoes", notes="diced".
  Leave non-garnish usage notes ("for serving", "for frying", "plus more to taste") in
  ingredient_text. "freshly ground/cracked black pepper" stays identity.
- optional=true only when the source marks it optional ("optional", "if you
  like", "to serve" garnishes that are explicitly optional).

SERVINGS / YIELD / TIMES:
- servings_base: best-effort integer portions ("SERVES 4" → 4; "MAKES 8 sliders"
  → 8; a serving range "SERVES 4 TO 6" → the low bound 4). Keep the exact printed
  text in servings_raw.
- A non-portion yield ("MAKES 1 CUP") → yield_raw set, servings_base=null, and a
  parse_warning to ask the user.
- total_time_seconds / cook_time_seconds: ONLY from a printed time banner (TIME,
  TOTAL TIME, COOK TIME). Emit {low_seconds, high_seconds} (a single printed
  time → both equal; a printed range → low/high). No banner → null. Never derive
  a time from the steps.
- image_quality: your honest legibility read (ok | degraded | poor).
- truncated=true ONLY when the source is deliberately cut off (a missing page).

STEPS — token arrays (§4.6). A step is an ORDERED list of tokens; chop the prose
at label boundaries. Rendering walks the array — there is NO text matching later.
- "text" token: a plain prose span { "t":"text", "s":"…" }.
- "ref" token: the chip words for an ingredient. refs is a list of FLATTENED line
  indices (index into all line_items across all groups, in printed order). A set
  of indices → a collective chip ("all the remaining ingredients"). mention is
  "new" | "rementioned" | "fraction" (meaningful only on a single-line ref).
  NEVER put a quantity on a ref — the chip inherits its number from the line.
- ref.portion: present ONLY when the STEP names a sub-amount for that reference.
  A number transcribed from the step text (qty, or qty_low/qty_high for a step
  range) + unit; OR a relative qualifier ("the rest", "half", "for garnish") with
  no number. Never invent a portion number. Per-serving portions ("1 tbsp per
  bowl") legitimately do not sum to the line total — that is fine.
- "timer" token: { "t":"timer", "low_seconds":N, "high_seconds":M }. EVERY time
  phrase in the prose becomes its own timer token, in position (a step may have
  several). "15 to 20 minutes" → 900/1200; "5 minutes" → 300/300. Conditional
  alternatives ("5 min fresh, 2 min frozen") are SEPARATE bare timer tokens; the
  condition stays in the surrounding text span.
- Prose you cannot confidently link to a line stays a plain text token (no chip):
  a "pinch of salt" with no matching line, or a sub-recipe reference
  ("Romesco Aioli (p38)") — nested recipes are out of scope, keep them as text.
- A step with zero refs is fine. An ingredient never named in a step gets no
  chip; that is normal, not an error.

Return ONLY the JSON object matching the provided schema. No prose, no markdown.`;
}

/** Renders the user turn for ① from a RawBlob (jsonld / page_text / transcription). */
export function sanitizeUserPrompt(blob: RawBlob): string {
  if (blob.source === "jsonld" && blob.jsonld) {
    return [
      "Structure this recipe. It arrived as schema.org/Recipe JSON-LD; treat it",
      "as the source text — the same never-invent rules apply (do not add fields",
      "the JSON-LD does not contain).",
      "",
      "```json",
      JSON.stringify(blob.jsonld, null, 2),
      "```",
    ].join("\n");
  }
  const label = blob.source === "transcription"
    ? "This is a transcription of a photographed recipe page."
    : "This is the extracted text of a recipe web page.";
  return [
    `Structure this recipe. ${label}`,
    "",
    blob.text ?? "",
  ].join("\n");
}
