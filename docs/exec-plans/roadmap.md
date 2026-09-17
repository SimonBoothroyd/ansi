# Roadmap — what is next, and what shipped

The numbered build sequence (spec §7, reordered around the meal-planning core)
ran to step 9 and is finished; step 10 has since shipped and step 11 stays
stretch. The unit of work now is a **plan** — one file in
[`active/`](./active), moved to
[`completed/`](./completed) when it lands. Read **Next** before starting. The
tables below are an index: one line on what exists and which plan bought it.
The detail is in the plan; the landing dates are in the
[cloud ledger](../cloud-setup.md#last-verified-ledger) and the
[tag table](../release.md#3d-tags-shipped), not here.

## Next

1. Food cost, receipts, and a meal eaten out —
   [plan 0049](./active/0049-food-cost-receipts-and-meals-out.md), the first
   ideas off the [backlog](./backlog.md), in three phases: prices and the
   recipe's cost reading, then receipts and spend, then the meal out.
2. Step 11 (anti-waste), still stretch.

The web app is served from GitHub Pages ([release.md §6.1](../release.md#61-the-host));
one browser sign-in on it is still to be walked.
The seed is the owner's own vocabulary and a reseed follows his rows, so no
operator statement is owed there.

## On main, not yet tagged

| What | Plan |
|------|------|

## Shipped

Rows in the order they shipped. `#` is the spec §7 step where a row is one;
a field-test round or a sweep has none. The tag is the first release that
carried the row. (Plans written before this index call rounds two to four,
Library v3 and Week v3 "steps 8.9–8.13"; they are the `v0.3.0`–`v0.5.0`
rows below, in that order.)

| # | What | Tag | Plan |
|---|------|-----|------|
| 1 | Unit system + ingredient data model — families, conversions, density | `v0.1.0` | — |
| 2 | Single-user recipes — create, group, scale, the recipe page | `v0.1.0` | [0002](./completed/0002-single-user-recipes.md) |
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
| 7.8 | Unit admission — per-ingredient `allowed_units`, density unlocking both families | `v0.1.0` | [0013](./completed/0013-unit-admission.md) · [ADR-0008](../decisions/0008-unit-admission-model.md) |
| 8 | Import — intake → extraction → deterministic match → review → commit; four lanes and an integration | `v0.1.0` | [0014](./completed/0014-import-foundation.md) · [0015](./completed/0015-import-extraction.md) · [0016](./completed/0016-import-matching.md) · [0017](./completed/0017-import-client.md) · [0018](./completed/0018-import-benchmark.md) · [0019](./completed/0019-import-integration.md) |
| 8.5 | Ingredients manager — the vocabulary's own screen, the flesh-out form, barcode add | `v0.1.0` | [0020](./completed/0020-ingredients-manager.md) |
| 9 | Computed macros in the UI — the recipe page's per-serving panel, `incomplete` when a stub is in | `v0.1.0` | — |
| 8.6 | Nested recipes — a recipe as an ingredient, with yield and batch math | `v0.2.0` | [0021](./completed/0021-nested-recipes.md) |
| 8.7 | `piece` is an admission fact, not a runtime guess; the seeded curation pass | `v0.2.0` | [0022](./completed/0022-piece-curation.md) · [ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) |
| — | Polish pass — navigation v2, search v1, Library v2, Week v2, editor v2, errors & sync health | `v0.2.0` | [0022](./completed/0022-polish-pass.md) · [0033](./completed/0033-library-v2-decisions.md) |
| — | Field test, round two — the import→macros seam, curated default measures | `v0.3.0` | [0024](./completed/0024-field-test-round-two.md) · [seam decisions](./completed/0024-seam-decisions.md) |
| — | Field test, round three — eight fixes from a week on `v0.3.0` | `v0.4.0` | [0025](./completed/0025-field-test-round-three.md) |
| — | Field test, round four — per-serving macros, the USDA match shown, a usual portion per person | `v0.5.0` | [0027](./completed/0027-field-test-round-four.md) |
| — | Library v3 — the Library's menus become rows and doors; the account page exists | `v0.5.0` | [0028](./completed/0028-library-v3.md) |
| — | Week v3 — no edit mode; every tap on the week grid has its own drawn target | `v0.5.0` | [0031](./completed/0031-week-v3.md) |
| — | Ingredient detail v2 — the flesh-out form ranks its fields instead of listing equals | `v0.5.0` | [0032](./completed/0032-ingredient-detail-v2.md) |
| — | Smoke split — one simulator file per flow, each provisioning its own household | `v0.5.0` | [0026](./completed/0026-smoke-split.md) |
| — | Debt pass — the server-side rule divergences, the measures rollout | `v0.5.0` | [0023](./completed/0023-debt-pass.md) |
| — | One save, one write — the New-ingredient sheet dissolves, and nothing matches to USDA on its own | `v0.5.0` | [0029](./completed/0029-one-save-one-write.md) · [ADR-0011](../decisions/0011-one-save-one-write.md) |
| — | State-of-the-world sweep — comments, docs, board, tests, UI anatomy | `v0.5.0` | [0030](./completed/0030-state-of-the-world-sweep.md) · [findings](./completed/0030-review-findings.md) |
| — | Field test, round five — fifteen owner notes off a photo import and a week of use; seven plans in parallel lanes | `v0.6.0` | [0034](./completed/0034-import-review-editable.md) · [0035](./completed/0035-line-ergonomics.md) · [0036](./completed/0036-ingredient-entry-and-units.md) · [0037](./completed/0037-library-rows.md) · [0038](./completed/0038-plan-an-ingredient.md) · [0039](./completed/0039-vocabulary-round-five.md) · [0040](./completed/0040-usda-provenance-and-edits.md) · [ADR-0012](../decisions/0012-tsp-mates-cup.md) |
| — | Field test, round six — four owner notes, the all-to-all unit rule, the vocabulary unit audit; the cloud database rebuilt from scratch | `v0.7.0` | [0041](./completed/0041-vocabulary-unit-audit.md) · [ADR-0013](../decisions/0013-mass-ladder-symmetric.md) · [ADR-0014](../decisions/0014-all-to-all-admission.md) |
| — | A piece weight is a row fact — a number on the row unlocks `piece`, and "Counts as" retires | `v0.8.0` | [0042](./completed/0042-piece-weight.md) · [ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md) |
| — | Four owner notes — a camera door on the import form, an ingredient's name on a line opens its page, a chip's new word keeps the sentence's case, a per-line macros toggle on the recipe page | `v0.9.0` | — |
| — | The ingredient page reads before it edits — a fact sheet with Edit behind the menu, every default-unit chip live, a typed name tidied on leaving the field with the change told | `v0.10.0` | — |
| — | Five owner notes — Title Case for every name kind, the default-unit row shows only what the row can say, a new ingredient saves complete or not at all, a beverage label lands per 100 ml, a photo import waits behind a stage ladder; then two barcode fixes | `v0.11.0` – `v0.11.2` | — |
| — | The serving, redrawn — any kitchen unit per serving, a density stated with an amount, the label's figures printed first, a scan seeding the serving, fibre as the optional fifth macro; then three inline-height fixes | `v0.12.0` – `v0.12.3` | — |
| — | Field test, round seven — kitchen fractions, one amount-and-unit control, measures edited in place, one name namespace, the import cascade batched and its reading streamed, the shop buying in the measure asked for, the seed as the owner's own snapshot, a recipe varied for one week. Migration `0040` | `v0.13.0` | [0043](./completed/0043-week-variant.md) |
| — | Field test, round eight — one unit chip at one height everywhere, forms reopen as entered, the USDA door where it is needed, "Edit for this week" beside a planned recipe, the import function streaming behind heartbeats, the units ladder applied once to the owner's vocabulary | `v0.13.1` | — |
| — | Field test, round nine — the import reading marker and checklist tidied, an optional line's tag is the week-mode switch, the learning loop refuses a whole printed line as a name | `v0.13.2` | — |
| — | Round ten — the recipe page up-levelled (method chips as word + amount, digit step numbers, fraction glyphs, a line's macros in the panel's order) and optional as the cook's decision: opened from a week, the page's `optional` tag is the switch, the shop's echo names are doors, and an optional sub-recipe is cooked only when the week includes it. No migrations | `v0.14.0` | [0044](./completed/0044-recipe-page-and-optional.md) |
| — | The retire guard — an ingredient is retired only when nothing live names it, refused in the app and in the database; a line already left at a retired row is shown by its last name and repairable wherever it appears. Migration `0041` | `v0.14.0` | — |
| — | The retired default-measure column, trigger, index and backfill are dropped; `ensure_onboarded` stops carrying a value nothing reads. Migration `0042` | `v0.14.0` | — |
| — | Round eleven — a flagged import amount prints empty with the source line beside it; the editor's line opens into the review's card so a note, the optional flag and the amount are set in one place; a household picks the day its week starts, a flip re-homing every planned week on the server. Migration `0043`, on cloud | `v0.15.0` | [0045](./completed/0045-field-test-round-eleven.md) |
| — | An empty shelf's two doors carry their book, so a recipe started there files onto that shelf; the Makefile shells the pinned Supabase CLI by path | `v0.14.0` | — |
| — | The seed follows the owner's rows again — Ginger's inch piece at 7 g, both can measures on Canned Diced Tomatoes, the Persian cucumber measures, Sauerkraut admitting to-taste. Reseed on deploy | `v0.14.0` | — |
| — | Field test, round twelve — ticked items gather in one basket section at the foot of the shop, a meal's slot is a field of its editor and the add flow defaults to the day's first unfilled slot (Snack joins the four), a piece-weighted row is bought in pieces on the shop and the basket keeps its aisles, a measure that weighs a piece is the row's word for one at every door (ADR-0016; existing lines re-pointed on cloud by hand), and the last tick on this phone bursts confetti of the food itself. No migrations | `v0.16.0` | [0046](./completed/0046-field-test-round-twelve.md) · [ADR-0016](../decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md) |
| — | Three owner notes on round twelve — the week's day foot and band read in the ingredient line's grammar with every unit glyph centred on the digits, the confetti plays on every finishing tick, and the camera door photographs page after page | `v0.16.1` | — |
| 10 | Wide screens — one file reads the viewport and one wrapper applies the measure, a sidebar and rail stand beside the content with sheets as dialogs, and each view that earns the width takes it: Cook as one schedule sheet on a shared seven-day axis, the Library as an open ledger, the Week as today beside the week's agenda, the recipe page and its editor in two columns, the import review with the page beside the lines and the current line's span lit, the Shop with a provenance pane, the vocabulary in two panes. Every glyph control answers a pointer through one style, the URL is the route, and the browser build ships from CI. **Deferred:** the phone's 44 px touch targets (mouse-only for now), mouse drag-to-scroll, the Week band's wide home, and the lit span, which waits on a `deploy-supabase` run — `import-recipe` changed additively. No migrations | `v0.17.0` | [0047](./completed/0047-wide-screens.md) |
| — | Field test, round fourteen — the wide Week redrawn as a small agenda at left (every meal in one mono run, the phone's macro strip per day, the week's band at the foot) beside the day at the phone's meal size with one add door; the serif's five named sizes with a guard; the vocabulary's wide pane without a loading header, its pick in the URL and its lit row on screen; the servings scaler, the search field and the Shop's sync line each fixed once; and a method chip or step struck off while cooking. No migrations | `v0.18.0` | [0048](./completed/0048-field-test-round-fourteen.md) |

## Stretch

- **11 — Anti-waste extras.** Freezer batching, monotony warnings,
  package-size flags. Unscheduled.
