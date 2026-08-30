# Seed data

Two things get seeded (spec §6):

1. **`usda_food`** — USDA FoodData Central (Foundation Foods + SR Legacy, CC0),
   server-side only. The reference set for *creating* ingredients and prefilling
   stubs. Never synced, never matched against at import (ADR-0005).
2. **Initial household `ingredient` vocabulary** — mined from real recipes and
   curated (currently 307 rows), so the app isn't empty on first run. Macros +
   density are prefilled from `usda_food` where a true match exists, plus a
   handful of label-sourced macro fills in the curation pass (271
   `complete`); the rest stay honest `stub`s for the flesh-out queue.

Density: derived from FDC **volume food portions parsed out of the full
portion text** (7.8 — SR Legacy keys most volume portions by `modifier`, not
`measure_unit`, which is why the old parser found almost none). Ranked
cup > tbsp > tsp, unqualified before prepared-state, sanity 0.1–2.0 g/ml.
Curation-pass corrections and fills sit on top (audit 2026-08-29, R1: every
volume-default row carries a density). Current vocab coverage: **264/307**.
FAO/INFOODS Density DB v2.0 remains the planned fallback for the tail
(tracker).

## Building the household vocabulary (`scripts/mine_recipes.ts`)

The initial `ingredient` vocab is mined from recipes you actually cook, not typed
by hand. The pipeline is deterministic where correctness demands it, with an LLM
pass only for offline judgment (never in the runtime matcher — ADR-0004):

1. Paste recipe URLs into `scripts/recipe_urls.txt` (one per line).
2. `cd scripts && deno task mine` — fetches each, reads schema.org/Recipe
   JSON-LD, parses ingredient lines, normalizes with the shared §7 normalizer,
   and writes the raw mining outputs to `scripts/out/` (git-ignored; regenerable).
