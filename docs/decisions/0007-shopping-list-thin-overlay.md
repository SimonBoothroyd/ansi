# ADR-0007: Shopping list persists a thin overlay; cook contributions are derived

- **Status:** Accepted
- **Date:** 2026-08-27
- **Context:** roadmap step 6 (shopping list); recorded retroactively during a
  docs fix-up pass — the decision was made and shipped in step 6
  (`supabase/migrations/0006_shopping.sql`)

## Context

The product spec's original §4 design made contributions the stored truth: every
shopping-list contribution — both the cook-plan-generated ones
(`source_type = 'cook_session'`, pointing at a `source_cook_session_id`) and
manual top-ups — would be persisted rows, with the per-ingredient total derived
by summing them.

By the time step 6 landed, steps 4–5 had already established that the batch cook
plan is a *pure derivation* of the week plan + recipe shelf life: there is no
`cook_session` table at all. Persisting cook contributions would therefore have
required inventing stable session ids and regenerating/reconciling the stored
rows on every plan or recipe edit — exactly the materialization complexity
steps 4–5 deliberately avoided.

## Decision

Only what **cannot be re-derived** is persisted — a thin overlay:

- `shopping_list_entry` — one row per ingredient the user has *touched*
  (checked off or topped up), plus free-text non-food items. Holds the
  check-off state (spec §4: check-off is on the entry, not per contribution).
- `shopping_list_contribution` — **manual contributions only** (top-ups and
  quantities on free-text items). Cook contributions are re-derived live on
  each device from the synced week + recipes and are never written to the
  database. The `source_type` / `source_cook_session_id` columns are carried
  for forward-compat but stay `'manual'` / null in v1.

The displayed list is assembled at read time: derived cook contributions +
persisted manual ones, summed in canonical base with provenance.

## Consequences

- **Nothing to reconcile between devices.** Two users share check-off and
  top-ups through sync; the derived totals are computed locally on each device
  from the same synced inputs, so a week or recipe edit never leaves stale
  stored contributions behind.
- **Entry lifecycle rule:** an ingredient entry is displayed only while it has
  at least one *live* contribution (derived or manual) or is free-text. Deleting
  a recipe makes its cook contribution vanish; an entry with no manual top-up
  drops off the list, its checked row staying inert (and the check-state
  returns if the ingredient is re-planned). `ingredient_id` never dangles —
  recipe deletion never touches the vocab. Pinned by a repo test.
- The spec's original "contributions are the stored truth" §4 wording is
  superseded; §4 now describes the shipped overlay model and links here.
- If cook sessions ever gain persisted state (e.g. the deferred cook-day
  override), the forward-compat columns allow revisiting without a schema
  change — that reversal would be a new ADR.
