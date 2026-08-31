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

## Deep design

Mechanics explainers — how a part of our own system actually works, traced
against the code. (Vendored snapshots of *other people's* docs live in
[`../references/`](../references/README.md); these are ours.)

- [Import & ingredient matching](../product-specs/import-and-matching.md) — the
  full pipeline: extraction → normalize → match cascade → reconcile → commit.
- [`unit-and-measure-matching.md`](./unit-and-measure-matching.md) — how an
  amount is interpreted end to end: the unit catalog vs the per-ingredient
  measure system, how "1 × 400 g tin" becomes both *400 g used* and *1 tin
  bought* from one stored number, and what the user can override where.
- [`powersync-watch-triggers.md`](./powersync-watch-triggers.md) — what makes a
  watched query re-fire, the unselected-LEFT-JOIN trap that silently drops a
  table from the trigger set, and the `triggerOnTables:` escape hatch.
