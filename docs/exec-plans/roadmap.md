# Roadmap — what is next, and what shipped

The numbered build sequence (spec §7, reordered around the meal-planning core)
ran to step 9 and is finished; steps 10 and 11 stay stretch. The unit of work
now is a **plan** — one file in [`active/`](./active), moved to
[`completed/`](./completed) when it lands. Read **Next** before starting. The
tables below are an index: one line on what exists and which plan bought it.
The detail is in the plan; the landing dates are in the
[cloud ledger](../cloud-setup.md#last-verified-ledger) and the
[tag table](../release.md#3d-tags-shipped), not here.

## Next

1. **Ship what is on main.** Round ten and the retire guard are landed and
   untagged (the table below). Migration `0041` has not reached cloud, so the
   order is [release.md §5](../release.md#5-full-ship-checklist): the
   deploy-supabase button first, then the tag, then move both rows into
   Shipped and add the tag's row to the tag table.
2. **Pay the due tracker row.** `ingredient.default_measure_id` and its
   machinery were kept for one release after the piece weight (`v0.8.0`);
   many have shipped since. One migration drops them
   ([tracker](./tech-debt-tracker.md), area `supabase`).
3. Then step 10 (web) or step 11 (anti-waste), both stretch, or the first
   idea worth building off the [backlog](./backlog.md).

The seed is the owner's own vocabulary and a reseed follows his rows, so no
operator statement is owed.

## On main, not yet tagged

| What | Plan |
|------|------|
| Round ten — the recipe page up-levelled (a method chip is the word with its live amount in a pill, digit step numbers, the Method tab says what it is scaled to, a one-line planned band, kitchen-fraction glyphs, line macros in the panel's order, the panel names what it left out) and optional as a decision the cook can reach: the page opened from a week draws the week's lines and its `optional` tag is the switch, the shop's echo names are doors, and an optional sub-recipe is cooked only when the week includes it. No migrations | [0044](./completed/0044-recipe-page-and-optional.md) |
| The retire guard — an ingredient is retired only when nothing live names it: the database refuses the retire while a recipe line, planned meal or this-week swap names the row, and repairs lines an earlier pass left broken; a line at a retired row is shown by its last name and repairable on the page, in the editor, in the shop's echo and on the import review. Migration `0041` | — |

## Shipped

The `#` is the spec §7 step where a row is one; a field-test round or a
sweep has none. The tag is the first release that carried the row.

| # | What | Tag | Plan |
|---|------|-----|------|
| 1 | Unit system + ingredient data model — families, conversions, density | `v0.1.0` | — |
| 2 | Single-user recipes — create, group, scale, recipe page | `v0.1.0` | [0002](./completed/0002-single-user-recipes.md) |
| 3 | Recipe books + user-defined sections | `v0.1.0` | [0003](./completed/0003-books.md) |
| 3.5 | Test harness + doc hygiene — repo tests on a real `PowerSyncDatabase` | `v0.1.0` | [0004](./completed/0004-test-harness-and-doc-hygiene.md) |
| 4 | Week planning — the grid, eaters, the two-step add flow | `v0.1.0` | [0005](./completed/0005-week-planning.md) |
| 5 | Batch cook plan — shelf-life clustering, freezer merge | `v0.1.0` | [0006](./completed/0006-batch-cook-plan.md) |
| 6 | Shopping list derived from the cook plan, with provenance | `v0.1.0` | [0007](./completed/0007-shopping-list.md) |
| 7 | Sync layer — PowerSync, the household JWT claim, the upload queue | `v0.1.0` | [0008](./completed/0008-sync-layer.md) |
| 7.4 | Post-step-7 hardening sweep — jsonb round-trip, tombstones, races | `v0.1.0` | [0012](./completed/0012-hardening-sweep.md) |
| 7.5 | Cloud verification & seeding — read-only health checks, versioned streams | `v0.1.0` | [0009](./completed/0009-cloud-verification.md) |
| 7.6 | Ingredient measures & portions — the honest count↔mass bridge | `v0.1.0` | [0010](./completed/0010-ingredient-measures.md) |
| 7.7 | Picker uplift — both pickers redesigned, unit chips over the keypad | `v0.1.0` | [0011](./completed/0011-picker-uplift.md) |
| 7.8 | Unit admission & entry polish — per-ingredient `allowed_units`, density both ways | `v0.1.0` | [0013](./completed/0013-unit-admission.md) · [ADR-0008](../decisions/0008-unit-admission-model.md) |
| 8 | Import — intake → extraction → deterministic match → review → commit, built as four lanes and an integration | `v0.1.0` | [0014](./completed/0014-import-foundation.md) · [0015](./completed/0015-import-extraction.md) · [0016](./completed/0016-import-matching.md) · [0017](./completed/0017-import-client.md) · [0018](./completed/0018-import-benchmark.md) · [0019](./completed/0019-import-integration.md) |
| 8.5 | Ingredients manager + the flesh-out form + barcode add; the detail page's second pass | `v0.1.0` | [0020](./completed/0020-ingredients-manager.md) · [0032](./completed/0032-ingredient-detail-v2.md) |
| 8.6 | Nested recipes — a recipe as an ingredient, with yield and batch math | `v0.2.0` | [0021](./completed/0021-nested-recipes.md) |
| 8.7 | `piece` versus a real measure — admission, not a runtime guess; the seeded curation pass | `v0.2.0` | [0022](./completed/0022-piece-curation.md) · [ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) |
| 8.8 | Polish pass — navigation v2, search v1, Library v2, Week v2, editor v2, errors & sync health | `v0.2.0` | [0022](./completed/0022-polish-pass.md) · [0033](./completed/0033-library-v2-decisions.md) |
| 8.9 | Field test, round two — the import→macros seam, curated default measures | `v0.3.0` | [0024](./completed/0024-field-test-round-two.md) · [seam decisions](./completed/0024-seam-decisions.md) |
| 8.10 | Field test, round three — eight fronts | `v0.4.0` | [0025](./completed/0025-field-test-round-three.md) |
| 8.11 | Field test, round four — per-serving macros, the USDA match shown, a usual portion per person | `v0.5.0` | [0027](./completed/0027-field-test-round-four.md) |
| 8.12 | Library v3 — the menus dissolve; `/account` exists | `v0.5.0` | [0028](./completed/0028-library-v3.md) |
| 8.13 | Week v3 — the mode goes; each tap gets its own drawn target | `v0.5.0` | [0031](./completed/0031-week-v3.md) |
| 9 | Computed macros in the UI — the recipe page's per-serving panel | `v0.1.0` | — |
| — | Smoke split — one integration file per flow, each self-provisioning | `v0.5.0` | [0026](./completed/0026-smoke-split.md) |
| — | Debt pass — the server-side rule divergences, the measures rollout | `v0.5.0` | [0023](./completed/0023-debt-pass.md) |
| — | One save, one write — the New-ingredient sheet dissolves, and nothing matches to USDA on its own | `v0.5.0` | [0029](./completed/0029-one-save-one-write.md) · [ADR-0011](../decisions/0011-one-save-one-write.md) |
| — | State-of-the-world sweep — comments, docs, board, tests, UI anatomy | `v0.5.0` | [0030](./completed/0030-state-of-the-world-sweep.md) · [findings](./completed/0030-review-findings.md) |
| — | Field test, round five — fifteen owner notes off a photo import and a week of use, seven plans in parallel lanes | `v0.6.0` | [0034](./completed/0034-import-review-editable.md) · [0035](./completed/0035-line-ergonomics.md) · [0036](./completed/0036-ingredient-entry-and-units.md) · [0037](./completed/0037-library-rows.md) · [0038](./completed/0038-plan-an-ingredient.md) · [0039](./completed/0039-vocabulary-round-five.md) · [0040](./completed/0040-usda-provenance-and-edits.md) · [ADR-0012](../decisions/0012-tsp-mates-cup.md) |
| — | Field test, round six — four owner notes, the all-to-all unit rule, the vocabulary unit audit; the cloud database rebuilt from scratch | `v0.7.0` | [0041](./completed/0041-vocabulary-unit-audit.md) · [ADR-0013](../decisions/0013-mass-ladder-symmetric.md) · [ADR-0014](../decisions/0014-all-to-all-admission.md) |
| — | A piece weight is a row fact — `piece` is unlocked by a number, and "Counts as" retires | `v0.8.0` | [0042](./completed/0042-piece-weight.md) · [ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md) |
| — | Four owner notes in parallel lanes — a camera door on import, a name as a door onto its page, a chip keeps the sentence's case, a per-line macros toggle | `v0.9.0` | — |
| — | The ingredient page reads before it edits; every default-unit chip is live; typed names are tidied and the change is told | `v0.10.0` | — |
| — | Five owner notes — chip case and Title Case everywhere, the sayable default-unit row, a new ingredient saves complete or not at all, a beverage label per 100 ml, the photo import's stage ladder | `v0.11.0` – `v0.11.2` | — |
| — | The serving, redrawn — any kitchen unit per serving, density with an amount, the label's figures first, a scan seeding the serving, fibre as the fifth macro | `v0.12.0` – `v0.12.3` | — |
| — | Field test, round seven — eight parallel lanes: kitchen fractions, one amount-and-unit control, measures edited in place, one name namespace, the import cascade batched and streamed, the shop counting in the measure asked for, the seed as the owner's snapshot, and this week's variant. Migration `0040` | `v0.13.0` | [0043](./completed/0043-week-variant.md) |
| — | Field test, round eight — the unit chip at one inline height everywhere, forms reopen as entered, the USDA door where it is needed, "Edit for this week" where a planned recipe is looked at, the import function streaming behind heartbeats, the units ladder applied once to the owner's vocabulary | `v0.13.1` | — |
| — | Field test, round nine — the import marker spins in place and its checklist speaks in tense, an optional line wears its tag and in week mode the tag is the switch, the learning loop refuses a whole printed line | `v0.13.2` | — |

## Stretch

- **10 — Web UI.** Near-free with Flutter; the first lane is a centred phone
  layout behind one breakpoint file. Unscheduled.
- **11 — Anti-waste extras.** Freezer batching, monotony warnings,
  package-size flags. Unscheduled.

## Why this order

The unit system underpins recipes, scaling, cook-plan scaling and
shopping-list aggregation — nothing works until conversions are trustworthy,
so it was built first and hardened with tests. Import came late deliberately:
it depends on a stable ingredient vocabulary to match against. The spec's
open questions are in [spec §8](../product-specs/product-spec.md#8-remaining-open-questions-low-priority).
