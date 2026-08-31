> ⚠️ **EPHEMERAL — superseded working scratch. Do not design against this.**
> This was a one-shot UX *proposal*; the shipped UI diverged from it substantially
> during live iteration (merged single editable review, expand-to-edit, band-based
> auto-lock, suggestion chips, save-gating). The **source of truth for the import +
> recipe-view design is [`design-board.html`](./design-board.html)** — its "Import &
> recipe view · v3" section. This file is not maintained.

**Status:** Proposal for Simon to react to · **Scope:** Mise v1 import reconciliation + preview UX · **Type:** UX design (no code)
**Supersedes (UX only):** the three-state "Review import" screen described in `import-and-matching.md` §8 and the design-board "Import & match" frame.
**Does NOT touch:** the frozen data contract (`supabase/functions/_shared/types.ts`, `evals/datasets/extraction/gold/_SCHEMA.md`), the match cascade, or normalization. Everything here is client-side *view + resolution* work plus reuse of the existing recipe editor / pickers.

---

## 0. The one-paragraph pitch

Today's screen is a flat list of per-line cards: every line, matched or not, sits open at the same weight, and "reconciliation" ends where a bare line list ends — there's no recipe to look at before you commit. The redesign keeps the honest three-band engine underneath but changes what the human *sees*: auto-matched lines fold away so only the lines that need a decision are loud ("2 to review"); the same ingredient used twice resolves **once** but keeps its two uses visible; unit/amount and prep become things you can see and correct in place; and the flow ends on a **real, editable recipe preview** — the thing you're actually saving — not a checklist. Intake → **triage** (only what needs you) → **preview/edit** → commit.

**Crucial framing:** the frozen contract already supports all six asks. The cook-prep qualifier is a first-class field on `RawLineItem` — named `notes` (renamed from `prep`; the concept it carries is still cook-prep, and "prep" below refers to that concept). The same ingredient used twice already arrives as two separate `ReconLine`s, each with its own `raw_amount` **and its own `notes`**. `aggregateQuantities` already does honest within-family sums and honest subtotals. None of this needs a contract change — it needs a **view layer** that stops treating the flat line list as the whole story.

**The unit of the redesign is the *use*, not the *line*.** An ingredient is used one or more times; each **use** is `{ amount(s), prep, note }` and every use of a given ingredient resolves to the **one** matched identity but is **shown separately**. Prep is per-use, exactly parallel to amount: "garlic, finely chopped" in the dish and "garlic, sliced for garnish" to serve are two uses of one Garlic, each with its own amount *and* its own prep. A single use may carry **several prep qualifiers** ("peeled and diced"). This shape — amount(s) · ingredient · prep/notes, per use — is what both the reconciliation card and, crucially, **the committed recipe page** must render.

---

## 1. The flow at a glance

```
┌──────────┐   ┌──────────────────┐   ┌────────────────────┐   ┌──────────┐
│  INTAKE  │──▶│    TRIAGE        │──▶│   PREVIEW / EDIT    │──▶│  COMMIT  │
│ link /   │   │ only lines that  │   │ full recipe — title,│   │ writes   │
│ photo    │   │ NEED you, loud;  │   │ servings, grouped   │   │ through  │
│          │   │ auto-matched     │   │ ingredients+amounts │   │ Power-   │
│          │   │ folded ("2 to    │   │ +prep, method chips │   │ Sync →   │
│          │   │ review")         │   │ (fixed v1)          │   │ recipe   │
└──────────┘   └──────────────────┘   └────────────────────┘   └──────────┘
   ImportIdle     ImportReconciling        (new sub-state or         ImportCommitted
                                            same state, "preview" step)
```

Two deliberate changes to the current state machine's *presentation* (not its states):

1. **Triage replaces the flat list.** `ImportReconciling` still holds the same payload + resolutions; the body just renders differently — decisions first, settled lines collapsed.
2. **A preview step sits between "all resolved" and "commit."** Today `canCommit` flips a single "Save recipe" button at the bottom of the line list. Instead, resolving everything unlocks **"Review recipe →"**, which pushes the full editable preview; **Save** lives there. (Whether preview is a second route or a second phase of `ImportReconciling` is an open decision — §9.)

---

## 2. Screen 1 — Intake (essentially unchanged)

Keep `_IntakeForm` as-is. Link field + "Import from photos". One copy tweak: the current subtitle promises "you confirm each match" — soften to "you'll review what we read before it's saved," since most lines will now auto-confirm and the human's job is triage + preview, not per-line confirmation.

