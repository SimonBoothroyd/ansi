# Exec plan: the state-of-the-world sweep — code, tests, comments, docs, board

- **Status:** active
- **Owner:** Simon (rulings) · orchestrator + lanes (build)
- **Roadmap step:** none — a repo-wide quality pass after `v0.4.0` and plans 0027–0029
- **Created:** 2026-09-04

## Goal

Every description of the app — comments, docs, the design board, the tracker,
the roadmap — says what the app *is* today, in the present tense, in one place
each; the ten verified defects the review surfaced are fixed; the test suite
and the UI anatomy lose their copy-paste weight without losing a behavioural
guarantee. The full findings, with the evidence the lanes act on, are in
[`0030-review-findings.md`](./0030-review-findings.md) (the eleven lane
reports it condenses stayed in the review session's scratchpad).

## Acceptance criteria

- [ ] The ten "fix now" defects (review §1, C1–C10) are closed, each with the
      guard that stops it recurring where one was proposed (NUL test,
      caller-exists test, derived feature set, `docs.yml` paths, generated-doc
      diff in `check_docs.sh`).
- [ ] `lib/` comments carry no dates, plan numbers, decision letters, board
      versions, memory backlinks or history phrases; a structure test holds it;
      `app/AGENTS.md` states the rule in one sentence.
- [ ] The 36 wrong/stale doc-comment sites and the 57 stale doc sentences are
      corrected; the three facts that rotted this week (USDA trigger dropped,
      New-ingredient sheet deleted, Library `⋯` dissolved) appear nowhere as
      live.
- [ ] `docs/product-specs/board/` exists: one file per current view, shared
      CSS, an index with one status line per view, a designed-not-built
      appendix whose frames cite a backlog row or plan; the single
      `design-board.html` is deleted; root `AGENTS.md` describes the pattern
      and the keep-current rule.
- [ ] Three retrospective plans exist in `completed/` before the board's prose
      is cut: Week v3 (E1–E7 + owner quotes), Ingredient detail v2 (R1–R8 /
      Q1–Q8 + the USDA band measurement), Library v2 (D1–D8).
- [ ] `docs/exec-plans/backlog.md` exists; the roadmap opens with a Next list
      and a one-line-per-row Shipped section; the tracker holds only unpaid
      debt (~31 rows) as one intact table; `QUALITY.md` is gone, its grades a
      short table at the end of `ARCHITECTURE.md`; `design-docs/index.md`
      lists all eleven ADRs; plans 0023 and 0029 are in `completed/`.
- [ ] Test suite: the consolidation table (review §2) applied — shared fakes,
      one semantics filter, one source scanner, table-driven re-proofs,
      `allowed_units_vectors.json` on both sides, plan codes stripped from
      test names (ADR refs kept), `portion_factor_identity_test` deleted.
- [ ] UI anatomy: `AnsiSheetShell`, `askAnsi`/`refuseAnsi`, `formatNumber`,
      `AnsiCallout` + caution/chill/radius tokens, `AnsiChip`; the ingredient
      form has a `@riverpod` ViewModel; `recon_line_card.dart` is three files;
      `UnitChip` lives in its own file.
- [ ] `make ci` runs the Deno lint/fmt and seed-script tests; `make ci-full`
      adds the database legs; both docstrings are true.
- [ ] `make ci` and `make docs-check` green at every landing; `make test-sim`
      run once at the end from the main checkout and recorded here.

## Approach — lanes and waves

Every code lane works in its own worktree off `main` (`git merge --ff-only
main` first; `make powersync-core` + `flutter pub get` before any test), one
conventional commit per slice, `make ci` green, no merge — the orchestrator
lands lanes by cherry-pick and re-runs the gates at each landing. Docs lanes
conflict with nothing and run alongside. Lane A2 is the only lane that may use
the local Supabase stack (`make db-up`).

**Wave 1 (parallel):**

- **A1 · app dead code and seams.** C1 (escape the two NUL bytes + a
  no-NUL structure test); C5 (derive `_scannedFeatures` from
  `lib/features/*`, scan every widget-bearing directory in both guards); C8
  (delete the ten dead repository methods, their impls, fakes and test groups;
  seed the smoke files through `saveForm(null, …)` instead of `createStub`;
  port `createStub`'s provenance-on-create assertion onto the `saveForm`
  create test; add a structure test that every declared repository method has
  a caller under `lib/`); C4 (`_findVocabRow` selects with LIKE, ranks with
  `searchRank`, refuses tier 2); move `search_query.dart` + `search_rank.dart`
  to `core/search/` and `recipes/presentation/format.dart` to `shared/`
  (leave `normalize.dart` where it is — lane A2 edits it); point
  `prematchLines` and `_startsFirstWord` at the shared tokenizer;
  `session.dart` reads `bookRepositoryProvider` instead of constructing the
  impl; C9's one-liners (uncapped decimal in `allowed_units.dart:444`, the
  undo toast's plural via `formatPortions`, the raw `$error` in
  `ingredient_list_view.dart`, the second search field in
  `add_shopping_item_sheet.dart`; the four missing `animation:` wait for lane
  F); fix the `Result` docstring; move the two "Structural test:" files into
  `test/structure/`.
