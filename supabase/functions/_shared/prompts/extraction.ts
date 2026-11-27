// The two extraction prompts the eval harness measures and the edge function
// sends (charter 0018):
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
    `Size words (they modify an ingredient, they are NOT a unit; they stay in`,
    `ingredient_text with the food — "1 small shallot" → "small shallot", "2 fat`,
    `garlic cloves" → "fat garlic cloves"): ${h.size_words.join(", ")}, fat.`,
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
The line list is EXACTLY the printed ingredient list: a thing only the method
names (salt for the pasta pot, water to fill a can) is never added as a line.
A thing the list does print, water included, is a line like any other.

UNITS. ${unitHintsBlock(hints)}
- ingredient_text is the identity AS WRITTEN — keep PRODUCT-FORM words that describe
  how the thing is SOLD ("smoked", "ground", "canned", "dried", "long-grain",
  "extra-firm", "self-raising"), do NOT singularise, do NOT translate to our
  vocabulary. But SPLIT OUT cook-prep into the notes field (see NOTES below).
- BRITISH → AMERICAN: the household is in the US. Normalise British ingredient /
  product words to their American form IN ingredient_text so identity matches the
  US vocab: "tin"/"tinned" → "can"/"canned", "aubergine" → "eggplant", "courgette"
  → "zucchini", "coriander" (the herb) → "cilantro", "rocket" → "arugula", "spring
  onions" → "green onions", "prawns" → "shrimp", "caster sugar" → "superfine
  sugar", and the like (keep the printed number and form words: "spring
  onions" → "green onions", "Fresh coriander" → "fresh cilantro"). This is the
  ONE allowed identity translation; keep the original
  printed wording verbatim in raw_amount. (This is spelling/regional normalisation,
  NOT inventing — the ingredient itself is unchanged.)
  Steps keep the printed word ("courgette"); only ingredient_text is translated.
- Put the FULL printed amount verbatim in raw_amount, always. Never lose it.
- An amount printed in several systems ("200g (7oz/1 cup)") takes qty/unit
  from the FIRST one (200 g); the conversions stay only in raw_amount.
- If an amount cannot map to a standard unit, keep the printed word in unit and
  set unit_mappable=false. Preserve it faithfully; never force-fit a number.
