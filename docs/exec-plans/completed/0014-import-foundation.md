# Exec plan: Import foundation — the frozen neck (W0)

- **Status:** done (frozen 2026-08-30, gold blessed by Simon; lanes A–D fanned out
  and landed — step 8 shipped 2026-08-31)
- **Owner:** Simon + Claude (foundation done solo, before any fan-out)
- **Roadmap step:** Step 8 — AI/deterministic import
- **Created:** 2026-08-30

## Goal

Freeze the **shared contracts, golden fixtures, and (minimal) schema** that let the
four downstream lanes — extraction (A), matching (B), client (C), and the provider
benchmark (D) — be built **in parallel by separate agents without drifting**. When
this lands, every lane codes against frozen types + example JSON, not against each
other. This file is the **freeze reference**: a change to a contract here is a
coordinated change across every lane, so it is reviewed and locked before fan-out.

Step 8 is a **DAG, not a linear plan** (see the roadmap + [ADR-0004](../../decisions/0004-matching-is-online-only.md)):

```
W0 (this file) → { A extraction · B matching · C client · D benchmark } → tail (integration)
```

The design these contracts encode was settled in a design session (decision log
below). The headline: **one forced LLM path** (JSON-LD is a cheaper *input*, not a
bypass); a **vocab-blind but unit-aware** sanitize/align stage; **deterministic,
server-side matching** (ADR-0004 intact); **user-driven** no-match resolution; and
**LLM within-recipe** step→line alignment. This revises spec §4/§6 (owned by the
tail) and **reaffirms** ADR-0004 without amending it.

> **INVARIANT — extraction never invents.** The pipeline must NEVER fabricate an
> ingredient, quantity, unit, time, serving count, or step that is not present in
> the source. Absent or ambiguous ⇒ **flag it to the user** (via `parse_warnings`,
> low `confidence`, or an explicit "needs input" band), never guess a value in.
> This extends "honest numbers" to import and is a **scored, disqualifying**
> dimension of the provider benchmark (the force-fit / hallucination ledger). It is
> the reason the human sits in the reconciliation loop.

## Acceptance criteria

- [x] `supabase/functions/_shared/types.ts` extended with every contract below, each
      with a doc comment pointing at its spec section. Types only — no logic.
