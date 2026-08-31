# Gold schema (finalized 2026-08-30; owner rulings folded in through 2026-08-31)

The shape every `gold/<recipe>.json` conforms to. Mirrors the `ExtractionResult`
contract in `docs/exec-plans/completed/0014-import-foundation.md`. When W0's
`supabase/functions/_shared/types.ts` is written, it matches this file — one source.

## Governing rule — NEVER INVENT

No fabricated ingredient, quantity, unit, time, serving, or step. If something is
absent or ambiguous in the source, **leave it null and flag it in `_review`** —
never guess a value in. Every transform you make (splitting a line, deriving a
range, tokenizing prose) is source-derived or it doesn't happen.

## Top level

```jsonc
{
  "source_images": ["dense bean salad.jpg"],
  "title": "Dense Bean Salad",
  "servings_base": 3,          // best-effort integer portions; null if genuinely unclear (a yield like "1 cup") — then flag
  "servings_raw": "Serves 3",  // exact printed text
  "yield_raw": null,           // printed yield when it isn't portions, e.g. "Makes 1 cup" / "Makes 8 sliders"; else null
  "total_time_seconds": null,  // {low,high} object if a range is printed (see time), else a number, else null (RE-READ the image for these two)
  "cook_time_seconds": null,
  "truncated": false,          // true only for the deliberately-missing-page case
  "image_quality": "ok",       // ok | degraded | poor — your honest legibility read
  "parse_warnings": [],
  "groups": [ /* … */ ],
  "_review": [ /* every spot a human should check, incl. every transform you inferred */ ]
}
```

Nutrition banners are **ignored** (we compute macros ourselves).

## Line items (inside `groups[].line_items[]`)

```jsonc
{
  "qty": 400,            // a SINGLE number. For a RANGE, set qty:null and fill qty_low/qty_high.
  "qty_low": null,       // range low  (e.g. "4 to 6" → 4)
  "qty_high": null,      // range high (e.g. "4 to 6" → 6)
  "unit": "g",           // normalized toward standard units where obvious; else the word as printed
  "unit_mappable": true, // false if the amount can't map to a standard unit
  "ingredient_text": "cannellini beans",  // ingredient IDENTITY, AS WRITTEN — keep PRODUCT-FORM words (how it is sold), do NOT singularize
  "notes": "drained",    // COOK-PREP / usage note: an action YOU do to the base ingredient (or a garnish/serving qualifier) — split it out here; null if none
  "raw_amount": "2½ x 400g cans",  // the FULL printed amount, verbatim — never lose it
  "optional": false,
  "confidence": 0.9
}
```

Conventions (all source-derived, none invented):
- **Range** → `qty:null`, `qty_low`+`qty_high` from `raw_amount`.
- **Cans / tins** — a **single** `"400 g tin"` / `"one 400 g can"` / `"One 14.5-oz can"` → `qty:1, unit:"can"` (NOT `qty:400, unit:"g"`); a **multi-pack** `"2½ × 400 g cans"` → `qty:2.5, unit:"can"` (NOT null). Either way the count is the amount and the gram basis lives in the measure system (it stays only in `raw_amount` until the app resolves it). **Normalise `"tin"` → `"can"`** (British/American synonym) so measure labels don't fragment. Keep any printed **drained weight** in `raw_amount` and flag it.
- **Compound INGREDIENT line** `"Sea salt and freshly cracked black pepper"` → **split into two line items**. Re-index every step `line_index` that shifts as a result, and flag the split in `_review`.
- **Compound AMOUNT, one ingredient** `"2 tbsp + ½ cup parsley"` (both volume) → sum within the family for the line total (`0.625 cup`); the split is represented per-step via `portion` (below). Cross-family compounds that can't bridge → keep `raw_amount`, `qty:null`, flag.
- **The PACK is the unit** (generalises the cans rule). Whenever the printed amount counts a *container or sold unit* and states its size, the COUNT is the amount and the size stays in `raw_amount`: `"One 14-ounce block"` → `qty:1, unit:"block"` (NOT `qty:14, unit:"oz"`); same for `can`, `loaf`, `head`, `bunch`, `slice`, `stalk`, `sprig`, `clove`. The gram/oz basis is the measure system's job, not the line's. *(owner ruling)*
- **Every count-measure noun is mappable — no exceptions.** The count family is `piece` plus the generic measure nouns `clove · head · sprig · loaf · block · slice · can · bunch · stalk` (the same list `_shared/unit_hints.ts` hands the model and `runner/score_extraction.ts` scores as one family). **All of them take `unit_mappable: true`**, uniformly: `"Leaves from 4 sprigs rosemary"` → `qty:4, unit:"sprig"`, `"One 14-ounce block"` → `qty:1, unit:"block"`, `"½ loaf"` → `qty:0.5, unit:"loaf"`, `"1 large head of broccoli"` → `qty:1, unit:"head"` — every one `unit_mappable:true`. *(owner ruling 2026-08-31, superseding the earlier per-noun split.)* `unit_mappable:false` is for amounts with **no** measure noun to map at all (`"Thumb-sized piece"`, `"2 large handfuls"`, a bare unquantified line).
- **`heaped` / `scant` / `rounded` modifiers** → keep the **printed** qty exactly (never inflate or deflate a number for them) **and** put the modifier word in `notes`: `"3 heaped tbsp peanut butter"` → `qty:3, unit:"tbsp", notes:"heaped"`, full phrase still in `raw_amount`. *(owner ruling)*
- **Printed qty + "or to taste"** → the printed number **wins**: keep `qty`/`unit` as printed and put the qualifier in `notes` (`"1 teaspoon sea salt, or to taste"` → `qty:1, unit:"tsp", notes:"or to taste"`). `qty` goes null only when **no** number is printed. *(owner ruling)*
- **Count-on-produce-with-a-transform** `"Juice of 1 lemon"` → `qty:1, unit:"piece", ingredient_text:"lemon", notes:"juiced"` (match the produce). If the page gives a volume `"(about 3 tbsp)"` → `qty:3, unit:"tbsp"`, lemon count stays in `raw_amount`. An **optional second use of the SAME produce** (`"plus zest (optional)"`) folds into that line's `notes` — it does **not** become a second line item. *(owner ruling)*
- **Count produce** `"1 red bell pepper"` → `unit:"piece"`.

