# Exec plan: Import — Lane C, client (intake · reconciliation · chips)

- **Status:** done — `app/lib/features/import` ships intake → review → commit →
  chipped steps. **Diverged from this charter, deliberately** (owner refinement
  during live iteration): the "three-state reconciliation screen" became ONE
  merged, always-editable **Review recipe** screen — no separate triage/preview
  split, rows expand in place, band-based auto-lock, "did you mean" chips for both
  ingredient and unit, allowed-unit enforcement, Save gated on all-valid. The
  @-mention editor stayed stretch and is unbuilt.
- **Roadmap step:** Step 8 — import (lane C of the W0 DAG)
- **Created:** 2026-08-30
- **Contract:** frozen in [0014](./0014-import-foundation.md) · server types in
  `supabase/functions/_shared/types.ts` · payload shape in
  `evals/datasets/extraction/gold/_SCHEMA.md` · reconciliation spec
  `docs/product-specs/import-and-matching.md` §8, §4.6 · app rules `app/AGENTS.md`

## Goal

The `app/lib/features/import` feature: intake → the three-state reconciliation
screen → commit (resolved lines + stubs) → tokenized-step **chips** on the recipe
page. Builds entirely against a **fake edge function** returning a canned
`ReconciliationPayload` — use a blessed **gold file** as the fixture. The real
`functions.invoke` is swapped in at integration (lane C's first-ever edge call).

## Deliverables

1. Feature scaffold (`domain/` pure Dart, `data/`, `presentation/`), MVVM + Riverpod,
   **Forui only** (never Material — [[mise-forui-only]]). Mirror the frozen payload
   as Dart types (Freezed/json).
2. **Intake screen** — paste URL / pick photo(s) → import repo (fake → real at integ).
3. **Reconciliation screen** (§8) — per line: `auto` (matched + undo), `suggest`
   (top-3), `none` (search vocab / **create-new stub**). **Ranges** (`qty_low/high`)
   → the user picks the number. **Coalesce** identical no-match lines. Surface
   never-invent flags (`parse_warnings`, low confidence) — don't hide shaky imports.
4. **Commit** — build the commit payload → PowerSync writes (`recipe`,
   `ingredient_group`, `recipe_line_item`, stubs). Remap `steps[].tokens[].ref`
   `line_index` → real `line_item_id` (§4.6). `recipe_line_item.ingredient_id` is NOT
   NULL — every line resolves first. Correction → alias write-back (lane B contract).
5. **Chip rendering** — tokenized steps on the recipe page: `text`/`ref`/`timer`
   tokens rendered by a **fold** (never render-time text-match). `portion` → sub-amount;
   else line qty on **first** mention; else quantity-less. Collective chips (no number).
   The @-mention editor is stretch.

## Boundaries

- **No Supabase in unit tests** — fake the import repo. Repo tests open a **real
  `PowerSyncDatabase`** (`test/helpers/test_db.dart`) — local tables are views
  ([[mise-powersync-views-no-upsert]]); select a column from every joined table in
  watches ([[mise-powersync-watch-left-join]]).
- No domain `package:flutter` imports. `make gen` after any `@riverpod`/Freezed/json.

## Tests

- Reconciliation VM: band handling, range resolution, dupe coalescing, create-new.
- Commit + `line_index`→`line_item_id` remap (real-schema repo test).
- Chip fold: portion/first-mention/collective rules. Use a gold file as the payload.

## Done when

Intake→reconcile→commit works against the fake edge fn; a committed recipe renders
chipped steps; repo/VM tests green; `make analyze` + `make test-app` clean.