- unit_mappable=true for every amount counted in "piece" or a count-measure
  noun ("1 red bell pepper", "½ red onion", "2 cloves", "Leaves from 4 sprigs"
  → 4 sprig, "½ loaf", "1 Italian Sausage (page 45)" → 1 piece) — all mappable.
  An imprecise word stays unit_mappable=false even with a number ("2 large
  handfuls" → qty=2, unit="handful", unit_mappable=false).
- A line printed with NO amount ("Sea salt", "black pepper", "Fresh coriander
  (optional)") → qty=null, unit=null, unit_mappable=false. Do not borrow "to
  taste" from the method; unit="to_taste" only when the LINE prints "to taste".
  A size phrase with no number ("Thumb-sized piece") is the same: unit=null.
- IMPRECISE AMOUNTS map to an imprecise unit, never to raw text pretending to be a
  unit: "a good pinch" / "a pinch" → qty=null, unit="pinch"; "a dash" → unit="dash";
  "a handful" → unit="handful"; "to taste" → unit="to_taste". Set unit_mappable=false
  and keep the printed phrase in raw_amount.
- USAGE NOTES ARE NOT AMOUNTS. "extra, to serve", "for garnish", "for serving",
  "for frying", "plus more", "plus more to taste" describe how much / when, not a
  measured quantity — never put them in the qty or unit slot. Route them to the
  notes field; the qty/unit stay null unless a real number is printed.

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
  within the family, exactly, into the larger unit for the line total (1 cup =
  16 tbsp, 1 tbsp = 3 tsp: "2 tbsp + ½ cup" → qty=0.625, unit="cup"); the
  per-step split lives in the step portions (below). If the two amounts are
  different families and cannot bridge,
  keep raw_amount, set qty=null, and add a parse_warning.
- COUNT-ON-PRODUCE-WITH-A-TRANSFORM ("Juice of 1 lemon"): the identity follows
  WHAT THE COOK WOULD BUY (owner ruling). When the recipe uses ONLY the juice of
  that fruit, the ingredient IS the juice — ingredient_text="lemon juice" /
  "lime juice", a bottled product: qty/unit from a printed volume when given
  ("about 3 tbsp" → qty=3, unit="tbsp"), else qty=null, unit=null,
  unit_mappable=false with the printed phrase kept in raw_amount (the fruit
  count is not the juice's amount; notes stays empty). When the
  recipe ALSO uses the zest or the fruit itself (any line or step does), the
  fruit is what's bought — ingredient_text="lemon", the transforms in notes
  ("juiced", "zested"), and the amount is still the printed volume when there
  is one ("Juice of 1 lemon (about 3 tbsp)" → qty=3, unit="tbsp", the fruit
  count kept in raw_amount); with no volume printed, qty=1, unit="piece". An optional zest printed on
  the same line ("plus zest (optional), to serve") folds into that line's
  notes — it never becomes a line of its own.
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
  Usage and choice qualifiers also go to notes, never into ingredient_text:
  "for serving", "to serve", "for frying", "plus more to taste", "or to taste",
  "depending on size and desired amount", "or desired amount", "(your choice)",
  "of your choice", a printed equivalent after the amount ("1 medium", "about 4
  large stalks", "about 1 cup"), and a parenthetical telling the cook what to
  do instead ("(or spinach or kale and 4 garlic cloves, fried)"). "freshly
  cracked / freshly ground black pepper" → ingredient_text="black pepper",
  notes="freshly cracked". Several fragments join in printed order with "; ".
  What STAYS in ingredient_text, never in notes: size words ("small", "large",
  "fat"), form words ("fresh", "dried", "boiling", "warm", "cooked",
  "toasted", "leaves", "head of"), a plain alternative between products
  ("soy sauce or tamari", "olive oil or vegetable oil" — keep both), a
  product's own parenthetical ("small pasta (pastina)"), and a page
  cross-reference ("Italian Sausage (page 45)"). notes never repeats the
  amount ("juice of 1 lemon", "400g cans") and never says "optional" — that is
  the optional field.
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
  time → both equal; a printed range → low/high). No banner → null, even when
  the steps give durations: never add up or copy a step's time.
- SHELF LIFE (keeps_for_days, freezable, freezer_days): ONLY from what the
  source prints about storing the FINISHED dish, wherever it sits (a "Fridge
  life" banner, the intro, a step, a note). Leave that text in place, as printed.
  keeps_for_days = days in the FRIDGE ("Fridge life: 3 days" → 3). A range
  takes the low end ("3–4 days" → 3); a week = 7 days, a month = 30.
  freezable=true only when the source says it freezes; freezer_days = the
  printed freezer time, else null. Nothing printed, or "not suitable for
  freezing" → freezable=false. Never infer from the kind of dish. Room-
  temperature storage, or a component kept on its own ("the dressing keeps a
  week"), sets nothing.
- image_quality: your honest legibility read (ok | degraded | poor).
- truncated=true ONLY when the source is deliberately cut off (a missing page).

CHECK EACH LINE: ingredient_text keeps every word of the food's name as
printed — size, "fresh", "leaves", "cooked", an "or" alternative ("tamari or
coconut aminos"), a "(page N)" cross-reference ("1 tablespoon fresh lemon
juice" → "fresh lemon juice");
notes holds only what the cook DOES to it and how it is used or served, in
the LINE's own printed words — never words from the method, never the amount
or its conversions, a size, a product form, or the word "optional". "Juice of
1 lime" alone → ingredient_text="lime juice", qty=null, unit=null, notes
empty.`;
}

/** The step-tokenization rules, shared by the one-shot and two-phase prompts. */
const STEPS_RULES =
  `STEPS — token arrays (§4.6). A step is an ORDERED list of tokens; chop the prose
at label boundaries, never rewrite it: the tokens' words, in order, are the
step's printed words and punctuation (timers aside), none added, dropped or
reworded. Rendering walks the array — there is NO text matching later.
- STEP SEGMENTATION is source-determined, never a style choice: one printed
  step = one step, exactly. The source's own separations (numbers, bullets,
  paragraph breaks) are the ONLY step boundaries. An unbroken method paragraph
  is ONE step, however many sentences it holds — never split it, and never
  merge separately printed steps. The step's printed number or bullet ("1.")
  is not part of its text.
- Use only three token kinds: "text", "ref" and "timer". Never emit an
  "amount" token; a printed quantity in a step stays in the text.
- "text" token: a plain prose span { "t":"text", "s":"…" }.
- "ref" token: { "t":"ref", "refs":["<line key>",…], "label":"<the food's
  name>", "mention":…, "portion":… }. The chip words go in "label" — NEVER in
  "s" — and "label" is the noun phrase that NAMES the food, exactly as printed
  in the step, every word of the name kept ("canned chopped tomatoes", "cream
  of tartar"). Only a leading determiner ("the", "a", "an", "some") is not part
  of the name: it stays in the text token BEFORE the chip — "Add the kale" →
  text "Add the " + label "kale". Prep words the prose puts around the name
  ("the chopped cabbage", "kale, shredded") stay in text tokens. The label
  never gains a word the step does not print there. refs is a list of line
  KEYS — copy each key exactly as you minted it on the line.
- mention: "new" the FIRST time a line is chipped anywhere in the recipe;
  "rementioned" for that line's later chips; "fraction" when the step uses a
  stated part of the line (a sub-amount, "half", "the remaining", "the
  reserved"). NEVER put a quantity on a ref — the chip inherits its number
  from the line.
- WHAT TO CHIP. Each time a step USES an ingredient line — adds, cooks,
  tosses, tops, serves or removes it — the words that name it are a ref, in
  every step that uses it. A mention counts even when it shortens or renames
  the line: "salt" for "sea salt", "quinoa" for "cooked tricolour quinoa",
  "garlic" for "fat garlic cloves", "the sausage" for "Italian sausage links".
  A line named with its prep or state ("the roasted fennel", "the chopped
  tofu", "the crispy kale") is still that line — chip it. Pronouns and implied
  subjects ("them", "it", "everything") are NOT refs.
- ONE CHIP PER LINE PER STEP. Keep a tally while you write each step: once a
  line has been chipped in this step — alone or inside a collective — every
  later naming of it IN THE SAME STEP is plain text. "First, roast the
  broccoli. Chop the broccoli…" → chip the first "broccoli" only; "Add the
  rice to the pot", "Spread the tofu on the sheet", "more quinoa, more
  broccoli", "Serve garnished with the green onions" are text when that line
  was already chipped earlier in the same step. The next step starts a fresh
  tally. The one exception: the step itself splits the line into stated parts
  ("1 cup of the stock … the remaining 1½ cups stock") — chip each part.
- COLLECTIVES — one ref token whose label is the printed phrase and whose refs
  list every line it covers, never one chip per ingredient:
  · A catch-all ("all the ingredients", "all the remaining sauce
    ingredients", "the remaining ingredients") covers EVERY line of the group
    the step is making (the group printed for that component, or the whole
    list if it is ungrouped) that no earlier step used — seasoning lines
    included, optional lines included. Only lines printed "to serve" / "for
    serving" stay out, and so does any line the same step names on its own.
    Walk the line list and enumerate the keys.
  · A mixture an earlier step made from several foods stays TEXT, whatever it
    is called: "the onion mixture", "the wild garlic sauce", "the dressing",
    "the 'feta'", "the broth mixture". A chip names a food, never a
    preparation of several. A food that is still itself ("the reserved chopped
    mushrooms", for the mushroom lines) is chipped as that food.
  · A plural that names two lines at once ("the bell peppers" for a green and
    a red pepper line) is one ref over both.
  · A strained liquid ("the mushroom broth", "the soaking liquid") is a single
    ref on the liquid line it was made from (the water), not on what steeped
    in it.
  A plain conjunction of separately listed foods ("salt and pepper", "oregano,
  thyme") is NOT a collective: one single-line ref per food, the connecting
  words as text between them.
- SEASONING SCOPE. "salt" / "a pinch of salt" chips a salt line only inside
  the scope being cooked: a line of the same group (or the ungrouped list).
  It stays text when the only salt line belongs to another group ("For the
  dressing" salt is not the salt for roasting the broccoli), or when that line
  prints its own measure that a later step uses ("1 tsp sea salt" blended into
  the sauce — the frying pinch is untracked). A salt line printed with no
  amount ("Sea salt") is chipped by its pinch. Salted cooking water and
  "adding more salt or lemon juice to taste" are text.
- EITHER/OR. "a drizzle of olive or chilli oil" chips only the branch that is
  its own line meant for that use — label "chilli oil", "olive or " left as
  text; a line already spent for another role (the frying oil) does not
  qualify. If neither branch is such a line, it is all text.
- ref.portion: present ONLY when the STEP names a sub-amount for that
  reference. A number transcribed from the step text (one number as
  qty_low = qty_high, a step range as qty_low/qty_high) + unit; OR a relative
  qualifier ("the rest", "half", "the reserved", "for garnish") with no
  number. Never invent a portion number. The portion COPIES the figure; the
  printed words stay in the text: "combine 2 tablespoons of the parsley" →
  text "combine 2 tablespoons of the " + ref parsley (portion 2 tbsp).
  Per-serving portions ("1 tbsp per bowl") legitimately do not sum to the
  line total — that is fine.
- "timer" token: { "t":"timer", "low_seconds":N, "high_seconds":M }. NEVER a
  timer: a storage time ("consume within 4 days", "keeps for a week") or a
  time relative to something unprinted ("1 minute less than the packet
  instructions") — both stay text. Otherwise EVERY printed duration the cook
  waits through — cooking, resting, soaking, marinating — becomes its own
  timer token, in position (a step may have several). "15 to 20 minutes" → 900/1200; "5 minutes" → 300/300. The timer
  replaces only the duration words: "for", "about", "another" stay in the text
  around it. Conditional alternatives ("5 min fresh, 2 min frozen") are
  SEPARATE timer tokens; the condition stays in the text.
- Prose you cannot confidently link to a line stays a plain text token (no
  chip): a food no line prints (water for the pasta pot, cayenne inside a
  spice blend), or a sub-recipe reference ("Romesco Aioli (p38)") that is not
  a line.
- A step with zero refs is fine. An ingredient never named in a step gets no
  chip; that is normal, not an error.

WORKED EXAMPLE (illustration only — not from the recipe you are given).
Lines: key "onion" (1 onion, diced), "olive-oil", "sea-salt" (Sea salt — no
amount), "cumin", "paprika", "chilli-flakes"; group "For the sauce":
"tahini", "lemon-juice", "garlic", "water"; "parsley" (Parsley, to serve).
Step printed: "Fry the onion in the olive oil with a pinch of salt for 5
minutes, stirring the onion often. Stir in the cumin, paprika and chilli
flakes. Add all the sauce ingredients and simmer for about 2 minutes. Serve
topped with the parsley." Tokens:
  text "Fry the " · ref onion ["onion"] new · text " in the " · ref olive oil
  ["olive-oil"] new · text " with a pinch of " · ref salt ["sea-salt"] new ·
  text " for " · timer 300/300 · text ", stirring the onion often. Stir in
  the " · ref cumin ["cumin"] · text ", " · ref paprika ["paprika"] · text
  " and " · ref chilli flakes ["chilli-flakes"] · text ". Add " · ref all the
  sauce ingredients ["tahini","lemon-juice","garlic","water"] new · text " and
  simmer for about " · timer 120/120 · text ". Serve topped with the " · ref
  parsley ["parsley"] new · text "."
The second "onion" is text (already chipped in this step). A list of foods is
one ref per food with only the separators (", ", " and ") as text between —
however long the list, a text token never holds a listed food's name. The
catch-all is ONE ref listing every line of its group.`;

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