No wireframe needed; this screen is fine.

---

## 3. Screen 2 — Triage ("2 to review")

The heart of the redesign. The current `ReconciliationBody` renders **every** line as an equal-weight card. Instead, split the payload's lines by whether they need a human:

- **Needs you** = band `suggest`, band `none`, any printed **range** (no auto-pick), any **unmappable unit**, low confidence, or a parse warning attached to the line. These render as open, actionable cards.
- **Auto-matched** = band `auto` with a mapped unit and a single quantity. These collapse into a single quiet, expandable summary.

### 3.1 Wireframe

```
‹ Review import                                    2 to review
──────────────────────────────────────────────────────────────
Weeknight Tomato Pasta                              SERVES  – 2 +

⚠ Check these
  • Chilli flakes quantity wasn't printed — set it below.
──────────────────────────────────────────────────────────────
NEEDS YOU  (2)

┌────────────────────────────────────────────────────────────┐
│ garlic cloves, sliced                        2–3 cloves     │
│ prep: sliced                                                │  ← §6 prep chip
│ Pick amount:  [ 2 cloves ]  ( 3 cloves )                    │  ← §5 range/qty
│ Did you mean?                                               │
│   ( Garlic )   ( Garlic granules )   [ Something else ⌕ ]   │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ Aleppo chilli flakes                                        │
│   used 2 ways — resolve once ▾                              │  ← §4 grouped uses
│     • a good pinch          (optional)                      │
│     • extra, to serve       (optional)                      │
│ ✗ no match found                                            │
│   [ Find or create ingredient ⌕ ]                           │
└────────────────────────────────────────────────────────────┘
──────────────────────────────────────────────────────────────
AUTO-MATCHED  (3)                                    review all ▾

  spaghetti ............... Spaghetti        200 g      ✓
  tinned chopped tomatoes . Chopped tomatoes 400 g      ✓
  Parmesan, grated ........ Parmesan          30 g      ✓
     (collapsed by default; tap a row to change/undo)
──────────────────────────────────────────────────────────────
                    [  Review recipe →  ]   ← disabled until 0 to review
```

### 3.2 Recommendation

