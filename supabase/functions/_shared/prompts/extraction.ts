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
    `(a whole/each-of, not a size word): ${
      h.measures.join(", ")
    }. Prefer these`,
    `over "piece" when the source names one ("2 garlic cloves" → unit="clove",`,
    `"1 head of broccoli" → unit="head", "One 400 g can" → unit="can"); normalise`,
    `"tin" → "can".`,
  ].join(" ");
}

const CLOSING =
  "Return ONLY the JSON object matching the provided schema. No prose, no markdown.";

/** Everything up to (not including) the STEPS rules — the line-extraction half. */
function headRules(hints: UnitHints): string {
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
- key: mint a short slug on EVERY line that names its food ("kale", "sea-salt",
  "garlic"), unique across the whole recipe (a repeated food gets a suffix:
  "sea-salt-2"). Step refs point at lines by COPYING these keys exactly — the
  key is the line's handle, so pick one you can re-type without thinking.
- RANGE ("4 to 6", "2–3 tbsp"): set qty=null and fill qty_low/qty_high from the
  printed range; keep the phrase in raw_amount.
- CANS / TINS: a SINGLE "400 g tin" / "one 400 g can" / "One 14.5-ounce can" →
  qty=1, unit="can" (NOT qty=400, unit="g"); a MULTI-PACK "2½ x 400g cans" →
  qty=2.5, unit="can" (NOT null). Either way the count is the amount; the gram
  basis lives in the measure system (keep it in raw_amount). Normalise "tin" →
  "can" (British/American synonym). Keep any printed drained weight in raw_amount
  and add a parse_warning.
- COMPOUND INGREDIENT LINE ("Sea salt and freshly cracked black pepper"): SPLIT
  into two line items, each with its own key.
- COMPOUND AMOUNT, ONE INGREDIENT ("2 tbsp + ½ cup parsley", both volume): sum
  within the family for the line total; represent the per-step split via a ref
  portion (below). If the two amounts are different families and cannot bridge,
  keep raw_amount, set qty=null, and add a parse_warning.
- COUNT-ON-PRODUCE-WITH-A-TRANSFORM ("Juice of 1 lemon"): the identity follows
  WHAT THE COOK WOULD BUY (owner ruling). When the recipe uses ONLY the juice of
  that fruit, the ingredient IS the juice — ingredient_text="lemon juice" /
  "lime juice", a bottled product: qty/unit from a printed volume when given
  ("about 3 tbsp" → qty=3, unit="tbsp"), else qty=null, unit=null,
  unit_mappable=false with the printed phrase kept in raw_amount. When the
  recipe ALSO uses the zest or the fruit itself (any line or step does), the
  fruit is what's bought — ingredient_text="lemon", qty=1, unit="piece", and
  the transforms in notes ("juiced", "zested").
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
- truncated=true ONLY when the source is deliberately cut off (a missing page).`;
}

/** The step-tokenization rules, shared by the one-shot and two-phase prompts. */
const STEPS_RULES =
  `STEPS — token arrays (§4.6). A step is an ORDERED list of tokens; chop the prose
at label boundaries. Rendering walks the array — there is NO text matching later.
- STEP SEGMENTATION is source-determined, never a style choice: one printed
  step = one step, exactly. The source's own separations (numbers, bullets,
  paragraph breaks) are the ONLY step boundaries. An unbroken method paragraph
  is ONE step, however many sentences it holds — never split it, and never
  merge separately printed steps.
