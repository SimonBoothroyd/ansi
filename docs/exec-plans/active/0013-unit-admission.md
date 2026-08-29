# Exec plan: Unit admission & entry polish

- **Status:** in progress
- **Owner:** agent (staged 2026-08-29 from the post-7.7 design session)
- **Roadmap step:** Step 7.8 — unit admission & entry polish
- **Created:** 2026-08-29

## Goal

Implement [ADR-0008](../../decisions/0008-unit-admission-model.md): units are
admitted per ingredient via basis mapping, density is the single volume⇄mass
fact (enterable as g/ml *or* "a spoon weighs N g"), measures are count-like
only and basis-aware, allowed units are explicit per ingredient, imprecise is
category-gated — plus the two independent 7.7 polish items Simon flagged.

## Acceptance criteria

- [x] **Quick polish (independent, land first):** chip ordering per ADR-0008
      §Consequences (default → basis-family kitchen sizes → density-unlocked
      family demoted → measures → imprecise) — no more `ml · l` before `tsp`
      on a tsp-default ingredient; Week grid slot label inline with the
      recipe name per the board's week frame. *(Landed with the 7.7
      re-verification one-liners: `deleteMeasure` mounted guard, `_createdKey`
      zone-less-means-UTC, the `…+00`→`… …Z` comment truth-up, inline
      ArgumentError surfacing in the add-measure form, selected-chip
      scroll-into-view, `formatDensity` ≥1000 clamp.)*
- [ ] Migration: `ingredient_measure` amounts become basis-aware (amount in
      the ingredient's basis unit; existing gram rows are /g so values carry
      unchanged); explicit `allowed_units` on `ingredient`, materialized at
      creation from the ADR defaults (backfill for the existing vocab);
      RLS/grants/publication + both sync-rule files + schema.dart + pgTAP.
- [ ] Domain: `allowedUnitsFor` v3 reads the explicit list; conversions honor
      basis-aware measures; category-gated imprecise.
- [ ] Density entry both ways in the manage sheet: g/ml field ⇄ "1 tbsp
      weighs __ g" (either writes the same density); volume-named labels in
      the add-measure form are redirected to density entry with a one-line
      explanation.
- [ ] Seed pipeline: FDC spoon portions → derived density for density-less
      /g ingredients (report the new density coverage, expect ≫ 7/291);
      yeast gains `sachet (7 g)` as a proper measure.
- [ ] Flesh-out/allowed-units form design added to board frame (d) before
      that form is built (form implementation itself may fold into step 8's
      stub-queue work — decide at kickoff).
- [ ] Tests cover the new logic at every layer; `make ci` + `supabase test
      db` (dirty) + `make test-sim` green.
- [ ] Docs updated: product-spec units section, QUALITY, tracker, `make docs`.

## Approach

1. Quick polish pair (chips order + week row) — small, shippable alone.
2. Migration + backfill + pipeline density derivation.
3. Domain v3 + entry UX (density-both-ways, redirects).
4. Board frame (d) extension → step-8 handoff decision.

## Decision log

- 2026-08-29 — Staged. Full rationale in ADR-0008; key calls made in the
  design chat: explicit allowed-units storage (cheap, predictable); spoon
  mappings ARE density (Simon); FDC spoons → density not measures.
- 2026-08-29 — **FDC portion extraction goes generous (Simon):** the old
  rank-and-cap-at-3 / fragment-suppressing pipeline used rules as the taste
  filter, which is the curation pass's job. New policy: extract ALL
  size-class portions, fragments/piece-types (slice, wedge, clove, sprig,
  floret, …), and dimension-described portions with kitchen-readable labels;
  still excluded at extraction are pure volume rows (they become derived
  DENSITY per ADR-0008) and NLEA/label "serving" rows. The curation pass
  trims what a human finds senseless, with reasons in the overrides file.
- 2026-08-29 — Kitchen trim + order encoded as explicit tables
  (`_kitchenMates`/`_kitchenOrder`/`_crossKitchen` in
  `allowed_units.dart`): the trim is judgment, not arithmetic — a ratio
  window kept failing metric↔customary cases — so it is a curated table the
  SQL default mirror re-states. `mg`/`fl oz` are label-reading units,
  offered only as the default (or admitted stored) unit. Demoted units
  render AFTER the measures (the plan's reading of ADR-0008's "demoted").

## Notes / open questions

- **Seed-default methodology (Simon, 2026-08-29):** rules are scaffolding,
  not the decider. Wherever this step assigns per-ingredient defaults
  (allowed units, derived densities, measures, imprecise gating), the
  pipeline's rule output gets a final **LLM curation pass**: the agent
  reviews each ingredient's assignments and overrides where a human would
  ("is this sensible?" — fuzzy judgment catches what rules overlook; the
  peeled-lemon class of error). Overrides are recorded with reasons so the
  pass is auditable, like the borrow map.

- **Preserve the stored-selection rule when admission narrows the sets
  (7.7 review fix, 2026-08-29):** `allowedUnitChoicesFor` admits the
  current (stored) choice when it falls outside the computed set and flags
  it so the chip row styles it "not in filter". Explicit `allowed_units`
  will narrow sets far more aggressively than today's density gate — an
  existing line's stored unit/measure must keep riding this admission path
  (and its widget tests must keep passing), never render orphaned.
- Category set for imprecise gating: start with `spice/seasoning/oil/
  condiment`; verify against the vocab's actual category values first.
- Does any existing UI assume `Measure` amounts are grams for display?
  Audit before the basis-aware change.

## Step-done checklist

- [ ] Roadmap row updated: status flipped, one line on what shipped and what
      was deliberately deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator, result
      recorded here.
- [ ] Tech-debt rows added for corners knowingly cut, and retired for debt
      this step paid off.
- [ ] `make ci` green.
