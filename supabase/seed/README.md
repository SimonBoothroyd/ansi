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

Density comes from three sources, in this order, each filling only what the
one before it left empty:

1. **FDC volume food portions**, parsed out of the full portion text (7.8 —
   SR Legacy keys most volume portions by `modifier`, not `measure_unit`,
   which is why the old parser found almost none). Ranked cup > tbsp > tsp,
   unqualified before prepared-state, sanity 0.1–2.0 g/ml.
2. **Curation-pass** corrections and fills on top (audits 2026-08-29 and the
   D4d density pass 2026-09-01). A fill may carry a `source` —
   `fdc_density:<fdc_id>` when it borrows a portion-derived density from
   another FDC record of the same food, `label:…`, or `typical:…` — which is
   appended to the row's own `source` so the density's provenance is
   readable off the row, like the FAO tag below. Never `usda_fdc:<id>`:
   that prefix means the MACROS came from FDC and the generator refuses it.
3. **FAO/INFOODS Density Database v2.0** as the fallback for the tail, via a
   reviewed mapping — see `scripts/fao_density.md`. Never overwrites 1 or 2:
   every fill carries a `density_g_per_ml is null` guard.

Current vocab coverage: **296/307** (264 → 277 when the FAO fallback landed,
then → 296 in the **D4d density pass**, plan 0020 batch 5). D4c admits only
the BASIS family on a density-less row, so a bare row silently refuses every
volume line; the pass re-read all 30 remaining rows and filled 19 of them.
Most were bare only because `usda_links.jsonl` links them to an FDC record
with no volume `food_portion` while a **sibling record of the same food**
carries one (gala apple, dill pickle, plantain, tofu…) — cited per row as
`fdc_density:<fdc_id>` in `curation_overrides.jsonl`. The FAO rejections
were not relitigated: FAO v2.0 still has no tofu, tortilla, seaweed or
mushroom row. The 11 rows still bare are enumerated with their reasons in
the overrides file's round-3 header — each is now a decision, not a gap.

Two invariants hold at `db reset` (`seed_curation.sql`): **R1**, a volume
`default_unit` requires a density; **R2**, every stored density lands in the
kitchen band 0.03–2.0 g/ml.

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

> **A normalizer change reaches this file too.** When the shared normalizer
> changes what it writes, the committed `seed_usda.sql` is stale until the
> bundles are re-run — and it is 8,204 plain inserts, so it seeds a *fresh*
> database only. The plan-0023 invariant-word fix (`molasses`, migration
> `0022`) applied the identical whole-word rewrite (`molass` → `molasses`,
> five rows) to the committed file by hand, the same precedent as the
> measure edits below, so a fresh reset and a migrated database agree. A
> regeneration from the bundles reproduces it verbatim.

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