3. **Curate** `out/gold_labels.jsonl` into the true vocabulary — resolving the
   judgment cases rules can't (a choice like "avocado or sunflower oil" becomes
   *two* ingredients; "fat garlic" folds into Garlic as an alias). This produced
   `vocab.jsonl` (committed — it's judgment, not regenerable). See the flow that
   built it in the git history / `out/audit.md`.
4. `deno task gen-seed` — deterministically turns `vocab.jsonl` into
   `../seed.sql`, computing each `match_text` with the shared normalizer (so
   stored keys stay symmetric with the runtime cascade) and failing on
   collisions. Everything seeds `status='stub'` (density/macros come later).
5. `supabase db reset` applies it.

`vocab.jsonl` is the source of truth; edit it and re-run `gen-seed` to change the
seed — never hand-edit `seed.sql`.

It also emits `gold_labels.jsonl` (for `evals/`), `needs_fallback.txt` (URLs
without JSON-LD, held for the step-8 photo path), `parse_failures.jsonl`, and
`ambiguous_pairs.txt` (near-duplicates to eyeball — never auto-merged).

### The human-merge pass (why curation isn't optional)

The normalizer is deliberately conservative: it will not strip a word that is
noise in one context but identity in another. "fat" is dropped nowhere, because
`duck fat` is a real ingredient — so `fat garlic` survives as its own candidate
even though a human instantly knows it's just `garlic`. "cracked" stays because
`cracked wheat` exists, so `cracked black pepper` won't auto-fold into
`black pepper`. These are correct refusals, not bugs.

Resolving them is a **human pass** on top of the deterministic one: a person maps
the messy surface form onto the real ingredient, and that surface form is kept as
an **alias** (never discarded). `ambiguous_pairs.txt` is the worklist for it.
This is the same shape as the import-time learning loop (import-and-matching.md
§8) — a human correction becomes an alias — and the app's GUI should expose the
same move (merge a stub/ingredient into another, keeping the old name as an
alias) so the vocabulary keeps getting cleaner after seeding, not just during it.

## The USDA reference (`scripts/gen_usda.ts`)

`usda_food` (8262 foods, macros incl. fiber) is built from the USDA FoodData
Central CSV bundles (Foundation Foods + SR Legacy, CC0). The bundles are **not
committed** (~40MB); only the compact generated `../seed_usda.sql` is. To
regenerate:

1. Download + unzip the two CSV bundles from
   <https://fdc.nal.usda.gov/download-datasets> (Foundation Foods, SR Legacy).
2. `deno run --allow-read --allow-write gen_usda.ts <foundation_dir> <sr_legacy_dir>`
   — pass Foundation first so it wins on overlap. Keeps the four macros + fiber
   (per 100 g) and a density derived from the best-ranked volume
   `food_portion` (unit words matched in the whole portion text — see the
   density note above); `match_text` uses the shared normalizer so the
   reference is indexed the same way.

## Ingredient measures (`scripts/gen_measures.ts`)

`../seed_measures.sql` — the template vocab's starter **measures** ("1 potato,
medium = 213 g", step 7.6; amounts in the ingredient's basis unit since
0012's `basis_amount`) — is GENERATED from the same FDC bundles' piece-type
`food_portion` rows, joined through `usda_links.jsonl`, with per-row
provenance in `ingredient_measure.source` (migration 0010). Never hand-edit
the SQL.

```
deno task gen-measures <foundation_dir> <sr_legacy_dir>
```

**Extraction is generous; curation decides** (plan 0013): every portion that
names a physical human unit is emitted — all size classes, fragments (slice,
wedge, strip, cube…), containers, dimension-described portions — ordered
most-kitchen-useful first (container > medium > large > small > extra sizes >
whole > fragment). Still excluded at extraction: pure volume rows (they
become density — see above), prepared-state volume qualifiers, mass aliases,
and nutrition-label servings — except *physically disguised* servings
("serving packet", "slice 1 serving"), which are rescued under their real
names. Then two tiers plus survivors, as before:

- **Tier 1** — each ingredient's OWN linked food's portions; a variety linked
  to a broader food keeps only portions naming the variety, and a food whose
  description carries a basis qualifier (without peel / drained / …) emits no
  whole-item measure unless the row or label owns that basis.
  `source = usda_fdc:<fdc_id> (<portion>)`.
- **Tier 2** — the explicit borrow map (`— borrowed`), plus the automatic
  borrow marker when several vocab rows share one FDC food.
- **`seed:typical` survivors** — the short curated list (incl. the 7 g yeast
  sachet — the near-universal printed standard).

Finally the committed **`../curation_overrides.jsonl`** is applied
(`drop_measure`/`add_measure` here; `density`/`allowed_units` in
`seed_curation.sql`): the audited LLM-curation pass over the generated
output, every override with a reason — rules are scaffolding, the pass is
the decider. A stale drop fails the run.

The generated SQL is idempotent (a `where not exists` guard per live label)
and ends with a check that every seeded match_text still resolves to a live
vocab ingredient.

## Curation overrides (`curation_overrides.jsonl`) & `seed_curation.sql`

`curation_overrides.jsonl` (committed, one JSON object per line, every entry
with a `reason`) records the human/LLM judgment pass over ALL generated
per-ingredient defaults — measures, densities, allowed units, and
label-sourced macros (`kind: "macros"` — per-100 g numbers with a visible
`label:…` source, for rows the no-analogue rule keeps link-less). Consumers:
`gen_measures.ts` (measure drops/adds) and `gen_seed.ts`, which emits
`../seed_curation.sql` — the LAST seed step: it applies the macro fills,
re-materializes the template vocab's `allowed_units` via
`default_allowed_units()` once every density source has run (the insert-time
trigger fired before prefill), then applies the density and allowed-unit
overrides with their reasons as SQL comments.

`seed_curation.sql` ends with the **R1 invariant** (adopted 2026-08-29): a
volume `default_unit` REQUIRES a density — `supabase db reset` FAILS loudly
if any template row is volume-default and density-less (a volume line on a
density-less per-g ingredient can never compute macros). Fix by filling an
honest density (FDC / label / tagged typical) or flipping the default to a
weight — always through the pipeline inputs.

## Prefill: promoting stubs to `complete` (`usda_links.jsonl`)

`usda_links.jsonl` (committed) maps an ingredient's `match_text` → the `fdc_id`
of the USDA row whose food it truly is. These were resolved by trigram for the
easy cases and an LLM arbiter for the judgment ones, under a strict
**no-analogue** rule: a link is only made where the USDA food genuinely *is* the
ingredient — never a stand-in (canned ≠ dry, fruit ≠ its oil, vegan ≠ dairy).
Unmatched ingredients stay `stub`. `gen-seed` reads `usda_links.jsonl` and emits
`../seed_prefill.sql`, which copies macros/density onto matched rows and flips
them to `complete` (a guard skips USDA rows with no macros).

## Load order

`config.toml` `[db.seed].sql_paths` runs, in order: `seed.sql` (household +
vocab) → `seed_usda.sql` (reference) → `seed_prefill.sql` (macros + density)
→ `seed_measures.sql` (measures) → `seed_curation.sql` (allowed-units
refresh + curation overrides). `supabase db reset` applies all five.
