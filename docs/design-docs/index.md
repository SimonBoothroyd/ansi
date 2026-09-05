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
- [ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) — `piece` is an admission fact, not a runtime guess
- [ADR-0011](../decisions/0011-one-save-one-write.md) — The flesh-out form defers every child write to one Save
- [ADR-0012](../decisions/0012-tsp-mates-cup.md) — The volume ladder is symmetric: `tsp` mates `cup` (amends ADR-0008's kitchen trim)

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
  measure system, how "1 × 400 g tin" becomes both *400 g used* and *1 tin
  bought* from one stored number, and what the user can override where.
- [`navigation.md`](./navigation.md) — the tab shell and why the bar is one
  instance, the cross-fade spec, what back does on every screen state, the
  root-navigator rule for sheets and dialogs, and the tap guard.
- [`errors-and-sync-health.md`](./errors-and-sync-health.md) — the one rule (a
  toast reports an act, a banner reports a state), the one door every write goes
  through and the test that holds it, the four sync states and the words for
  each, and — just as deliberately — the seven things the app stays quiet about.
- [`powersync-watch-triggers.md`](./powersync-watch-triggers.md) — what makes a
  watched query re-fire, the unselected-LEFT-JOIN trap that silently drops a
  table from the trigger set, and the `triggerOnTables:` escape hatch.