- **A2 · backend, evals, infra.** C2 (`deploy-supabase.yml` runs
  `seed_usda_index.sql` after `seed_usda`); C6 (`docs.yml` paths gain
  `docker/**` + the drift script); C7 (migration `0030`: `enable row level
  security` on the four `usda_search_*` tables; pgTAP `throws_ok` for
  `household.is_template` / `id` and for the four tables); `tinned` → `canned`
  fold in `normalize.ts` and `normalize.dart` before the state-word step, a
  shared vector for it, and migration `0031` rewriting stored `match_text`
  containing `tinned` (the 0022 shape); the fused number+unit token
  (`400g`) stripped by `QUANTITY` on both sides, with vectors; C3
  (`fixtures.ts` imports `deriveUnitHints()`; **no re-run** — a note in
  `evals/runs/README.md` that runs dated before this change were prompted
  with a diverged hint set and are not comparable to later ones); delete
  `noneDedupeKey` and the `usda_match_trgm` index (in `0030`); drop `sliced`
  from `0029`'s processed-form list (also `0030`); `make ci` gains the Deno
  fmt/lint legs and the seed-script tests, `make ci-full` adds
  `db-reset` + `supabase test db`, both docstrings true; `cloud_verify.sh`
  expects 15 RLS tables and checks `usda_search_stats` is populated; `make
  docs` regenerated; the stale TODO in `0000_init.sql` gone; `pricing.ts`
  notes corrected and a `retired_after` on the promo row; the 24 "lane
  A/B/C/D" comments in `supabase/` and `evals/` replaced by the role name;
  `supabase/AGENTS.md` corrected (no prefill trigger; eleven pgTAP suites; the
  four index tables under the server-only rule). Verify with `deno test`,
  `deno lint`, `deno fmt --check`, and `supabase db reset && supabase test
  db` on the local stack.
