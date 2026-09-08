# Roadmap — what is next, and what shipped

The numbered sequence (spec §7, reordered around the meal-planning core) ran to
step 9 and is finished; steps 10 and 11 stay stretch. The unit of work now is a
**plan** — one file in [`active/`](./active), moved to [`completed/`](./completed)
when it lands. Read **Next** before starting; the Shipped table is the index of
what exists and which plan bought it.

## Next

1. Step 10 (web) or step 11 (anti-waste), both stretch, or the first idea
   worth building off the [backlog](./backlog.md). Every migration through
   `0037` and the current seed are on cloud: the v0.7.0 release rebuilt the
   cloud database from scratch (owner call, cloud-setup §2c), so there is no
   pending push, no operator statement owed to an old household, and the data
   from here on is real.

## Shipped

One row per step or plan. Detail lives in the plan; this table says what exists
and where to read about it.

| # | What | Status | Plan |
|---|------|--------|------|
| 1 | Unit system + ingredient data model — families, conversions, density | 🟢 | — |
| 2 | Single-user recipes — create, group, scale, recipe page | 🟢 | [0002](./completed/0002-single-user-recipes.md) |
| 3 | Recipe books + user-defined sections | 🟢 | [0003](./completed/0003-books.md) |
| 3.5 | Test harness + doc hygiene — repo tests on a real `PowerSyncDatabase` | 🟢 | [0004](./completed/0004-test-harness-and-doc-hygiene.md) |
| 4 | Week planning — the grid, eaters, the two-step add flow | 🟢 | [0005](./completed/0005-week-planning.md) |
| 5 | Batch cook plan — shelf-life clustering, freezer merge | 🟢 | [0006](./completed/0006-batch-cook-plan.md) |
| 6 | Shopping list derived from the cook plan, with provenance | 🟢 | [0007](./completed/0007-shopping-list.md) |
| 7 | Sync layer — PowerSync, the household JWT claim, the upload queue | 🟢 | [0008](./completed/0008-sync-layer.md) |
| 7.4 | Post-step-7 hardening sweep — jsonb round-trip, tombstones, races | 🟢 | [0012](./completed/0012-hardening-sweep.md) |
| 7.5 | Cloud verification & seeding — read-only health checks, versioned streams | 🟢 | [0009](./completed/0009-cloud-verification.md) |
| 7.6 | Ingredient measures & portions — the honest count↔mass bridge | 🟢 | [0010](./completed/0010-ingredient-measures.md) |
| 7.7 | Picker uplift — both pickers redesigned, unit chips over the keypad | 🟢 | [0011](./completed/0011-picker-uplift.md) |
| 7.8 | Unit admission & entry polish — per-ingredient `allowed_units`, density both ways | 🟢 | [0013](./completed/0013-unit-admission.md) · [ADR-0008](../decisions/0008-unit-admission-model.md) |
| 8 | Import — intake → extraction → deterministic match → review → commit | 🟢 | [0014](./completed/0014-import-foundation.md) → [0019](./completed/0019-import-integration.md) |
| 8.5 | Ingredients manager + the flesh-out form + barcode add | 🟢 | [0020](./completed/0020-ingredients-manager.md) |
| 8.6 | Nested recipes — a recipe as an ingredient, with yield and batch math | 🟢 | [0021](./completed/0021-nested-recipes.md) |
| 8.7 | `piece` versus a real measure — admission, not a runtime guess | 🟢 | [0022](./completed/0022-polish-pass.md) · [ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) |
| 8.8 | Polish pass — navigation v2, search v1, Library v2, Week v2, editor v2, errors & sync health | 🟢 | [0022](./completed/0022-polish-pass.md) |
| 8.9 | Field test, round two — the import→macros seam, curated default measures | 🟢 `v0.3.0` | [0024](./completed/0024-field-test-round-two.md) |
| 8.10 | Field test, round three — eight fronts on `v0.3.0` | 🟢 `v0.4.0` | [0025](./completed/0025-field-test-round-three.md) |
| 8.11 | Field test, round four — per-serving macros, the USDA match shown, a usual portion per person | 🟢 done — on cloud 2026-09-04 | [0027](./completed/0027-field-test-round-four.md) |
| 8.12 | Library v3 — the menus dissolve; `/account` exists. No migrations | 🟢 done — all seven smoke files green 2026-09-04 | [0028](./completed/0028-library-v3.md) |
| 8.13 | Week v3 — the mode goes; each tap gets its own drawn target | 🟢 | — |
| 9 | Computed macros in the UI — the recipe page's per-serving panel | 🟢 | — |
| — | Smoke split — one integration file per flow, each self-provisioning | 🟢 | [0026](./completed/0026-smoke-split.md) |
| — | Debt pass — the server-side rule divergences, the measures rollout | 🟢 | [0023](./completed/0023-debt-pass.md) |
| — | One save, one write — the New-ingredient sheet dissolves, and nothing matches to USDA on its own | 🟢 done — on cloud 2026-09-04 | [0029](./completed/0029-one-save-one-write.md) · [ADR-0011](../decisions/0011-one-save-one-write.md) |
| — | State-of-the-world sweep — comments, docs, board, tests, UI anatomy | 🟢 done — on cloud 2026-09-04, shipped as `v0.5.0` | [0030](./completed/0030-state-of-the-world-sweep.md) |
| 8.14 | Field test, round five — fifteen owner notes off a photo import and a week of use, built as seven plans in parallel lanes | 🟢 done — on cloud 2026-09-05, shipped as `v0.6.0` | [0034](./completed/0034-import-review-editable.md) · [0035](./completed/0035-line-ergonomics.md) · [0036](./completed/0036-ingredient-entry-and-units.md) · [0037](./completed/0037-library-rows.md) · [0038](./completed/0038-plan-an-ingredient.md) · [0039](./completed/0039-vocabulary-round-five.md) · [0040](./completed/0040-usda-provenance-and-edits.md) · [ADR-0012](../decisions/0012-tsp-mates-cup.md) |
| 8.15 | Field test, round six — four owner notes (unit ladder, a stranded default, a dying provider, week-scoped staples, provenance by name), then the all-to-all unit rule and the vocabulary unit audit; the cloud database rebuilt from scratch | 🟢 done — on cloud 2026-09-08, shipped as `v0.7.0` | [0041](./completed/0041-vocabulary-unit-audit.md) · [ADR-0013](../decisions/0013-mass-ladder-symmetric.md) · [ADR-0014](../decisions/0014-all-to-all-admission.md) |
| — | A piece weight is a row fact — `piece` is unlocked by a number, and "Counts as" retires | 🟢 | [0042](./completed/0042-piece-weight.md) · [ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md) |
| — | Four owner notes in parallel lanes — a camera door on the import form, an ingredient's name as a door onto its page, a chip's new word keeps the sentence's case, a per-line macros toggle on the recipe page. No migrations | 🟢 `v0.9.0` | — |
| 10 | Web UI (near-free with Flutter) | ⚪ stretch | — |
| 11 | Anti-waste extras — freezer batching, monotony warnings, package-size flags | ⚪ stretch | — |

Legend: ⚪ not started · 🟡 in progress · 🟢 done

## Why this order

The unit system underpins recipes, scaling, cook-plan scaling and shopping-list
aggregation — nothing works until conversions are trustworthy, so it was built
first and hardened with tests. Import came late deliberately: it depends on a
stable ingredient vocabulary to match against.

## Open questions (spec §8, low priority)

- Can a recipe belong to multiple books? (v1 assumes one.)