- "text" token: a plain prose span { "t":"text", "s":"…" }.
- "ref" token: { "t":"ref", "refs":["<line key>",…], "label":"<the food's
  name>", "mention":…, "portion":… }. The chip words go in "label" — NEVER in
  "s" ("s" belongs to text tokens only) — and "label" is the complete noun
  phrase that NAMES the food, exactly as printed — every word that belongs to
  the name stays, whatever it is ("canned chopped tomatoes", "cream of
  tartar", "extra-firm tofu"). Only a leading determiner ("the", "a", "an",
  "some") is not part of the name: it stays in the text token BEFORE the chip,
  never inside the label and never dropped — "Add the kale" → text "Add the "
  + label "kale". Prep that the prose hangs off the name ("kale, shredded")
  likewise stays in text tokens. The name's words appear ONLY in the label,
  never duplicated in a text token. refs is a list of line KEYS — copy each
  key exactly as you minted it on the line; never invent, abbreviate, or
  re-spell a key. mention is
  "new" | "rementioned" | "fraction" (meaningful only on a single-line ref).
  NEVER put a quantity on a ref — the chip inherits its number from the line.
- REF RECALL IS THE JOB: every time step prose names an ingredient that appears
  in the line list, that mention MUST be a ref token — first use and every
  re-mention alike ("the kale", "reserved marinade", "remaining butter"). Before
  emitting a step, re-read its prose against the full line list and convert
  every match you can resolve; a mention left as plain text is a MISS, exactly
  as wrong as a fabricated line. A mention counts even when it shortens or
  renames the line: "salt" for "sea salt", "quinoa" for "cooked tricolour
  quinoa", "the sausage" for "Italian sausage links", and a derived rename —
  "the broth" for the water line it was made from — are all refs. So are
  garnish/serving re-mentions ("more parmesan, for serving" → ref with a
  relative portion). Only genuinely unresolvable prose stays text (the rule
  below). The inverse also holds: pronouns and implied subjects ("them", "it",
  "everything", an unstated subject) are NOT refs — chip only words that name
  the food.
- A multi-line ref is ONLY for an explicit collective phrase — "all of the
  ingredients", "the remaining sauce ingredients", "the onion mixture": ONE ref
  token whose label is the printed phrase and whose refs list every line it
  covers, never one chip per ingredient, and never plain text when the covered
  lines are unambiguous ("the remaining X" = every line of the named group not
  already used by earlier steps). A plain conjunction of separately listed
  foods ("salt and pepper", "oregano, thyme") is NOT a collective — emit one
  single-line ref per food, with the connecting words as text tokens between
  them.
- KEY ACCURACY: before finishing each step, confirm every ref's keys name
  exactly the lines you mean — a wrong key chips the wrong food onto the
  sentence.
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
  chip; that is normal, not an error.`;

/** The one-shot sanitize prompt (lines + steps in one call) — the gemini/gpt
 * benchmark adapters still use this; the Claude adapter now runs two-phase. */
export function sanitizeSystemPrompt(hints: UnitHints): string {
  return [headRules(hints), STEPS_RULES, CLOSING].join("\n\n");
}

/**
 * Phase 1 of the two-phase sanitize: LINES ONLY. Same rules as the one-shot
 * prompt minus step tokenization — steps are emitted as an empty array and a
 * second call writes them against the finished, keyed line list (the split
 * exists because step refs and collective membership need the WHOLE line list
 * in view, not a list still being written).
 */
export function linesSystemPrompt(hints: UnitHints): string {
  return [
    headRules(hints),
    "STEPS: emit an empty steps array ([]). The method is tokenized in a " +
    "second pass against your finished line list — your job here is the " +
    "lines, their keys, and the recipe fields.",
    CLOSING,
  ].join("\n\n");
}

/**
 * Phase 2 of the two-phase sanitize: STEPS ONLY, with the finished line list
 * (keys included) in the input. Emits { "steps": [...] } and nothing else.
 */
export function stepsSystemPrompt(): string {
  return [
    `You tokenize one recipe's METHOD into step token arrays. The recipe's
ingredient lines have already been extracted and are FINAL — they are given to
you with their keys. You never re-extract, add, or renumber lines; you write
steps that reference them by key.

THE ONE INVARIANT — NEVER INVENT. Do not fabricate a step, timer, or
ingredient reference that is not in the source prose. This is scored and
disqualifying.`,
    STEPS_RULES,
    `TWO-PHASE CONVENTIONS (the line list is in your input):
- refs: copy keys EXACTLY from the provided line list — never a key that is
  not on the list.
- label = the words AS PRINTED in the step prose, even when the line's name is
  longer: prose "garlic" stays label "garlic" though its line says "garlic
  cloves". The key does the matching; the label does the reading. A form-word
  the prose appends to the name ("kale leaves" for the kale line) may stay in
  the label only if printed that way.
- CHIP EACH USE: chip the mention where the food enters the action, and chip
  re-uses in LATER steps (mention "rementioned"). An immediate repeat of the
  same food within the same passage stays text — chip the FIRST naming.
- COLLECTIVES: "all the remaining ingredients" and kin are ONE ref token —
  walk the PROVIDED line list, work out exactly which lines remain unused, and
  list every one of their keys. The list is in front of you; enumerate it.`,
    CLOSING,
  ].join("\n\n");
}

/**
 * Chars of source material one prompt may carry. A recipe is a few thousand;
 * these are the ceiling that stops a hostile or broken page from being billed
 * in full. `jsonld.ts` caps page text at intake — this is the last line of
 * defence, and the only bound on a JSON-LD object (which arrives parsed, so its
 * serialized size is not otherwise checked).
 */
export const MAX_JSONLD_CHARS = 60_000;
/** Same, for a text blob (page text or a vision transcription). */
export const MAX_SOURCE_TEXT_CHARS = 120_000;

function cap(s: string, max: number): string {
  return s.length <= max ? s : `${s.slice(0, max)}\n…[source truncated]`;
}

/**
 * Phase-2 reference table: the finished line list rendered for the steps call.
 * Reads the RAW phase-1 JSON (uncoerced — tolerant of missing fields) so the
 * table shows exactly the keys the model minted.
 */
export function lineTableBlock(linesJson: unknown): string {
  const o = (linesJson ?? {}) as Record<string, unknown>;
  const rows: string[] = [];
  const groups = Array.isArray(o.groups) ? o.groups : [];
  for (const g of groups) {
    const gr = (g ?? {}) as Record<string, unknown>;
    if (typeof gr.name === "string" && gr.name.trim() !== "") {
      rows.push(`[group: ${gr.name}]`);
    }
    const items = Array.isArray(gr.line_items) ? gr.line_items : [];
    for (const li of items) {
      const l = (li ?? {}) as Record<string, unknown>;
      const amount = typeof l.raw_amount === "string" && l.raw_amount !== ""
        ? l.raw_amount
        : [l.qty, l.unit].filter((x) => x !== null && x !== undefined).join(
          " ",
        );
      rows.push(
        `- key=${String(l.key ?? "?")} | ${amount || "—"} | ${
          String(l.ingredient_text ?? "?")
        }`,
      );
    }
  }
  return rows.join("\n");
}

/** The user turn for phase 2: the keyed line table + the source method text. */
export function stepsUserPrompt(blob: RawBlob, linesJson: unknown): string {
  const label = blob.source === "transcription"
    ? "a transcription of a photographed recipe page"
    : blob.source === "jsonld"
    ? "a schema.org/Recipe JSON-LD extraction"
    : "the extracted text of a recipe web page";
  const source = blob.source === "jsonld" && blob.jsonld
    ? cap(JSON.stringify(blob.jsonld, null, 2), MAX_JSONLD_CHARS)
    : cap(blob.text ?? "", MAX_SOURCE_TEXT_CHARS);
  return [
    `Tokenize this recipe's method into steps. The source is ${label}.`,
    "",
    "FINAL LINE LIST (refs use these keys, verbatim):",
    lineTableBlock(linesJson),
    "",
    "SOURCE:",
    source,
  ].join("\n");
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
      cap(JSON.stringify(blob.jsonld, null, 2), MAX_JSONLD_CHARS),
      "```",
    ].join("\n");
  }
  const label = blob.source === "transcription"
    ? "This is a transcription of a photographed recipe page."
    : "This is the extracted text of a recipe web page.";
  return [
    `Structure this recipe. ${label}`,
    "",
    cap(blob.text ?? "", MAX_SOURCE_TEXT_CHARS),
  ].join("\n");
}