- **B1 · harness and status docs.** Present-tense pass over
  `ARCHITECTURE.md` (drop the trigger paragraph; add ADR-0011 and ADR-0006;
  absorb `QUALITY.md` as a closing "Where each area stands" table — grade ·
  one-sentence gap · link — then delete `QUALITY.md` and fix every link to
  it), `docs/README.md`, root `AGENTS.md` (link the backlog; keep ~100 lines),
  `app/AGENTS.md` (`/account` not `Library ⋯`; the reorder sheet is gone; drop
  `scratch/`; shorten the smoke paragraph to a pointer at
  `integration_test/`; add the one-sentence comment rule), `design-docs/index.md`
  (ADR-0010, 0011), the roadmap (a **Next** list at the top; rows 1–9 and
  8.x collapsed to one line each in a Shipped section; 8.12 corrected; 291 →
  308; frozen test counts dropped; a row for 0029 and this plan), the tracker
  (delete the blank lines at :48/:67, move the footer; apply the row-by-row
  prune in the findings — keep ~31, merge 6, delete the paid rows and
  obituaries, move 16 to `backlog.md`; add the header rule: no paid rows, no
  obituaries, one screen per row), **new `docs/exec-plans/backlog.md`** (one
  row per unbuilt idea: description · origin plan/board/ruling · trigger),
  plans 0023 and 0029 to `completed/` (0029 gains a decision-log line: the
  dirty-new-row prompt from R1 is **dropped** — rare, loses little — and a
  step-done checklist; 0028 ticks its five done boxes and narrows its open
  item to the three sim legs), `check_docs.sh` additions (generated-doc diff;
  active plan may not say done; stale-active warning; duplicate first cells;
  table integrity; ADR completeness; date-budget warning), and the house rule
  paragraph in `docs/README.md`.