### `notes` — cook-prep vs product-form (the identity split)

`ingredient_text` is the **identity** — what you buy and match against. `notes` holds a
**cook-prep transform** — an action YOU perform on that base ingredient (plus any
garnish/serving qualifier), split out so it renders as a note and never pollutes the
match text. (The field is named `notes` because it is the render-time note slot; the
*concept* it captures is still cook-prep.)

The test: **would a shop sell it that way?** If the word is *how the thing is sold*
(a product form/state that changes what you buy), it is **identity — keep it in
`ingredient_text`**. If the word is *an action the cook takes* (you did it in your
kitchen), it is **cook-prep — move it to `notes`**.

| cook-prep → move to `notes` (an action you do) | product-form → keep in `ingredient_text` (how it is sold) |
|---|---|
| `onion, thinly sliced` → `onion` + notes `thinly sliced` | `tinned chopped tomatoes` (a distinct SKU — never split the "chopped") |
| `celery, finely diced` → `celery` + notes `finely diced` | `smoked paprika`, `ground cumin`, `ground white pepper` |
| `garlic, minced` → `garlic` + notes `minced` | `boneless` (`chicken thighs, boneless`), `canned`, `coconut milk (canned)` |
| `chopped onion` → `onion` + notes `chopped` | `self-raising flour`, `long-grain rice`, `raw sesame seeds` |
| `potato, mashed` → `potato` + notes `mashed` | `dried oregano`, `fresh basil`, `frozen peas`, `toasted seeds`, `cooked rice` |
| `ginger, grated` → `ginger` + notes `grated` | `crushed red pepper flakes` (crushed = the product, not an action) |
| `beans, drained and rinsed` → `beans` + notes `drained and rinsed` | `fire-roasted diced tomatoes` (a can — the diced is the product) |
| `Juice of 1 lemon` → `lemon` + notes `juiced`; also `zested`, `leaves picked` | `smoked chilli harissa paste`, `pickled red onions`, `stone-ground mustard` |
| `parsley, for garnish` → `parsley` + notes `for garnish` (`for garnish` qualifier) | `extra-firm tofu`, `extra virgin olive oil`, `silken tofu` |

Rules:
- **Multiple cook-preps on one use → one `notes` string**: `"peeled and diced"`,
  `"cleaned, ends trimmed, and quartered"`, `"destemmed and roughly chopped"`.
- **A product-form + a cook-prep on the same line** → keep the form in identity, move
  only the action: `"diced fresh tomatoes"` (fresh) → `fresh tomatoes` + notes `diced`,
  but a canned `"fire-roasted diced tomatoes"` keeps everything (it is the product).
- The hard test: `tinned chopped tomatoes` is a **product** (identity, keep "chopped");
  `1 onion, thinly sliced` is a **base + cook-prep** (`onion` identity, `thinly sliced`
  → `notes`). "Chopped/crushed/diced tomatoes (tinned)" are DIFFERENT PRODUCTS — never
  move that "chopped" to `notes`.
- **`freshly cracked` / `freshly ground` black pepper** → `ingredient_text: "black pepper"`,
  `notes: "freshly cracked"` / `notes: "freshly ground"`. Both grind wordings are cook-side
  freshness qualifiers, not distinct SKUs, so neither pollutes the match text. Plain
  `"black pepper"` lines are unchanged. By contrast **`rubbed sage` stays in identity** —
  rubbed sage is genuinely how it is sold, and so does bare **`ground cumin` / `ground white
  pepper`** (sold ground, with no "freshly"). *(owner ruling; `freshly ground` folded in
  2026-08-31 as the same shape as `freshly cracked`.)*
