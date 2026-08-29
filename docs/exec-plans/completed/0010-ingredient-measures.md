# Exec plan: Ingredient measures & portions

- **Status:** done (2026-08-28)
- **Owner:** agent (staged 2026-08-27)
- **Roadmap step:** Step 7.6 — ingredient measures & portions
- **Created:** 2026-08-27

## Goal

Ingredients gain **named measures with gram weights** ("1 potato, large =
299 g", "1 portion = 30 g", "1 can = 400 ml"), synced per household — powering
honest conversions for count foods (only 7/291 vocab rows have a density
today, and a liquid density can't describe a potato anyway), ingredient-aware
unit choices, whole-unit rounding, and the batch-level cook nudge. This is the
data model behind the MacroFactor-style unit chips (see plan 0011 for the UI).

## Acceptance criteria

- [x] `ingredient_measure` table (id, household_id, ingredient_id, label,
      grams, sort_order, timestamps, deleted_at) + RLS + grants + publication;
      row in `docker/powersync.yaml` (and the cloud streams file once 0009
      commits it); `schema.dart` entry; jsonb-free so the connector needs no
      new column mapping. *(0009_ingredient_measures.sql; both sync files
      updated in the same change — `check_stream_drift.sh` green at 14
      tables; verified `jsonbColumnsByTable` needs no entry: all columns are
      text/numeric/int.)*
- [x] Domain: a `Measure` concept in the units layer — quantity-in-measure ↔
      grams, honest by construction (no measure, no invented grams; measures
      never bridge to volume without a density). `aggregateQuantities` folds
      measure-quantified contributions into the mass subtotal with provenance
      intact. *(`core/units/measure.dart`: `convertMeasure` /
      `amountInMeasure`, `grams ≤ 0`/NaN refused like a bad density;
      `aggregateQuantities(measured:)` + breakdown lines carry the measure.)*
- [x] Line items can reference a measure: nullable `measure_id` on
      `recipe_line_item` and `shopping_list_contribution` (decision below).
      *(Rows quantified in a measure store `unit = 'piece'` as the honest
      count fallback; an unresolved `measure_id` survives re-saves and
      degrades to a count, never invented grams.)*
- [x] `allowedUnitsFor` v2: current rules (same family; density-gated
      cross-family; imprecise; count-suppression) **plus the ingredient's live
      measures**. *(`allowedUnitChoicesFor` → sealed `UnitChoice`
      (`UnitOption`/`MeasureOption`, labelled "potato, large (299 g)"); wired
      into the recipe-editor line dropdown, the shop add sheet, AND the
      edit-top-up sheet — which got the by-id vocab lookup the tracker row
      called for, retiring it.)*
- [x] Batch-level cook nudge: the cook session's raw factor (×0.75) offers a
      whole-batch nudge (×1) with an honest "covers N portions · M left over"
      line — pure-domain math, display + one persisted preference at most.
      *(`wholeBatchNudgeFor` + `wholeBatchNudgeLine`, boundary-tested; a
      per-session display toggle — ephemeral by decision, see log. The
      ingredient-level "2.25 → buy 3" hint shipped on the shop line via
      `wholeUnitHintFor`, gated to count foods that actually have a measure,
      always beside the honest total.)*
- [x] Starter measures seeded for the common count/liquid vocab rows (onion,
      potato, tofu block, canned coconut milk, …) — curated pass, honest
      weights, sources noted. *(`supabase/seed_measures.sql`: 28 rows / 27
      ingredients, USDA-FDC-portion / retail-pack / typical sources noted per
      row; template clone extended so they arrive at onboarding. `usda_food`
      could NOT be mined: it carries no portion columns — gen_usda.ts consumed
      FDC portions for density only, and the raw CSVs aren't committed.)*
- [x] Tests cover the new logic (domain conversions, aggregation, nudge
      boundaries, repo watch coverage). *(245 app tests green: measure
      conversions incl. NaN/≤0 guards, measured aggregation, hint gating,
      nudge boundaries incl. float noise, measure round-trip + unresolved-id
      survival + watch re-fire in the recipe/shopping/measure repos —
      `measure_repository_impl.dart` enrolled in the structural
      watch-coverage test. pgTAP 54 green: RLS isolation row for the new
      table, clone-includes-measures, manual-ingredient measures never
      clone.)*
- [x] Docs updated: ARCHITECTURE data model, product-spec units section,
      QUALITY row, `make docs` regenerated *(db-schema.md now 15 tables)*.

## Approach

1. Migration + schema + sync rules (one new table, two nullable FK columns).
2. Domain `Measure` + conversion/aggregation, fully unit-tested.
3. Repo + providers (measures per ingredient, watched).
4. `allowedUnitsFor` v2.
5. Cook nudge (domain first, then the session card control).
6. Seed pass for starter measures.
7. Whole-unit shopping rounding for measure-bearing count ingredients.

## Decision log

- 2026-08-27 — Staged; promoted from stretch after step-7 review discussion:
  batch nudge and count-food honesty are wanted now, package-size flags stay
  step 11.
- 2026-08-27 — Measures are **per-household rows** (synced, user-editable),
  not global reference data: households disagree about what "1 portion" is,
  and the import step (8) will want to create them from labels.
- 2026-08-28 — **`measure_id` FK confirmed** over a namespaced unit string:
  the connector uploads the column as a plain uuid string (no jsonb decode,
  PUT/PATCH both fine), the unit catalog stays closed, and the column is
  self-documenting. A measure-quantified row additionally stores
  `unit = 'piece'` so a missing measure degrades to an honest count — never
  invented grams (invariant 3).
- 2026-08-28 — **Whole-batch toggle is display-level and ephemeral** (an
  autoDispose provider per session key): a persisted per-session override was
  explicitly ruled out — it is the same machinery the deferred cook-day
  adjustment needs and can arrive with it. The honest raw factor stays what
  the shopping list scales by; the nudge is advice, tracked as a tracker row.
- 2026-08-28 — **Whole-unit shopping hint shipped honestly**: gated to
  count-default ingredients that have a measure, single-subtotal items only
  (a mixed count+mass item would need a hint that covers both — a guess), and
  always rendered beside the total, never replacing it.
- 2026-08-28 — **Seed lives in its own hand-curated file**
  (`supabase/seed_measures.sql`, appended to `config.toml` sql_paths):
  `seed.sql` is generated from `vocab.jsonl` and must never be hand-edited,
  while measure weights are curated judgment. Joined by `match_text`, so a
  vocab regeneration that drops a row drops its measures too.
- 2026-08-28 — **USDA mining answered: no.** `usda_food` has no portion/gram
  columns (`gen_usda.ts` consumed FDC food portions to derive *density* only,
  and the ~40 MB CSV bundles aren't committed), so the seed pass is
  hand-curated with sources noted per row.

### Addendum — review follow-up (0010 migration + provenance pipeline)

- 2026-08-28 — **USDA mining re-answered: yes, from the raw bundles.** The
  earlier "no" was true of the compact `usda_food` table but wrong as a
  conclusion: FDC's `food_portion.csv` (in the uncommitted bundles) carries
  exactly the piece-type gram weights measures need. `seed_measures.sql` is
  now GENERATED (`seed/scripts/gen_measures.ts`): 184 rows over 118
  ingredients — tier 1 from each ingredient's own linked food (russet vs red
  potato get their own weights; a variety linked to a broader food keeps only
  variety-named portions, so cherry tomato = the 17 g `cherry` portion), tier
  2 an explicit committed borrow map (gold potato ← russet's size classes;
  five canned-bean varieties ← pinto's drained 15 oz can), and four
  `seed:typical` survivors where FDC has nothing usable (shallot, tempeh,
  coconut-milk can, silken-tofu block).
- 2026-08-28 — **Per-ingredient rows stay; no shared portion-class entity.**
  Sharing "medium potato" across varieties was considered and rejected: user
  overrides (and 7.7's editor) must stay variety-specific, and the borrow map
  makes cross-variety reuse explicit at *seed* time instead of implicit at
  read time. `ingredient_measure.source` (0010) records provenance per row —
  `usda_fdc:<fdc_id> (<portion>)`, `… — borrowed`, `seed:typical`, `manual`.
- 2026-08-28 — **Backfill for pre-0009 households** (0010): the
  already-onboarded early-exit leg of `ensure_onboarded()` clones the
  template's measures into a household with zero LIVE measures (same
  match_text join + manual exclusions, same advisory lock), so existing
  households heal on their next sign-in — and an operator can roll out a
  reseeded template by soft-deleting a household's measures
  (`docs/cloud-setup.md` §2). "Zero live rows" is deliberate: it doubles as
  the refresh path, and a live-label unique index keeps the seed idempotent.

## Notes / open questions

- ~~`measure_id` FK vs a namespaced unit string~~ — resolved: FK (see log).
- ~~Fractional measures ("½ can")?~~ — nothing new needed: quantity is a
  numeric and `formatQuantity` renders "0.5 can (400 ml)" fine; `convertMeasure`
  is tested at 0.5.
- ~~Does `usda_food` carry portion weights we can mine?~~ — no (see log);
  hand-curated 28 rows.

## Step-done checklist

- [x] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [x] `docs/QUALITY.md` grade for every area touched matches reality (unit
      system, vocab, cook-plan, shopping, sync notes updated).
- [x] `app/AGENTS.md` "Current focus" and command list still true (both point
      at the roadmap / unchanged commands — no edit needed).
- [x] Feature steps: `make test-sim` run on the booted iPhone 17 sim
      2026-08-28 — **all 3 scenarios green** (auth asserts the cloned
      measures synced; the library scenario picks "clove (3 g)" in the editor
      dropdown and asserts the persisted `measure_id` + honest `unit='piece'`
      fallback through the live-sync round-trip).
- [x] Tech-debt rows added for corners knowingly cut (no in-app measure
      editor; ephemeral whole-batch toggle), and retired for debt this step
      paid off: the **unit-picker edit-top-up sliver** (by-id vocab lookup
      added, sheet filtered + measure-aware) and the
      **whole-ingredient-scaling row** (batch nudge + whole-unit shop hint
      shipped).
- [x] `make ci` green (format · analyze + custom_lint · 245 app tests +
      edge-function tests · docs-check). `supabase test db`: 54 pgTAP
      assertions green.