- **B2 · specs, design docs, retro plans.** The 25 stale sentences in
  `product-spec.md` and `import-and-matching.md` (trigger, sheet, `Library
  ⋯`, portion factor, data-model tables → link `generated/db-schema.md`,
  embeddings, the pre-step-8 import passages deleted and the supersession
  note scoped by name, the "re-traced" stamp dropped, ADR-0011's write model
  described); the five design-doc traces (`DensityEntry`, `jsonld.ts` path,
  the fifth caller, `/account` + `/ingredients/new` in `navigation.md`, the
  sync line's move in `errors-and-sync-health.md`); ~6 lines of navigation's
  rejected alternatives appended to `navigation.md`; the chip-label-wins
  sentence in the product spec; the `search-and-matching.md` note that the
  import commit ranks with `searchRank`; **three retrospective plans written
  straight into `completed/`** from the board's prose — `0031-week-v3.md`
  (E1–E7, E3a, the four owner quotes), `0032-ingredient-detail-v2.md` (R1–R8,
  Q1/Q2/Q5/Q8, the owner quotes, the rev-8 USDA band measurement: 267 pairs,
  63 % / 34 %, bimodal), `0033-library-v2-decisions.md` (D1–D8 incl. the E8
  amendment; plan 0028's dangling `library-decisions.md` link repointed);
  0027's decision log corrected to the shipped band words.

**Wave 2 (after A1 lands; E after B2 lands):**

- **C · comments.** The per-file cleanup lists in the findings' appendix
  (features: ~55 deletions, ~40 rewords, 26 fixes; core/shared/test helpers/
  integration_test: ~40 lines); `units.dart` gains `batch` in its own docs;
  `[[…]]` backlinks replaced by the fact they pointed at; backticked Dart
  identifiers in `///` become `[Ident]`; a new
  `test/structure/no_transcript_comments_test.dart` (tier 1 only: backlinks,
  ISO dates, `plan \d{4}`, review/sign-off phrases, history tense, board
  versions, commented-out code); `features/ingredients/README.md` corrected.
- **D · tests.** The consolidation table in the findings §2: shared fake base
  classes, one semantics filter, `test/helpers/source_scan.dart`, table-driven
  re-proofs, `allowed_units_vectors.json` read by Dart and generated into
  `unit_admission.sql`, `_pumpWeek` and `routedHost`, the rename pass (strip
  plan/board/round codes, keep ADR refs), `portion_factor_identity_test`
  deleted with its one residual assertion folded into `week_macros_test`,
  `ingredient_manager_test` split, `test/features/recipes/domain/` flattened.
- **E · the board.** `docs/product-specs/board/`: `board.css`, `index.html`
  (legend + status table), one file per current view (library · recipe page ·
  recipe editor · import review · ingredient picker · quantity & measures ·
  recipe picker & confirm · ingredients manager · ingredient detail · week ·
  cook & shop · navigation & shell · errors & sync · account), Nested recipes
  and Ingredient detail v2 absorbed into the screens they extend,
  `not-built.html` (Cook mode, the 400 ms latch, and any other unbuilt frame,
  each citing its backlog row); every frame checked against code and the
  divergences in the findings §5 corrected on the frame; status line grammar
  `built · matches code <date> · <feature dir> · <ADR/plan>`; the old file
  deleted; `docs/product-specs/index.md` and root `AGENTS.md` describe the
  pattern: one file per screen, replace the view when a design pass lands,
  never append a version, decisions go to the plan or an ADR, the status date
  is refreshed when the view is re-verified.

**Wave 3 (after C and D land):** **F · UI anatomy** — `AnsiSheetShell`,
`askAnsi`/`refuseAnsi` (fixes the four missing animations and the action
order), `formatNumber` in `core/units/`, `AnsiCallout` + `AnsiColors.caution*`
/ `chill*` + `AnsiRadii`, `AnsiChip`, `AnsiSelectRow`, `AnsiStepperRow`,
`plural()`, `AnsiMicroLabel`, `FreshnessBar`, one `⋯` trigger, one weekday
table; the two unit-word tables merged.

**Wave 4 (after F lands):** **G · the one refactor** — `IngredientForm`
ViewModel (`@riverpod`, a freezed draft, `save({markComplete})`),
`ServingOffer` to `ingredients/domain/`, `crossReferenceFlag` to
`line_validation.dart`, `recon_line_card.dart` split into card / amount /
resolver, `UnitChipRow`/`UnitChip` to `unit_chips.dart`, `ingredientById` /
`ingredientAliases` as watched streams.

`ingredient_detail_view.dart` and `ingredient_manager_test.dart` are touched
by A1, C, D, F and G; those lanes serialize on that file.

## Decision log

- 2026-09-04 — Review run as eleven read-only Opus lanes; synthesis in
  `0030-review-findings.md`. Simon's rulings on the twelve open calls:
  - Board: split per screen **and** absorb the delta sections; root
    `AGENTS.md` must describe the pattern and how to keep it current.
  - Write the three retrospective plans before the board's prose is cut.
  - Roadmap: a Next list; plans are the unit of work. Backlog lives in a new
    `docs/exec-plans/backlog.md`.
  - `QUALITY.md` folds into `ARCHITECTURE.md` ("it constantly goes out of
    date").
  - Test names: strip plan/board codes, keep ADR references only.
  - `createStub`: delete; the smoke files seed through `saveForm`.
  - `portion_factor_identity_test`: delete ("no provenance, probably safe").
  - `tinned`: fold to `canned` with a rewrite migration (the recommendation).
  - The 0029 dirty-new-row prompt (R1): **dropped** — "guards against a rare
    case that loses little time". Recorded in 0029 when it moves.
  - Designed-not-built frames: kept in an explicit appendix, each referenced
    to its plan or backlog row.
  - `make ci`: the fast local target grows the Deno legs; `ci-full` adds the
    database legs.
  - Extraction eval history: **no re-run**; a note in `evals/runs/README.md`
    marks the discontinuity. "Happy with our choice for now."

## Notes / open questions

- Migration numbers: A2 owns `0030` (RLS + index drop + `sliced`) and `0031`
  (`tinned` rewrite). No other lane creates a migration.
- Retro plan numbers 0031–0033 are creation-ordered, like every plan; their
  status lines say "retrospective — written 2026-09-04 from the board".
- The eleven lane reports (`file:line` evidence, per-file lists) are in the
  review session's scratchpad, not the repo; the findings file carries what
  the lanes need.

## Step-done checklist

- [ ] Roadmap row for this plan: status flipped, one line on what shipped.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true (incl.
      `ci-full`).
- [ ] `make test-sim` run on a booted simulator from the main checkout after
      wave 4, result recorded here.
- [ ] Tech-debt rows added for corners knowingly cut; retired for debt paid.
- [ ] Migrations `0030`/`0031`: say in the roadmap row whether they have
      reached cloud; ledger entry in `docs/cloud-setup.md` when they do.
- [ ] `make ci` green.