- **Usage qualifiers** (`for serving`, `for frying`, `for roasting`, `to serve`,
  `plus more for garnish`, `plus more to taste`, `or to taste`) are quantity / usage
  notes, **not** cook-prep, but they still come **out of `ingredient_text` into `notes`**
  so the identity stays clean for matching. *(owner ruling — this supersedes the earlier
  "leave them in `ingredient_text`" draft; every gold file already follows it.)*
- **Substitution instructions live in `notes`** — there is no dedicated field. A long
  parenthetical like `"(if not using fermented tofu, season the crumbled tofu with lemon
  juice and salt before adding)"` joins the line's other cook-prep in one `notes` string;
  `ingredient_text` keeps only the identity. *(owner ruling)*
- **The split applies INSIDE an `or`-alternative.** `"shelled fresh peas or thawed frozen
  peas"` → identity `"shelled fresh peas or frozen peas"` (both `shelled` and `frozen` are
  product-forms, and the whole alternative is kept) + `notes: "thawed"` (an action you take).
  Extract the cook-prep word; do not split the line into two. *(owner ruling)*
- **Multiple note fragments join in printed order**, `; `-separated:
  `"freshly cracked; or to taste"`.
- Genuinely borderline calls (is `pitted` a product form or an action?) → **make the call
  but flag it in `_review`**.

## Steps — token arrays (NOT strings + a ref list)

A step is an ordered list of tokens. The prose is **chopped into pieces** at label
boundaries: plain-text spans, `ref` tokens (the chip words), and `timer` tokens.
Rendering walks the array — there is no render-time text matching.

```jsonc
{
  "tokens": [
    { "t": "text", "s": "Combine the " },
    { "t": "ref",  "refs": [7], "label": "parsley", "mention": "rementioned",
      "portion": { "qty": 2, "qty_low": null, "qty_high": null, "unit": "tbsp", "qualifier": null } },
    { "t": "text", "s": " with the diced " },
    { "t": "ref",  "refs": [3], "label": "onion", "mention": "new", "portion": null },
    { "t": "text", "s": ", then simmer " },
    { "t": "timer", "low_seconds": 900, "high_seconds": 1200 },
    { "t": "text", "s": "." }
  ]
}
```

Token rules:
- **`ref`** — `refs` is a list of **flattened** `line_index`es (index into all
  `line_items` across all groups, in order); a set means a collective chip
  (`"the dry ingredients"`). `mention`: `"new" | "rementioned" | "fraction"` —
  meaningful only on a **single-line** ref; on a collective (`refs.length > 1`)
  it's advisory (a collective shows no number anyway, §4.6).
- **`ref.portion`** — OPTIONAL; present only when the STEP names a sub-amount.
  A number (`qty`, or `qty_low`/`qty_high` for a step range) + `unit`, both
  transcribed from the step text; OR a relative `qualifier`
  (`"the rest" | "half" | "for garnish"`) with no number. Never invent. Whether
  step portions sum to the line total is an **advisory** data-quality hint, NOT a
  rule: **per-serving** recipes legitimately state a per-bowl portion (`"1 tbsp
  per bowl"` × 4 servings = the `¼ cup` line), so a portion smaller than the line
  total is normal — reconcile by servings, don't treat it as an error.
- **`timer`** — `low_seconds`/`high_seconds` (single time → both equal;
  `"15 to 20 min"` → 900/1200). **Every** time phrase becomes its own timer token,
  positioned in the stream (a step may have several). Alternatives/conditionals
  (`"5 min for fresh, 2 min for frozen"`) are **separate bare timer tokens** — the
  condition stays in the surrounding `text` span; there is no condition/label field.
  **Rest / stand / chill / marinate times ARE timers** (`"let sit for 5 minutes"` →
  300/300) — a timer token is "a duration the cook waits", not "a duration the heat is
  on". *(owner ruling)*
- Text the model can't confidently link stays a plain `text` span (no chip). A
  `"pinch of salt"` with no matching line, or a **sub-recipe reference**
  (`"Romesco Aioli (p38)"`), stays plain text (nested recipes are deferred).
- **Garnish re-mentions stay plain text.** When a step names an ingredient again purely
  as a garnish (`"Serve garnished with the green onions"`) and that line is already
  chipped earlier, do **not** emit a second `ref` chip. One chip per line per genuine
  use; the garnish restatement is prose. *(owner ruling)*
- **Never-mentioned ingredients stay unlinked.** A line item no step mentions gets no
  ref anywhere — do not invent a chip to tidy up an authorial omission. Note the orphan
  in `_review`. *(owner ruling)*
- **No editorial markers in step text.** When the source is cut off (a missing page), the
  gold **ends at the printed cut**, mid-sentence if that is where it stops — never
  `"[RECIPE CONTINUES — page 2 missing]"` or any other bracketed annotation. The cut is
  recorded in `truncated: true`, `parse_warnings`, and `_review`. A marker inside the
  prose is invented content the model would then be scored against. *(owner ruling)*
- A step with zero refs is fine.