- [ ] ~~`supabase/functions/_shared/contracts/` golden fixtures: one committed example
      JSON per contract (raw blob, `ExtractionResult`, reconciliation payload, commit
      payload).~~ **Never built — superseded, deliberately.** The lanes needed *real*
      fixtures, not hand-written ones, and got them: `evals/datasets/extraction/gold/`
      (11 human-blessed labels, the `ExtractionResult` oracle) plus the committed
      `supabase/functions/import-recipe/__fixtures__/reconciliation_payload.golden.json`
      (the TS→Dart payload contract test's shared fixture). A hand-written third copy
      would have been a fourth source of truth to keep in step.
- [x] Provider-adapter interface (`ExtractAdapter`) defined — the seam shared by lane
      A (impl) and lane D (comparison).
- [x] Step-token model pinned with example JSON in **both** shapes: extraction
      (refs by **line index**) and stored (refs by **`line_item_id`**), plus the
      index→uuid remap rule for commit (§4.6).
- [x] Schema decision recorded: **one** migration after all —
      `0013_recipe_times.sql` (`recipe.cook_time_seconds` / `total_time_seconds`,
      from the gold-review decision below); `make docs` regenerated `db-schema.md`.
- [x] Four lane charters exist (`0015`–`0018`) and the integration plan (`0019`),
      each referencing this file's contracts. (All six now live in `completed/`.)
- [x] `docs/product-specs/import-and-matching.md` §4/§6 flagged for the tail's rewrite
      (a TODO marker + a pointer here), so the stale-doc rule isn't silently broken
      mid-flight. The rewrite itself landed with the step-8 close-out.
- [x] `make analyze` / deno check clean on the new types + fixtures.

## The contracts (freeze reference)

All live in `supabase/functions/_shared/`. `normalize.ts` (§7) and the existing
`ExtractionResult`/`MatchedLine` skeletons in `types.ts` are the starting point.

### 1. `RawBlob` — extraction input to the sanitize stage (lane A → lane A/D ①)

The union output of intake. **Lane A** produces it (JSON-LD parse or page text);
**vision transcription** (lane D's cheap tier) produces the `text` variant from
images. The sanitize stage consumes only this — it never sees the URL or the image.

```jsonc
{
  "source": "jsonld" | "page_text" | "transcription",
  "url": "https://…" | null,          // provenance only; sanitize ignores it
  "jsonld": { /* raw schema.org/Recipe object, when source=jsonld */ } | null,
  "text": "…raw recipe text…" | null  // page text or vision transcription
}
```

### 2. `ExtractionResult` — output of ① sanitize·structure·align (§4.4)

Extends the existing skeleton. **Ingredient-blind, unit-aware.** `ingredient_text`
is preserved **as-written** (feeds §7 normalize *and* the learning-loop alias);
only `qty`/`unit` are normalized toward our unit vocab, and an unmappable amount is
preserved faithfully + flagged, never force-fit (honest numbers).

```jsonc
{
  "title": "Weeknight Chicken Curry",
  "servings_base": 4,
  "image_quality": "ok" | "degraded" | "poor",
  "parse_warnings": ["…"],
  "groups": [
    { "name": "for the curry", "line_items": [
      { "qty": 900, "unit": "g", "ingredient_text": "chicken thighs, boneless",
        "unit_mappable": true, "confidence": 0.97 }
    ]}
  ],
  "steps": [                          // tokenized; refs by LINE INDEX at extraction
    { "tokens": [
        { "t": "text", "s": "Dice the " },
        { "t": "ref",  "line_index": 3, "label": "onion", "mention": "new" },
        { "t": "text", "s": " and soften." }
      ], "timer_seconds": 600 }
  ]
}
```

- `line_index` indexes the **flattened** line-item order of this same extraction
  (§4.6 — alignment is within-recipe, never vocabulary). `refs` may be a set for
  collective chips ("the dry ingredients").
- `mention`: `"new" | "rementioned" | "fraction"` — the LLM's semantic classification
  (replaces the spec's brittle "first index carries the number" heuristic). The chip
  still derives its number **live** from the line item; `mention` only governs
  whether/how the number renders (§4.6). The model never emits a quantity here.
- `unit_mappable`: false ⇒ `unit` holds the original phrase; UI/edit resolves it.

### 3. `ExtractAdapter` — the provider seam (lanes A + D)

```ts
interface ExtractAdapter {
  name: string;                        // "gemini-flash" | "gpt-5-mini" | "claude-haiku" | "jsonld"
  transcribe?(images: Uint8Array[]): Promise<RawBlob>;     // vision tier (LLM)
  sanitize(blob: RawBlob, unitHints: UnitHints): Promise<ExtractionResult>; // ① (LLM)
}
```

`unitHints` = our canonical units + accepted imprecise words + size words (NOT the
ingredient vocab, NOT per-ingredient measures). Sourced from `app/lib/core/units`
mirrored server-side. Lane D swaps adapters to compare providers; lane A wires the
chosen one at the tail. `jsonld` adapter has no `transcribe` and a trivial `sanitize`
passthrough shape (real sanitize is always an LLM — see decision log).

### 4. Match output — bands + candidates (§6, lane B)

Existing `MatchBand` / `MatchCandidate` / `MatchedLine` stand, with one change: **no
silent auto-stub**. Band `none` carries empty candidates and the raw text; the
*user* resolves it at reconciliation (search / create-new). Within-import dedupe of
identical `none` lines is a client concern (see payload note).

### 5. `ReconciliationPayload` — edge fn → app (lanes B, C)

What `import-recipe` returns; what lane C's fake edge fn emits.

```jsonc
{
  "title": "…", "servings_base": 4,
  "image_quality": "…", "parse_warnings": ["…"],
  "groups": [ { "name": "…", "lines": [
    { "raw": { "qty": 900, "unit": "g", "ingredient_text": "chicken thighs, boneless" },
      "band": "auto" | "suggest" | "none",
      "candidates": [ { "ingredient_id": "…", "canonical_name": "Chicken thigh", "score": 0.91 } ] }
  ]}],
  "steps": [ /* ExtractionResult.steps, refs still by line_index */ ]
}
```

### 6. `CommitPayload` — app → PowerSync (lane C)

Client-built after the user resolves every line. **`recipe_line_item.ingredient_id`
is NOT NULL** — every line must resolve to a real or just-created ingredient before
commit; there is no dangling line. On commit, `steps[].tokens[].ref.line_index`
remaps to the created `line_item_id` (§4.6). Stub creation (`status='stub'`,
`source='import_stub'`) and correction aliases (`source='import_correction'`) write
through the normal sync queue — no new tables.

## Schema decision

**No migration required.** Confirmed against the live schema:

- `recipe.steps` is `jsonb` — tokenized steps are a *content-shape* change; data is
  ephemeral ([mise-data-ephemeral], no back-compat). Domain types + validation change
  in lane C; SQL does not.
- `recipe_line_item.id` is a UUID — refs point at it post-commit.
- `ingredient.source` already allows `'import_stub'`; `status` defaults `'stub'`.
- `ingredient_alias.source` already allows `'import_correction'`.
- The flesh-out queue is a **view over** `ingredient WHERE status='stub'` — no table.

If a lane discovers a genuine schema need, it routes back **here** (W0 owns all
migrations) to avoid numbering collisions across parallel branches.

## Approach

1. Extend `types.ts` with contracts 1–6; keep it logic-free.
2. Add `_shared/contracts/*.json` golden fixtures (one per contract), hand-written
   from a real example (reuse a `recipe_urls.txt` page).
3. Define `ExtractAdapter` + `UnitHints`; add a `unit_hints.ts` that derives the hint
   set from the unit system (single source).
4. Write the four lane charters (`0015`–`0018`) + integration (`0019`), each linking
   these contracts and stating its fixtures-not-live boundary.
5. Mark spec §4/§6 for the tail's rewrite; reaffirm ADR-0004 (no amendment).
6. Freeze: Simon reviews this file → then fan out A/B/C/D as parallel agents.

## Decision log

- 2026-08-30 — **One forced LLM path.** JSON-LD is a cheaper *input* to the shared
  pipeline, not an LLM-free bypass. Kills path branching; the JSON-LD chip-alignment
  gap (spec §4.1 vs §4.6) disappears. "LLM uptime is all nines"; import was
  online-only anyway (ADR-0004), so no capability lost.
- 2026-08-30 — **Sanitize is ingredient-blind, unit-aware.** ① gets our unit/measure
  vocab + structuring rules as *hints* (bias, don't constrain — preserve unmappable
  amounts), never the ingredient vocab. Keeps ADR-0004's matching stance and keeps ①
  text-fixture testable. `ingredient_text` stays as-written (learning-loop signal).
- 2026-08-30 — **Matching stays deterministic + server-side** (exact → trigram/typo →
  bands). LLM-over-household-vocab is **back-pocket only**, if evals show a synonym
  gap trigram + learned aliases can't close. ADR-0004 reaffirmed, unamended.
- 2026-08-30 — **LLM does within-recipe step→line alignment** (`mention`:
  new/rementioned/fraction), replacing the "first index carries the number"
  heuristic. Not vocabulary matching — stays inside ADR-0004. Chips never carry an
  LLM number; they reference a line and inherit its quantity live.
- 2026-08-30 — **No silent auto-stub.** Band `none` surfaces to the user
  (search / create-new → stub they flesh out, USDA-prefilled). Within-import dupes
  coalesce onto a just-created ingredient. Keeps human agency (spec §8).
- 2026-08-30 — **Vision = faithful transcriber + shared sanitize** (2 calls on
  photos), so transcription and sanitize models vary independently.
- 2026-08-30 — **Provider choice is an evidence lane (D), not a guess.** A benchmark
  harness scores Gemini Flash / GPT-5 Mini / Claude Haiku on a labeled dataset (36
  `recipe_urls.txt` pages + `out/needs_fallback.txt` hard cases + Simon's photos) and
  outputs the pick. D is the one lane that uses real API keys, early, on purpose; it
  also is where the transcription + ① prompts are developed. Exact model IDs +
  per-provider vision/structured-output support pinned via the `claude-api` reference
  when D's charter is written.
- 2026-08-30 — **Reuse:** `mine_recipes.ts` already parses schema.org/Recipe JSON-LD
  and splits `{qty,unit,text}`; lane A ports it. `out/needs_fallback.txt` = ready
  hard cases for the vision path.

### Contract decisions from the gold-drafting review (2026-08-30)

Drafting gold on the 11 real photos stress-tested the line/step contract; these
lock its shape (source: the `_review` flags in `evals/datasets/extraction/gold/`).

- **Never invent** (promoted to the invariant above). The gold-drafter flagging its
  own uncertainty instead of guessing is the behavior the runtime pipeline and the
  benchmark both enforce.
- **Multi-pack cans → numeric count, grams via the measure.** `"2½ × 400 g cans"`
  is `qty: 2.5, unit: "can"` (NOT `null`) — the gram basis rides our existing
  `ingredient_measure` (step 7.6; we already store e.g. `can = 454 g`). Preserve the
  printed **drained weight** (`"about 600 g drained"`) too — for canned produce the
  drained weight is what's used; handling it is a measures-side nuance (the `can`
  measure may need a drained basis), flagged, not blocking.
- **Ranges are resolved by the user at import.** `"4 to 6"`, `"2–3 cups"` →
  contract carries `qty_low` + `qty_high` (faithful, never collapsed); the
  reconciliation UI surfaces the range and the user picks. No silent auto-pick — same
  human-in-the-loop as no-match.
- **Servings: always attempt a number, flag when unclear.** ① emits a best-effort
  integer `servings_base`; genuinely unclear (`"Makes 1 cup"`, a bare yield) ⇒
  `servings_base: null` + `servings_raw` preserved + a flag for the user to set it.
  `"Makes 8 sliders"` = 8 portions; `"1 cup"` (a staple/component) is a real null.
- **Timers are ranges, and per-token.** `timer_seconds` → `timer_low`/`timer_high`
  (`"15 to 20 min"`); multiple times in one step (mint-pea-soup step 1 has three) are
  handled as **timer tokens** in the tokenized step stream (§4.6), not a single
  step field — this also seats cook-mode timers later.
- **Split compound lines.** `"Sea salt and freshly cracked black pepper"` → two
  line items. Real-world line-splitting is exactly why an LLM is in the path.
- **Unresolvable step mentions stay plain text.** A `"pinch of salt"` with no
  matching line ⇒ plain text, no chip (never fabricate a line). **Sub-recipe
  references** (`"Romesco Aioli (page 38)"`, six of them in sausage-sliders) ⇒ plain
  text for now; **nested recipes are a deferred future feature** (new roadmap/tech-
  debt item — the tail records it).
- **Orphan lines are normal.** An ingredient never named in a step gets no chip; not
  an error, no handling needed.
- **Printed metadata:** **keep cook time + total time** (`recipe` gains nullable
  `cook_time_seconds` / `total_time_seconds`; a range uses low/high like timers — this
  is W0's one real migration). **Ignore printed nutrition** — an unverifiable number
  would break never-invent; we compute macros ourselves. Fridge-life → existing
  `recipe.keeps_for_days`, import auto-fills it.

### Step-token model — sub-quantities (2026-08-30, from the parsley case)

The flat "ref → line total" token model can't represent `"2 tbsp + ½ cup parsley"`
used across three steps. Two separable problems:

- **Compound *amount* on one line** (`"2 tbsp + ½ cup"`, same ingredient): the line
  total **sums within the family** (reuses `aggregateQuantities` family-summation,
  step 6) → `0.625 cup`. Cross-family compounds that can't bridge stay honest
  subtotals — never force a conversion. The split only matters for steps, below.
- **Per-step sub-quantity → an OPTIONAL `portion` on the ref token** (pulls spec
  §4.6's deferred portion-token forward):

  ```jsonc
  { "t": "ref", "refs": [7], "label": "parsley", "mention": "rementioned",
    "portion": { "qty_low": 2, "qty_high": 2, "unit": "tbsp",   // FROM STEP TEXT, or
                 "qualifier": "the rest" | "half" | "for garnish" | null } | null }
  ```

  **Rendering is a structured token fold, NOT text-replace** (render-time substring
  detection = the on-device matching ADR-0004 forbids). A ref's displayed number:
  `portion` if the step named one → else the line's scaled qty on **first** mention →
  else quantity-less. A `portion` number is **transcribed from the step text**
  (source-derived, not invented — still "picks references, never invents numbers"); a
  relative word lands in `qualifier` and renders relative, never a made-up amount. If
  step portions don't sum to the line total, **flag it** — never reconcile by
  inventing. Additive: `portion: null` (the common case) behaves exactly as §4.6 v1.

- **Count-on-produce-with-a-transform** (`"Juice of 1 lemon"`, `"Zest of 2 limes"`):
  model the **produce** as the ingredient — `qty: 1, unit: "piece",
  ingredient_text: "lemon"` + a `notes: "juiced"` qualifier (not identity — **match
  the lemon**, Simon's call). Shopping stays honest (buy 1 lemon, never invent a
  juice volume); a measure supplies the derived juice volume for macros when needed.
  When the page gives the volume (`"…(about 3 tbsp)"`), capture `qty: 3, unit: tbsp`
  and keep the lemon count in `raw_amount`. (Bottled-juice households would flip the
  target — not ours.)

## Notes / open questions

- Portion tokens (spec §4.6 "half"/"the rest" → `portion`) stay **deferred** — the
  `mention` field leaves room to add it additively later.
- Multi-image single-call transcription (§4.2) is lane D's; the `RawBlob.text`
  contract already covers a merged multi-page transcription.
- Provider keys arrive at D's run phase, not W0.

## Step-done checklist

W0 is the neck, not a feature step — its "done" is **contracts frozen + lanes
unblocked**, verified by the lanes compiling against the fixtures.

- [x] Contracts committed; `deno check` / `make analyze` clean. (Fixtures: see the
      struck criterion above — the gold set + the golden payload fixture stand in.)
- [x] Four lane charters + integration plan written and cross-linked.
- [x] Roadmap step-8 row annotated "foundation frozen; lanes A–D in parallel"
      (since superseded by the shipped row).
- [x] Simon has reviewed this file (the freeze gate) **before** any agent fan-out.
- [x] Spec §4/§6 marked for the tail's rewrite; ADR-0004 reaffirmed (the note landed
      in the spec's §2 with the step-8 close-out).