> **Regenerating without the CSV bundles.** `gen-measures` needs the ~40 MB
> FDC bundles, which are deliberately not committed. The plan-0022 measure
> edits (broccoli `bunch` → `whole`, cherry tomato's borrowed `cherry`
> dropped, ginger's `piece, 1 inch`) were therefore recorded as
> `drop_measure`/`add_measure` overrides — the real source of truth — and the
> identical transformation was applied to the committed `seed_measures.sql`
> by hand. Any run of `gen-measures` against the bundles reproduces it
> verbatim: drops are label-exact, and an added row lands by its
> `sort_order`. If a future edit is bigger than a handful of rows, fetch the
> bundles and re-run the generator rather than extending the hand pass.

## Curation overrides (`curation_overrides.jsonl`) & `seed_curation.sql`

`curation_overrides.jsonl` (committed, one JSON object per line, every entry
with a `reason`) records the human/LLM judgment pass over ALL generated
per-ingredient defaults — measures, densities, allowed units, and
label-sourced macros (`kind: "macros"` — per-100 g numbers with a visible
`label:…` source, for rows the no-analogue rule keeps link-less). Consumers:
`gen_measures.ts` (measure drops/adds) and `gen_seed.ts`, which emits
`../seed_curation.sql` — the LAST seed step, in this order: macro fills →
density overrides → **FAO density fallback** (`scripts/fao_density.md`) →
re-materialize `allowed_units` via `default_allowed_units()` now that every
density source has run (the insert-time trigger fired before prefill) →
produce volume leg → allowed-unit overrides. Every override's reason is
emitted as a SQL comment so the generated file stays auditable on its own.

**The `piece` pass (2026-09-02, plan 0022 / [ADR-0010](../../docs/decisions/0010-piece-is-an-admission-fact.md)).**
`piece` means "a whole one of these, and we have nothing better to call it".
Where the vocabulary *does* have something better — a clove, an avocado, a
medium potato — `piece` is not admitted at all, so nothing at runtime ever has
to guess which measure a `piece` meant. That is an **admission fact** in the
explicit `allowed_units` list, not a derived rule: deriving it would put
`piece` back on broccoli and take it off ginger. All **142** seeded rows that
carry a measure were read and ruled on by hand (the tables in
`docs/exec-plans/active/0022-piece-curation.md`), and each landed here as one
`{"kind": "allowed_units", …, "remove": ["piece"]}` line with its reason. 66
of those removals are no-ops today — those rows are mass- or volume-default
and never got `piece` from the rule — and are written anyway, because the file
is the decision record and the ruling must outlive a change of default unit.
`default_allowed_units()` and its Dart mirror are deliberately **unchanged**: a
measure-less count row must still get `piece`. In the seeded template that case
turns out never to arise — all 76 count-default rows carry a measure — so after
the pass **no seeded row admits `piece` at all**; the fallback is there for the
ingredients a household creates itself. Rollout is a **reseed**, never a
migration (ADR-0009 rule 3 forbids a backfill that removes from a list the
household owns). The safety net is a pgTAP assertion in
`../tests/unit_admission.sql`, not a second stored copy of the rule.

**Produce volume leg.** ADR-0008's density leg fires only for mass/volume
defaults — a count default gets nothing from a density, because "a density
can't describe a piece". Produce is where that stops being true: "1 cup diced
mango" is an ordinary recipe line, the row is legitimately piece-default, and
the density is exactly what makes the cup computable. Without this, every
cup-measured produce import failed *"Pick a supported unit"* despite the row
carrying an honest density all along. It is category-gated (like the imprecise
leg beside it) and applies only where a density exists. **The rule belongs in
`default_allowed_units()` and its `allowed_units.dart` mirror** — until
ADR-0008 is amended, the template vocab carries the honest list explicitly,
which `allowed_units` being an explicit stored attribute exists to allow.

`seed_curation.sql` ends with two invariants — `supabase db reset` FAILS
loudly on either:

- **R1** (adopted 2026-08-29): a volume `default_unit` REQUIRES a density (a
  volume line on a density-less per-g ingredient can never compute macros).
  Fix by filling an honest density (FDC / FAO / label / tagged typical) or
  flipping the default to a weight — always through the pipeline inputs.
- **R2**: every stored density lands in the kitchen band **0.03–2.0 g/ml**,
  whatever its source. Catches the wrong physical quantity (FAO publishes
  salt at 2.165 — a crystal density, not what a spoonful weighs) without
  second-guessing the genuinely light end (dill 0.038).

## Prefill: promoting stubs to `complete` (`usda_links.jsonl`)

`usda_links.jsonl` (committed) maps an ingredient's `match_text` → the `fdc_id`
of the USDA row whose food it truly is. These were resolved by trigram for the
easy cases and an LLM arbiter for the judgment ones, under a strict
**no-analogue** rule: a link is only made where the USDA food genuinely *is* the
ingredient — never a stand-in (canned ≠ dry, fruit ≠ its oil, vegan ≠ dairy).
Unmatched ingredients stay `stub`. `gen-seed` reads `usda_links.jsonl` and emits
`../seed_prefill.sql`, which copies macros/density onto matched rows and flips
them to `complete` (a guard skips USDA rows with no macros).

## Density fallback (`fao_density_links.jsonl`)

`fao_density.jsonl` (the FAO/INFOODS Density Database v2.0 table, derived and
committed) + `fao_density_links.jsonl` (the reviewed vocab → FAO mapping, every
line with a reason, `"fao_food": null` recording an audited rejection). The
last density source, filling only the tail the FDC derivation and the curation
overrides leave. Full detail, licence note and refresh steps:
**`scripts/fao_density.md`**.

## Load order

`config.toml` `[db.seed].sql_paths` runs, in order: `seed.sql` (household +
vocab) → `seed_usda.sql` (reference) → `seed_prefill.sql` (macros + density)
→ `seed_measures.sql` (measures) → `seed_curation.sql` (curation overrides +
FAO density fallback + allowed-units refresh). `supabase db reset` applies
all five.
