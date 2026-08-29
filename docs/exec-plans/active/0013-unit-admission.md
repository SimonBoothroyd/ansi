# Exec plan: Unit admission & entry polish

- **Status:** draft
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

- [ ] **Quick polish (independent, land first):** chip ordering per ADR-0008
      §Consequences (default → basis-family kitchen sizes → density-unlocked
      family demoted → measures → imprecise) — no more `ml · l` before `tsp`
      on a tsp-default ingredient; Week grid slot label inline with the
      recipe name per the board's week frame.
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

## Notes / open questions

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
