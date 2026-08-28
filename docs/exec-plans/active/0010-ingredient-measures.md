# Exec plan: Ingredient measures & portions

- **Status:** draft
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

- [ ] `ingredient_measure` table (id, household_id, ingredient_id, label,
      grams, sort_order, timestamps, deleted_at) + RLS + grants + publication;
      row in `docker/powersync.yaml` (and the cloud streams file once 0009
      commits it); `schema.dart` entry; jsonb-free so the connector needs no
      new column mapping.
- [ ] Domain: a `Measure` concept in the units layer — quantity-in-measure ↔
      grams, honest by construction (no measure, no invented grams; measures
      never bridge to volume without a density). `aggregateQuantities` folds
      measure-quantified contributions into the mass subtotal with provenance
      intact.
- [ ] Line items can reference a measure: nullable `measure_id` on
      `recipe_line_item` and `shopping_list_contribution` (decision below).
- [ ] `allowedUnitsFor` v2: current rules (same family; density-gated
      cross-family; imprecise; count-suppression) **plus the ingredient's live
      measures**.
- [ ] Batch-level cook nudge: the cook session's raw factor (×0.75) offers a
      whole-batch nudge (×1) with an honest "covers N portions · M left over"
      line — pure-domain math, display + one persisted preference at most.
      (Pulled forward from stretch per 2026-08-27 decision; the *ingredient*-
      level "2.25 → 3 potatoes" rounding lands here too, but only for
      ingredients that actually have a count measure.)
- [ ] Starter measures seeded for the common count/liquid vocab rows (onion,
      potato, tofu block, canned coconut milk, …) — curated pass, honest
      weights, sources noted.
- [ ] Tests cover the new logic (domain conversions, aggregation, nudge
      boundaries, repo watch coverage).
- [ ] Docs updated: ARCHITECTURE data model, product-spec units section,
      QUALITY row, `make docs` regenerated.

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

## Notes / open questions

- `measure_id` FK vs a namespaced unit string (`measure:<uuid>`) in the
  existing `unit` column: lean FK — keeps the unit catalog closed and the
  column self-documenting. Confirm against connector/patch behavior.
- Fractional measures ("½ can")? Quantity is already a numeric — nothing new
  needed, but the formatter should render halves nicely.
- Does `usda_food` carry portion weights we can mine for the seed pass?
  Check `scripts/gen_usda.ts` output before hand-curating.

## Step-done checklist

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator, result recorded
      here.
- [ ] Tech-debt rows added for corners knowingly cut, and retired for debt this
      step paid off (unit-picker row sliver, whole-ingredient-scaling row).
- [ ] `make ci` green.
