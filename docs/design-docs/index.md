# Design docs — index

A catalogue of the design knowledge in this repo. Design decisions with lasting
consequence are recorded as ADRs; broad operating principles live in
core-beliefs.

## Operating principles

- [`core-beliefs.md`](./core-beliefs.md) — how we (humans and agents) work here.

## Decision records (ADRs)

Immutable records of significant choices and their rationale.

- [ADR-0001](../decisions/0001-record-architecture-decisions.md) — Record architecture decisions
- [ADR-0002](../decisions/0002-stack-flutter-supabase-powersync.md) — Flutter + Forui + Supabase + PowerSync
- [ADR-0003](../decisions/0003-riverpod-feature-first-mvvm.md) — Riverpod 3 + go_router + feature-first MVVM
- [ADR-0004](../decisions/0004-matching-is-online-only.md) — Matching is online-only
- [ADR-0005](../decisions/0005-two-tier-vocabulary.md) — Two-tier ingredient vocabulary
- [ADR-0006](../decisions/0006-sync-auth-and-onboarding.md) — Sync auth, the household JWT claim, and onboarding
- [ADR-0007](../decisions/0007-shopping-list-thin-overlay.md) — Shopping list persists a thin overlay; cook contributions are derived
- [ADR-0008](../decisions/0008-unit-admission-model.md) — Units are admitted per ingredient via basis mapping; density is the only volume⇄mass fact
- [ADR-0009](../decisions/0009-density-unlocks-both-families.md) — A density unlocks the other mass/volume family whatever the default unit's family (amends ADR-0008)
- [ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) — `piece` is an admission fact, not a runtime guess (superseded by ADR-0015)
- [ADR-0011](../decisions/0011-one-save-one-write.md) — The flesh-out form defers every child write to one Save
- [ADR-0012](../decisions/0012-tsp-mates-cup.md) — The volume ladder is symmetric: `tsp` mates `cup` (superseded by ADR-0014)
- [ADR-0013](../decisions/0013-mass-ladder-symmetric.md) — The mass ladder is symmetric: the four kitchen mass units mate each other (superseded by ADR-0014)
- [ADR-0014](../decisions/0014-all-to-all-admission.md) — All to all: a mass/volume family is admitted whole and the household prunes per row (supersedes ADR-0008's kitchen trim, and ADR-0012/0013 entirely; leg 3 amended by ADR-0015)
- [ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md) — A piece weight is a row fact, exactly as a density is: it unlocks `piece` and retires "Counts as" (supersedes ADR-0010; rules 2 and 4 amended by ADR-0016)
- [ADR-0016](../decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md) — A measure that weighs a piece is the row's word for one: the sheet opens on it, the review lands a count on it, found by weight and never stored (amends ADR-0015 rules 2 and 4)
- [ADR-0017](../decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md) — A cost is a unit price, never an allocation: the latest price per basis unit, a recipe is its lines, planned and spent are never reconciled, an unpriced line is named and takes the figure with it
- [ADR-0018](../decisions/0018-a-recipe-measure-is-a-named-amount.md) — A recipe measure is a named amount, gated on `makes`: `a blob is 15 g`, so `3 blob` is 45 g and 0.15 of a 300 g batch — the ingredient measure's shape one level up, with its own unit because a recipe has no basis; authoring refuses without a `makes` in the unit's family, no density ever, a gone word refuses rather than degrading to a count, and the whole-batch word (the word that IS the whole yield) is found, never stored

## Deep design

Mechanics explainers — how a part of our own system actually works, traced
against the code. (Vendored snapshots of *other people's* docs live in
[`../references/`](../references/README.md); these are ours.)

- [Import & ingredient matching](../product-specs/import-and-matching.md) — the
  full pipeline: extraction → normalize → match cascade → reconcile → commit.
- [`search-and-matching.md`](./search-and-matching.md) — the one rule every
  phone-side search uses: three tiers (exact · word prefix · guarded typo), why
  each guard is the number it is, the "did you mean" band, and the seam that
  deliberately never guesses because nobody is watching it.
- [`unit-and-measure-matching.md`](./unit-and-measure-matching.md) — how an
  amount is interpreted end to end: the unit catalog vs the per-ingredient
  measure system, the three row facts a count or a volume is bridged by
  (density · piece weight · a measure), how "1 × 400 g tin" becomes both
  *400 g used* and *1 tin bought* from one stored number, and what the user can
  override where.
- [`navigation.md`](./navigation.md) — the tab shell and why the bar is one
  instance, the cross-fade spec, what back does on every screen state, the
  root-navigator rule for sheets and dialogs, and the tap guard.
- [`wide-screen.md`](./wide-screen.md) — the three layouts and their numbers
  (compact · medium · expanded, on Forui's own breakpoints), the one file under
  `lib/` allowed to read the viewport and the structural test that holds it, the
  two places the 640 measure is applied, and what a screen may and may not do
  with width.
- [`errors-and-sync-health.md`](./errors-and-sync-health.md) — the one rule (a
  toast reports an act, a banner reports a state), the one door every write goes
  through and the test that holds it, the four sync states and the words for
  each, and — just as deliberately — the seven things the app stays quiet about.
- [`powersync-watch-triggers.md`](./powersync-watch-triggers.md) — what makes a
  watched query re-fire, the unselected-LEFT-JOIN trap that silently drops a
  table from the trigger set, and the `triggerOnTables:` escape hatch.
