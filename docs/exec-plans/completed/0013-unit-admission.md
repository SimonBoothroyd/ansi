# Exec plan: Unit admission & entry polish

- **Status:** done (2026-08-29)
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
- [x] Migration: `ingredient_measure` amounts become basis-aware (amount in
      the ingredient's basis unit; existing gram rows are /g so values carry
      unchanged); explicit `allowed_units` on `ingredient`, materialized at
      creation from the ADR defaults (backfill for the existing vocab);
      RLS/grants/publication + both sync-rule files + schema.dart + pgTAP.
      *(0012: `basis_amount` rename-by-new-column + drop; `allowed_units`
      jsonb + `default_allowed_units()` + BEFORE INSERT trigger + whole-vocab
      backfill; `ensure_onboarded` rev 5 carries both through every clone
      leg. Sync-rule files needed NO text change — their `select *` ships the
      new columns; the drift check confirms both lists still match. pgTAP:
      +14-assert `unit_admission.sql` with rule vectors mirrored in the Dart
      tests, and the 0010 'glug (test)' shape now pins `basis_amount` + a
      verbatim `allowed_units` clone.)*
- [x] Domain: `allowedUnitsFor` v3 reads the explicit list; conversions honor
      basis-aware measures; category-gated imprecise. *(Explicit set →
      `_orderUnits` chip ordering; null/legacy → `defaultAllowedUnitSet`,
      the Dart mirror of the SQL rule. `Measure.amount` + `basis`
      (`MacrosBasis`, joined from the ingredient — never stored twice);
      `convertMeasure`/`amountInMeasure` bridge the basis family and cross
      only via density; `aggregateQuantities` folds per-ml measures into the
      VOLUME subtotal; the whole-unit hint prices volume totals too. The
      display audit found five surfaces assuming grams — chip labels,
      measure rows, conversion note, add-form hint, shopping breakdown — all
      now denominate in the basis unit. Stored-selection admission
      preserved + re-pinned.)*
- [x] Density entry both ways in the manage sheet: g/ml field ⇄ "1 tbsp
      weighs __ g" (either writes the same density); volume-named labels in
      the add-measure form are redirected to density entry with a one-line
      explanation. *(`_DensityEntry` with tsp/tbsp/cup spoons + live g/ml
      equivalence; `densityFromVolumeWeight` unit-tested;
      `IngredientRepository.setDensity` writes density AND extends the
      explicit `allowed_units` in the same write, and the open sheet swaps
      its live ingredient copy so the unlocked chips appear immediately.
      The redirect pre-picks the named spoon.)*
- [x] Seed pipeline: FDC spoon portions → derived density for density-less
      /g ingredients (report the new density coverage, expect ≫ 7/291);
      yeast gains `sachet (7 g)` as a proper measure. *(Famine root cause:
      SR Legacy keys volume portions by `modifier` text, not
      `measure_unit_id` — gen_usda.ts now parses the whole portion text,
      ranked cup > tbsp > tsp, unqualified first, sanity 0.1–2.0. Coverage
      **7/291 → 211/291**. Both yeasts carry the 7 g sachet
      (`seed:typical` — the near-universal printed standard). Measures went
      GENEROUS per Simon's scope note (238 raw rows incl. rescued
      physically-disguised servings), then the curation pass trimmed to
      **230 rows / 117 ingredients**; `curation_overrides.jsonl` records
      all 44 overrides with reasons.)*
- [x] Flesh-out/allowed-units form design added to board frame (d) before
      that form is built (form implementation itself may fold into step 8's
      stub-queue work — decide at kickoff). *(Frame pv2-d2 "Allowed units"
      grown beside the macros-basis frame: basis line, pre-ticked family
      chips + dashed density-locked ones, either-way density entry, measures,
      category-gated imprecise toggle; frame b2 updated to show the shipped
      density entry + redirect. The form BUILD stays step-8 scope —
      decided.)*
- [x] Tests cover the new logic at every layer; `make ci` + `supabase test
      db` (dirty) + `make test-sim` green. *(364 app tests — was 311 at 7.7;
      87 pgTAP — was 67; the full gate chain ran in order: `make test-app` →
      `make test-sim` (3/3 scenarios over live sync on the booted iPhone 17
      sim, retargeted for the manage-state's density entry) → `supabase
      test db` on that DIRTY db (87 green) → `make ci` — plus a final fresh
      reset + pgTAP validating the lint-driven STABLE re-declare.)*
- [x] Docs updated: product-spec units section, QUALITY, tracker, `make docs`.
      *(Plus seed README — density derivation, generous extraction +
      curation overrides, five-file load order — and cloud-setup's seed list
      + rollout notes. `make docs`/`docs-check` green; the stream drift
      check confirms both sync-rule files needed no change.)*

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
- 2026-08-29 — Gate-chain findings worth keeping: the smoke's manage-sheet
  `Save` taps had to be SCOPED to `QuantityUnitEditor` — the recipe
  editor's own covered Save sits earlier in the tree, and the sheet now
  carries a second (density) Save; `supabase db lint` caught
  `default_allowed_units` declared IMMUTABLE over the stable `to_jsonb`
  (re-declared STABLE before the migration shipped anywhere).
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

- [x] Roadmap row updated: status flipped, one line on what shipped and what
      was deliberately deferred.
- [x] `docs/QUALITY.md` grade for every area touched matches reality.
- [x] `app/AGENTS.md` "Current focus" and command list still true (it points
      at the roadmap; commands unchanged).
- [x] Feature steps: `make test-sim` run on a booted simulator, result
      recorded here — **green, 3/3 scenarios** (auth → library incl. the
      manage-sheet measure add now scoped past the new density Save → week →
      cook → shop over live sync), 2026-08-29.
- [x] Tech-debt rows added for corners knowingly cut (Foundation bundle
      refresh; no sim scenario for the density entry; server-side density
      vs materialized lists), and retired/narrowed for debt this step paid
      off (the density famine: 7/291 → 211/291; the `recipes/macros`
      blocker row removed).
- [x] `make ci` green.