- **Header count** ("2 to review") is the live `unresolvedCount`, but now *meaningfully small* because auto-matched lines don't count against it. This is exactly the design-board `<span class="dots">2 to review</span>` promise, finally backed by the layout.
- **Auto-matched section** collapses to a dense list (reuse the recipe page's `_LineRow` visual language — name · match · amount · check). Tapping a row expands it into the same actionable card the "needs you" lines use, so "the match is wrong" is always one tap away. **Do not hide the undo** — surface it on expand. This preserves the current "auto-match with undo" honesty (§8 of the spec) while getting it out of the way.
- **"Needs you" card** is the current `ReconLineCard`, restructured: raw line → prep chip → amount control → resolver. Same `_Resolver` band logic, same `_Pill` candidates, same range buttons — reorganized, not rewritten.
- **Bottom button becomes "Review recipe →"** (was "Save recipe"). It never commits directly; it advances to preview. Keep the honest disabled label ("2 lines need you").

### 3.3 Sub-decisions for Simon

- **What counts as "needs you"?** I've proposed: suggest / none / range / unmappable unit / low-confidence / line-level parse warning. Low-confidence auto-matches are the judgment call — do we surface a 0.72-confidence *auto* match in triage, or trust it and let the user catch it in preview? (I lean: trust it, catch in preview — otherwise "2 to review" creeps back up to "9 to review.")
- **Group heading fate.** The current screen shows the extraction's group headings ("To finish") inline. In triage, groups are broken by the needs-you/auto split. I propose dropping group headings from triage entirely (they reappear in preview, where they belong) — triage is a work queue, not the recipe.

---

## 4. Point 1 — One ingredient, multiple uses (shown separately)

**The situation, concretely** (from the canned payload): "Aleppo chilli flakes — a good pinch" and "Aleppo chilli flakes — extra, to serve" arrive as **two separate `ReconLine`s**, same `ingredient_text`, different `raw_amount`, both band `none`. The recipe *means* two things: a cooking amount and a garnish amount. That separation is intent and must survive.

### 4.1 Recommendation: resolve the identity once, keep the uses (amount + prep) as a list

**Model a use as `{ amount(s), prep, note }`.** In triage — detect sibling lines (same normalized `ingredient_text`, or, once resolved, same chosen ingredient) and render them as **one card with a stacked "uses" list**. The user makes **one** identity decision; it fans out to every sibling `LineResolution`. Each use keeps its **own** amount, **own prep** (possibly several qualifiers), optional flag, and range pick — none of these are shared across uses.

```
┌────────────────────────────────────────────────────────────┐
│ Aleppo chilli flakes           used 2 ways — resolve once   │
│ ──────────────────────────────────────────────────────     │
│ ✗ no match  →  [ Find or create ingredient ⌕ ]              │
│ ──────────────────────────────────────────────────────     │
│  Uses (kept separate — each its own amount + prep):         │
│   1 · a good pinch    ⌗ toasted        (optional)   ✎       │
│   2 · extra           ⌗ —, to serve    (optional)   ✎       │
└────────────────────────────────────────────────────────────┘
   ↑ one identity pick, above the line; two independent {amount, prep} below
```

A richer example that shows per-use prep clearly — one Garlic, two uses:

```
┌────────────────────────────────────────────────────────────┐
│ garlic              used 2 ways — resolve once   → Garlic ✓ │
│ ──────────────────────────────────────────────────────     │
│   1 · 2 cloves      ⌗ finely chopped               ✎       │
│   2 · 1 clove       ⌗ sliced · for garnish         ✎       │  ← multi-qualifier
└────────────────────────────────────────────────────────────┘
```

Mechanically this is a **view grouping over the flat line list** — no contract change. `LineResolution` is keyed by `lineIndex`; resolving the group writes the same `chosenIngredientId`/`createStubName` (and, for a stub, the same coalescing name — which `buildCommit` already dedupes onto one `CommitStub`) to each sibling's resolution, while `quantity`/`unit`/**`notes`** stay strictly **per-line (= per-use)**. This is the *stub coalescing* that already exists (`buildCommit` keys stubs by normalized name), surfaced honestly in the UI instead of happening invisibly at commit. **Prep is never merged or lifted to the group** — merging identity is safe; merging prep would destroy the intent the separation carries.

### 4.2 How the committed recipe renders the two uses

**This replaces any "sum the amounts" instinct.** Amounts are a **list**, combined only when the domain safely can. Reuse `aggregateQuantities`:

- Two uses, **compatible** units (e.g. "20 g" in-dish + "10 g" to serve) → offer the honest single total *and* the breakdown. `aggregateQuantities([20g, 10g])` → `30 g`.
- Two uses, **imprecise / unmappable** ("a good pinch" + "extra, to serve") → `aggregateQuantities` correctly refuses to merge (it never merges imprecise units, and keeps honest subtotals). So the recipe shows **two rows**, not a fabricated total.

**On the recipe page**, render sibling uses as adjacent rows under the same ingredient identity, each carrying its own amount + a use-qualifier:

```
Aleppo chilli flakes                 a good pinch
  └ to serve                         extra
```

or, when the amounts safely combine, a single row with a "(2 uses)" affordance that expands to the breakdown. My recommendation: **default to showing both rows** (honest, matches the recipe's intent) and let combination be the exception the math earns — never the default.

### 4.3 Sub-decisions for Simon

- **Where's the seam between "one ingredient" and "two ingredients"?** Auto-group only *exact* `ingredient_text` siblings? Or also group after the user resolves two differently-worded lines ("chilli flakes" + "Aleppo chilli") to the same ingredient? I lean: auto-group exact siblings pre-resolution; *offer* (don't force) grouping when two resolved lines land on the same ingredient — a subtle "these both matched Chilli flakes — keep separate / merge uses?" nudge.
- **Recipe-page rendering default:** two rows always, vs. combined-with-expand when units allow. I lean two rows.
- **Does the garnish/"to serve" qualifier come from `raw_amount` or the step `portion.qualifier`?** The contract carries `qualifier: "to serve"` on the ref portion. Worth wiring so the second row reads "to serve," not just "extra."

---

## 5. Point 3 — Unit / amount override

A line can be read wrong: "1 × 400 g tin" that should read as **400 g**, a count that should be a weight, a unit the model couldn't map (`unit_mappable: false`). The user needs to correct the **amount + unit** in reconciliation.

### 5.1 Recommendation: reuse the step-7.7 quantity + unit sheet verbatim

The recipe editor already does exactly this dance (`_LineItemEditor.editQuantity`): tap the amount → `showQuantityUnitSheet(ingredient, initialQuantity, initialChoice)` → get back `QuantitySaved(quantity, choice, unitPicked)`. **Reuse it here.** The amount on every reconciliation line becomes a tappable chip identical to the editor's:

```
   tinned chopped tomatoes                    [ 400 g ✎ ]   ← tap → sheet
                                                 raw: "1 × 400g tin"
```

- The tappable amount chip is the recipe editor's `_LineItemEditor` measure chip, lifted into the recon card.
- Opening it calls `showQuantityUnitSheet` with the line's current `qty`/`unit` as `initialQuantity`/`initialChoice`. On `QuantitySaved`, write `quantity` + `unit` back onto the `LineResolution` (`pickQuantity` already exists; add a unit setter alongside it, mirroring `setLineItemUnit`).
- **Always keep `raw_amount` visible** underneath as the ground truth ("raw: 1 × 400g tin"). Honest-numbers rule: the printed thing is never lost, so an override reads as *"we heard X, you're setting Y."*
- The **range picker** (`_RangeButtons`) becomes a special case of the same chip: a range line shows its two endpoints as quick-pick pills *and* the "✎" to open the full sheet for anything else. This unifies "pick 2 vs 3 cloves" and "actually it's 400 g" into one affordance.

Because a subagent owns the unit/measure **mechanics**, the UX contract here is deliberately thin: **the override sheet is the 7.7 sheet, unmodified; reconciliation only decides when to open it and where to store the result.** The stub-shaped stand-in `_LineItemEditor` already builds (an `Ingredient` with just id/name/defaultUnit when the row isn't resolved yet) covers the case where the line hasn't matched an ingredient — reuse that pattern so the sheet works before identity is settled.

### 5.2 Sub-decisions for Simon

- **The "1 × 400 g tin → 400 g" case is really a *unit-system* question** (is "tin" a measure that carries a 400 g basis, or does the user flatten it to grams?). That's the sibling subagent's mechanics call. UX-wise I only need: tap amount → sheet → the sheet offers whatever units/measures the mechanics expose. Flag: confirm the sheet can *present* "tin" as a measure so the user isn't forced to hand-convert.
- **An override to a mappable unit should clear the `unit_mappable: false` flag/badge** on the line — confirm that's the desired signal that "you've resolved the unit."

---

## 6. Point 4 — First-class prep, per use, displayed everywhere

`notes` is already a field on `RawLineItem` ("juiced", "zested", "thinly sliced", "peeled and diced") — the extraction separates this cook-prep qualifier from identity precisely so it *doesn't* pollute the match. But today it's invisible in reconciliation and gets **comma-smuggled into the name** at render (`buildCommit` maps `notes → note`; the recipe page prints `"$ingredientName, $note"`). Ending that smuggling is not just an import concern — **the committed recipe page is the real target.**

### 6.1 The three-part ingredient line — the load-bearing rule

**Every ingredient line, per use, renders three distinct parts:**

```
      amount        ·        ingredient        ·        notes (prep)
   ───────────         ────────────────────         ─────────────────
     2 cloves                 Garlic                  finely chopped
```

- **amount** — the scaled quantity + unit/measure (owned by the unit system; scales with servings).
- **ingredient** — the matched identity, and *only* the identity. Never carries prep, never carries "to serve."
- **notes (prep)** — the per-use prep qualifier(s), plus any free note. De-emphasised, but present and distinct. Multiple qualifiers list within this part ("peeled · diced" or "peeled and diced").

This three-part shape is the **single rendering contract** shared by (a) the committed recipe page, (b) the import preview, and — in reduced form — (c) the reconciliation card. Design it once; reuse it in all three. It replaces the current two-part `"amount | name(+comma-note)"` `_LineRow`.

### 6.2 Recommendation for the recipe page (`recipe_view.dart` `_LineRow`)

Extend the recipe-page line to lay out three columns/spans, and to render **sibling uses** (§4) as stacked three-part rows under one identity:

```
INGREDIENTS
──────────────────────────────────────────────────────────────
  2 cloves     Garlic                    finely chopped         ← use 1
     1 clove      └ (same)               sliced · for garnish   ← use 2, prep differs
──────────────────────────────────────────────────────────────
  400 g        Chopped tomatoes                                 ← no prep → part omitted
──────────────────────────────────────────────────────────────
  a pinch      Aleppo chilli flakes      toasted                ← use 1
     extra        └ (same)               to serve               ← use 2
──────────────────────────────────────────────────────────────
  30 g         Parmesan                  grated
```

Layout notes:

- **Three regions, honest about emptiness.** No prep → the notes region is simply empty (not a dangling comma). No amount ("to taste") → the amount region shows the imprecise word or blank; identity always present.
- **Amount stays in its own scan column** so the eye can still run down quantities — prep sits to the *right* of the identity, not between amount and name. (This is why I moved off the earlier "prep before amount" sketch: the three-part rule wants amount and prep in separate regions, not interleaved.)
- **Sibling uses** render as indented continuation rows sharing the identity once (a "└ (same)" or blank identity cell), each with its own amount + prep. This is the §4 "shown separately" rule made literal on the page.
- **Multiple prep qualifiers** join with a middot or the source's own conjunction inside the notes region.

Concretely this is a rewrite of `_LineRow._measure`/`build` in `recipe_view.dart`: today it concatenates `name = "$ingredientName, $note"` and renders `[name | measure]`. Replace with a three-region row `[amount | identity | notes]`, and teach `_IngredientsTab` to render sibling `LineItem`s (same ingredient, adjacent) as a stacked group. The `LineItem` domain already carries `note` (which holds prep post-commit); the change is presentational — split it back out into its own region rather than gluing it to the name.

### 6.3 Recommendation for reconciliation + preview (mirror the same three parts)

**Import preview** uses the *same* three-part row as the recipe page (§8 reuses the editor/line renderer), so what you review is exactly what you'll see.

**Triage / recon card** — a reduced form of the same rule: identity on top, then a **per-use prep chip** and the amount control beneath, visually separate from the matched-ingredient name:

```
   garlic cloves, finely chopped                2–3 cloves ✎
   ⌗ finely chopped                                          ← per-use prep chip, editable
   → matched Garlic
```

- The chip makes the point visually: **"finely chopped" describes the work, "Garlic" is the thing.** Identity matched Garlic; the prep rode alongside, untouched, and stays attached to *this use*.
- Chip is editable (tap to correct/clear/add a qualifier) but **never affects the match** — it's stored on the `LineResolution.notes` that already exists, per line (= per use).
- Optional and "to serve" qualifiers get the same quiet-chip language, kept per-use.

### 6.4 Sub-decisions for Simon

- **Multi-qualifier prep: one string or a list?** The contract's `notes` is a single string, so "peeled and diced" arrives whole. Display it verbatim, or split on `and`/`,`/`·` into separate chips? I lean: **display verbatim** on the recipe page (honest to the source), **offer split chips** only in the editable recon chip if we want per-qualifier editing. Confirm.
- **Notes region = prep only, or prep + a separate free note?** The three-part rule calls the third part "notes (prep)." Is prep the sole occupant in v1, or do we also surface a general free-text note there? I lean: **prep is the v1 occupant**; a general note folds into the same region later without layout change.
- **Sibling-use identity cell.** "└ (same)", a repeated greyed name, or a blank cell? Affects scannability. I lean a light "└" continuation.
- **Prep on method chips (§8).** Chip = identity only, or identity + prep? Method chips read the identity live off the line item; prep is a per-use ingredient-list concern, so I lean **chip = identity only** (moot for v1 since chips are fixed, but decide the render).
- **Copy for the recon prep label:** "⌗", "prep:", or an unlabelled muted chip. Minor.

---

## 7. Point 2 — Search should SUGGEST (not open blank)

The no-match / override path opens `showReconcileIngredientSheet` → `_ReconcileSheet`, which **already** uses `useIngredientSearch` and `PickerShell` — and `useIngredientSearch` **already** seeds recents on an empty query and returns the create-new row. So the bones are right; the gap is that the sheet opens with the search field *empty and autofocused*, showing recents, rather than pre-loaded with **candidates for this specific line**.

### 7.1 Recommendation: pre-seed the picker with this line's candidates

When opening the sheet for a line, pass the line's context so the results list opens **already showing the best guesses**, ranked:

```
✕  Match "Aleppo chilli flakes"
──────────────────────────────────────────────
⌕ Aleppo chilli flakes                         ← pre-filled query, not blank
──────────────────────────────────────────────
SUGGESTED FOR THIS LINE
  Chilli flakes            Spice · has density   +   ← server candidates (if any)
  Aleppo pepper            Spice                  +   ← typo-tolerant vocab hits
  Red pepper flakes        Spice                  +
RECENT
  Garlic  ·  Olive oil  ·  Parmesan                  ← useIngredientSearch recents
──────────────────────────────────────────────
＋ create "Aleppo chilli flakes" as a new ingredient   ← raw text as create-new
```

Concretely:

- **Seed the query with the raw `ingredient_text`** (or the resolved name on a re-open), so the deterministic vocab search (`repo.search`) fires immediately and the list is populated on open — never blank. This is a one-line change to how `_ReconcileSheet` initialises (`useIngredientSearch` already runs `run('')` on mount; run it with the seed instead).
- **Show the server's `MatchCandidate`s first**, under a "Suggested for this line" header, above recents — these are the cascade's ranked near-matches (`ReconLine.candidates`) the line already carries. For a `none` line with empty candidates, fall back to the vocab search over the seed text (which is typo-tolerant via the 7.4 normalizer). Either way the user sees options immediately.
- **Recents** stay (they're free from `useIngredientSearch`) — a household reaching for the same ten things benefits.
- **Create-new** stays as the footer, pre-named with the raw text, exactly as today (`_CreateNewRow`). This is the "raw text as a create-new option" ask — already present, just keep it.

This is mostly **reuse + reorder**: the picker components exist; the change is (a) seed the query, (b) render `candidates` as a top section. No new picker.

### 7.2 Sub-decisions for Simon

- **Candidate source when the band is `none`.** `none` lines carry *empty* server candidates by contract (no silent auto-stub). So "Suggested for this line" on a `none` line = client-side vocab search over the raw text. Confirm that's acceptable (it's the same typo-tolerant offline search the manual picker uses — §10 of the spec blesses it for human-picks).
- **Header wording:** "Suggested for this line" vs "Did you mean?" (the triage card already says "Did you mean?" — keep them distinct or unify?).

---

## 8. Point 5 — Full editable recipe preview before commit

After triage, show the **actual recipe** — the thing being saved — and let the user edit it, before commit. Today the flow just ends at the line list.

### 8.1 Recommendation: reuse the recipe editor as the preview surface

The `RecipeEditorView` already renders and edits everything preview needs: title, servings stepper, grouped ingredients with the tap-to-edit amount chips, and a method field. **Build preview by feeding the reconciled result into the editor** (or an editor-shaped read-mostly variant), rather than inventing a preview screen.

```
‹ Review recipe                                        [ Save ]
──────────────────────────────────────────────────────────────
TITLE
  Weeknight Tomato Pasta                                   ✎
SERVES   – 2 +
──────────────────────────────────────────────────────────────
INGREDIENTS                          amount · ingredient · notes(prep)
  200 g     Spaghetti                                        ✎
  2 cloves  Garlic              finely chopped               ✎   ← 3 parts §6
  400 g     Chopped tomatoes                                 ✎
  a pinch   Aleppo chilli flakes  toasted                    ✎   ← use 1 §4
    extra     └ (same)            to serve                   ✎   ← use 2, own prep
  ── To finish ──
  30 g      Parmesan            grated                       ✎
  a handful Fresh basil                                      ✎
──────────────────────────────────────────────────────────────
METHOD                                          (chips fixed — v1)
  ① Boil the [spaghetti 200g] for [9–11 min].
  ② Soften the [garlic], add the [tomatoes] and a
     [pinch of chilli], then simmer [10 min].
  ③ Toss through with [the sauce and cheese], finish
     with [basil].
     ⓘ Method text is read-only in v1 — chips render,
        editing lands later.
──────────────────────────────────────────────────────────────
                        [  Save recipe  ]
```

- **Ingredients block = the recipe editor's group/line editors**, so amount edits reuse the 7.7 sheet (§5) and prep shows per §6. Sibling uses (§4) render as stacked rows. Removing/adding a line, renaming a group, adjusting servings — all already in `RecipeEditorView`.
- **Method = the recipe *page*'s tokenized renderer** (`_TokenizedStep` / `foldMethod`), **read-only in v1.** Chips render with live amounts off the line items; timers render. This is the fixed-chips-in-v1 constraint made concrete: the reader from `recipe_view.dart` is reused, the editor's @-mention picker is **not** built yet.
- **Save** here builds the `CommitPayload` (`buildCommit`) and commits — the current bottom-of-list button moves to this screen.

### 8.2 Where editable chips slot in later

`recipe_view.dart`'s `_MethodTab` already branches: tokenized steps → chip fold, else plain text. The spec (§4.6) says the manual editor gets an @-mention picker on the *same token model*. So the later upgrade is: swap the read-only `_TokenizedStep` for an editable variant that lets a tap on a chip re-target its `refs`, and a `@` in the text drop a new `RefToken`. **Design the v1 preview so the method block is a self-contained widget** (`ReadOnlyMethod(steps, lineItems)`) — then v2 replaces that one widget with `EditableMethod` without touching the rest of preview. Note it in the code as the seam.

### 8.3 Sub-decisions for Simon

- **Preview: editor reused directly, or a preview-flavoured wrapper?** The editor has filing (book/section), shelf-life, and freezer fields that don't belong mid-import (or do they? — filing an import on the way in is arguably nice). Decide: full editor (filing + shelf life included) vs a trimmed preview (title/servings/ingredients/method only, file-it-later). I lean **trimmed** for the first pass — an import wants to land fast; filing and shelf-life can be a gentle post-save nudge.
- **Is method truly read-only, or read-only-except-plain-text?** Simplest v1 = fully read-only method (chips + prose both locked). Slightly more useful = prose editable, chips fixed. The contract stores tokens, so editing prose without breaking chips is fiddly — I lean **fully read-only method in v1**, with a one-line "edit after saving" affordance (the recipe page's existing Edit route).
- **Back from preview** returns to triage with resolutions intact (cheap — same state). Confirm that's the expected gesture vs. a forward-only flow.

---

## 9. Point 6 — The coherent flow + "2 to review"

Pulling it together, the sequence and where each redesign point lives:

```
INTAKE ──▶ TRIAGE ─────────────▶ PREVIEW/EDIT ──▶ COMMIT ──▶ recipe page
  §2        §3 shell               §8 editor reuse   buildCommit
            §4 grouped uses        §4 stacked uses   (unchanged)
            §5 amount override     §5 amount chips
            §6 prep chips          §6 prep display
            §7 suggesting picker   method = fixed chips
            "N to review" count
```

**"2 to review" is the organising promise of the whole flow:** the number is small and truthful *because* auto-matched lines fold (§3) and sibling uses collapse to one decision (§4). The design board already drew "2 to review" — this makes the layout finally earn it. If import is clean (all `auto`, mappable units), triage shows **"0 to review — looks good"** and the user can go straight to preview: the flow degrades gracefully to near-one-tap for the happy path, which is most weeknight imports.

### 9.1 State-machine sub-decision (the one real architecture call)

Preview needs to live *somewhere*. Two options:

- **(A) Preview is a new sub-phase of `ImportReconciling`** — add a `phase: triage | preview` flag; the same state object carries payload + resolutions throughout; the view switches body. Cheap, keeps everything in one controller, back/forward is free. **I lean this.**
- **(B) Preview is a new route** pushed after triage, fed the reconciled result. Cleaner separation, but you must thread payload + resolutions to the route and back on edits, and Save has to reach back into the import controller.

Recommend **(A)** — it's the smaller change and matches how `ImportReconciling` already holds the working state.

---

## 10. Components: reuse vs build

| Need | Reuse (exists) | Build / change |
|---|---|---|
| Intake | `_IntakeForm` | copy tweak only |
| Triage shell | `ReconciliationBody` scaffold, `_WarningsBanner`, `_ServingsRow` | split lines into **needs-you / auto-matched**; collapsible auto section |
| Recon line card | `ReconLineCard`, `_Resolver`, `_Pill`, `_RangeButtons` | reorder (raw → prep → amount → resolver); make auto rows collapsed |
| Grouped uses (§4) | stub-coalescing in `buildCommit`; view grouping over `flatLines` | "used N ways" card; fan one identity decision to sibling `LineResolution`s; per-use amount **+ prep** kept separate |
| Suggesting picker (§7) | `showReconcileIngredientSheet`, `useIngredientSearch`, `PickerShell`, `IngredientResultList`, `_CreateNewRow` | seed query with raw text; render `candidates` as a top "Suggested" section |
| Amount/unit override (§5) | `showQuantityUnitSheet` + `QuantitySaved` (7.7); `_LineItemEditor` tap-chip + stub stand-in pattern | lift the amount chip into the recon card; add a unit setter to `LineResolution` |
| **Three-part line (§6)** — amount · ingredient · notes(prep) | `LineResolution.notes`, `RawLineItem.notes`, `LineItem.note` (all exist) | **rewrite `recipe_view.dart` `_LineRow`** into three regions; stack sibling uses; per-use prep chip in recon card; mirror the row in preview |
| Preview/edit (§8) | `RecipeEditorView` (title/servings/groups/lines), `showQuantityUnitSheet`, the new three-part line renderer | trimmed "preview" wrapper; wire "Review recipe →" and Save→`buildCommit` |
| Method chips (fixed v1) | `recipe_view.dart` `_TokenizedStep`, `foldMethod`, `_IngredientChip`, `_TimerChip` | wrap as a self-contained `ReadOnlyMethod` widget (seam for future editable chips) |
| Commit | `buildCommit`, `CommitPayload`, repository | none — contract frozen, path unchanged |

**Net:** almost everything is reuse + reorganise. The genuinely new pieces are (1) the triage split with a collapsible auto section, (2) the "used N ways" grouped-uses card with per-use amount **and prep**, (3) the **three-part ingredient line** (amount · ingredient · notes/prep) that the recipe page, preview, and recon card all share — the one real rendering change on the *recipe view* side, and (4) the thin preview wrapper around the editor + read-only method. No frozen-contract changes; no new pickers; no new match logic.

---

## 11. Open decisions for Simon

A consolidated list of every call flagged above — these are the "react to this" points:

1. **Triage threshold (§3.3).** What lands in "needs you"? Specifically: do low-confidence *auto*-matches surface in triage, or stay folded and get caught in preview? (I lean: fold them — protect the small "2 to review" number.)
2. **Group headings in triage (§3.3).** Drop them from the triage work-queue and reintroduce in preview? (I lean yes.)
3. **Grouping seam for multiple uses (§4.3).** Auto-group only exact `ingredient_text` siblings; *offer* merge when two differently-worded lines resolve to the same ingredient? Force or just suggest?
4. **Recipe-page rendering of multiple uses (§4.3).** Two rows always, or combine-with-expand when units allow? (I lean two rows.)
5. **Use qualifier source (§4.3).** Wire the step `portion.qualifier` ("to serve") into the second use's label, or leave it as raw `raw_amount` text?
5a. **Three-part line adoption (§6.1–6.2).** Confirm the recipe page moves to `amount · ingredient · notes(prep)` with sibling uses stacked — this is a change to the live recipe view, not just import.
5b. **Multi-qualifier prep render (§6.4).** Verbatim "peeled and diced", or split into "peeled · diced" chips? (I lean verbatim on the page, split only in the editable recon chip.)
5c. **Sibling-use identity cell (§6.4).** "└ (same)", greyed repeat, or blank? (I lean the "└" continuation.)
5d. **Notes region occupancy (§6.4).** Prep-only in v1, or prep + a separate free note? (I lean prep-only, note folds in later.)
6. **"tin" as a presentable measure (§5.2).** Confirm the 7.7 sheet (per the mechanics subagent) can offer "tin" so "1 × 400 g tin → 400 g" doesn't force hand-conversion.
7. **Override clears the unmappable flag (§5.2).** A successful unit override should drop the "unit needs a look" badge — confirm.
8. **Prep in method chips (§6.2).** Chip = identity only, or identity + prep?
9. **prep vs general note (§6.2).** Is prep the only v1 qualifier, or keep a separate free-text note slot too?
10. **Prep render on recipe page (§6.1).** Option A (inline muted modifier) vs Option B (secondary line). (I lean A.)
11. **Candidate source for `none` lines in the picker (§7.2).** Confirm client-side vocab search over raw text is the right "Suggested for this line" source when server candidates are empty.
12. **Preview scope (§8.3).** Full editor (with filing + shelf-life) vs trimmed preview (file/shelf-life later). (I lean trimmed.)
13. **Method editability in v1 (§8.3).** Fully read-only method, or prose-editable-chips-fixed? (I lean fully read-only, with the existing post-save Edit route as the escape hatch.)
14. **Preview state placement (§9.1).** Sub-phase of `ImportReconciling` (A) vs new route (B). (I lean A.)

---

*This is a proposal to react to, not a spec to build. Every recommendation is grounded in the current code and the frozen contract; nothing here requires changing `types.ts` or the gold schema. The heaviest new work is the triage split and the grouped-uses card — everything else is reuse and reorder.*
