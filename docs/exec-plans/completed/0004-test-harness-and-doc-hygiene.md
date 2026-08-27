# Exec plan: Real-PowerSync test harness + doc hygiene

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 3.5 — test harness + doc hygiene (intermediate; between books and planning)
- **Created:** 2026-08-27

## Goal

Close the gap that let view-only SQL and provider-lifecycle bugs ship green
through steps 2–3: repository tests run against a **real `PowerSyncDatabase`
opened from the real `core/sync/schema.dart`** (view-backed tables, in plain
`flutter test`), one enabled integration smoke exists behind `make test-sim`,
and the satellite docs (QUALITY.md, app/AGENTS.md focus, tech-debt rows) stop
drifting via a step-done checklist.

## Why now (context)

Steps 2 and 3 each shipped a bug class that `flutter test` could not see,
because the repo tests run on plain SQLite with hand-written `CREATE TABLE`s
(`test/helpers/test_db.dart`):

- `INSERT … ON CONFLICT` (UPSERT) and subquery `UPDATE/DELETE` are illegal on
  PowerSync's view-backed local tables but legal on real tables — the step-2
  `saveRecipe` bug and the step-3 risk class. See tech-debt rows 2026-08-26.
- The hand-written test schema can drift from `schema.dart` (it already lacks
  columns the real schema has), so a column missing from `schema.dart` passes
  tests and fails on-device.
- `watch()` re-fire behaviour, `ensureDefaultBook()` idempotency, and provider
  lifecycle across async gaps were only exercised manually on the iOS sim.

Separately, the docs around the roadmap drifted (stale QUALITY.md grades, stale
"Current focus" in app/AGENTS.md, a `skip: true` integration stub with a
`TODO(step-2)` two steps old) because "step done" has no checklist.

## Acceptance criteria

- [x] Repo tests open a real `PowerSyncDatabase` from `core/sync/schema.dart`
      (PowerSync core extension loaded on the host VM — see PowerSync's unit
      testing guidance), replacing `test/helpers/test_db.dart`'s hand-written
      tables. All existing repository tests pass against it unchanged in
      behaviour.
- [x] A regression test proves the harness rejects view-illegal SQL (e.g. an
      `INSERT … ON CONFLICT` against `recipe` fails), so the harness itself
      can't silently degrade back to real tables.
- [x] New tests: `ensureDefaultBook()` called twice is a no-op (idempotency +
      no double-adoption), and the recipe→book→section watched join re-fires on
      a book/section rename (stale-breadcrumb class).
- [x] `integration_test/app_test.dart` stub replaced by a real smoke: boot →
      create a recipe → create a section → file the recipe → assert the
      breadcrumb; runnable via a new `make test-sim` target (booted sim
      required; NOT added to CI — local gate only).
- [x] Step-done checklist added to `docs/exec-plans/_template.md` and
      referenced from `docs/exec-plans/README.md`: roadmap row updated,
      QUALITY.md grade updated, app/AGENTS.md focus current, `make test-sim`
      smoke run for feature steps, tech-debt rows added *and* retired.
- [x] Doc refresh: QUALITY.md grades reflect reality (steps 1–3 done);
      app/AGENTS.md "Current focus" becomes a pointer to the roadmap instead of
      duplicated status; roadmap step 9 note clarified (macros exist
      server-side — 248 complete after prefill; the *bundled* vocab is stub
      until step 7 sync or a deliberate bundle enrichment); app/AGENTS.md gains
      a one-line phone-first layout rule (fixed logical-px spacing is fine;
      no screen-derived sizes outside a future shared max-width wrapper).
- [x] Tech-debt tracker: the two 2026-08-26 view/lifecycle rows retired (or
      narrowed to what genuinely remains, e.g. drag-reorder); the pubspec.lock
      row updated (lock is committed — row is half-paid).
- [x] `make ci` green; `make docs-check` green.

## Approach

Dependency order:

1. **Harness** — add a test helper that opens `PowerSyncDatabase` with a test
   open-factory loading the PowerSync SQLite core extension for the host OS
   (macOS/Linux), using the schema from `core/sync/schema.dart`. Delete
   `test_db.dart`'s hand-written DDL.
2. **Migrate repo tests** (`recipe_repository_test.dart`,
   `book_repository_test.dart`, `ingredient_repository_test.dart`) onto it;
   add the view-rejection regression test and the two new behaviour tests.
3. **Integration smoke** — implement the flow in `integration_test/`, add
   `make test-sim`, document it in app/AGENTS.md's verify loop.
4. **Docs + checklist** — template/README checklist, QUALITY.md, app/AGENTS.md,
   roadmap step 9 wording, tech-debt rows.

## Decision log

- 2026-08-27 — Plan created from a holistic harness review: the tech-debt
  tracker had already diagnosed the gap (2026-08-26 rows) but nothing promoted
  it into tooling — this step is that promotion (core belief: enforce
  invariants with tooling, not prose).
- 2026-08-27 — Integration smoke stays a **local** gate (`make test-sim`), not
  CI: macOS runners are slow/expensive at hobby scale; the real-PowerSync unit
  harness carries the CI burden for the view-only bug class.
- 2026-08-27 — QUALITY.md is **refreshed and kept** (added to the step-done
  checklist) rather than folded into the roadmap — less churn to links and
  structure.
- 2026-08-27 — No bundle enrichment of `vocab.jsonl` with macros in this step:
  surfacing macros pre-sync is a product decision (roadmap step 9), not a
  harness fix. This step only corrects the misleading wording.
- 2026-08-27 — Extension loading: `scripts/fetch_powersync_core.sh` downloads
  the core extension for the host OS/arch into `app/` (git-ignored), pinned to
  **v0.4.11** — the version `powersync_flutter_libs` links on-device, so host
  tests and the phone run the same engine. `make test-app` runs it; CI fetches
  it too. `test_db.dart` loads it by absolute path through a
  `PowerSyncOpenFactory` subclass rather than relying on the linker's search
  path.
- 2026-08-27 — macOS ships SQLite with `OMIT_LOAD_EXTENSION`, so the system
  library cannot register the extension at all (`sqlite3_auto_extension` →
  MISUSE). The harness points sqlite3 at Homebrew's build instead; Linux uses
  the distro library. This is a real machine prerequisite (`brew install
  sqlite`), documented in app/AGENTS.md and tracked as debt.
- 2026-08-27 — The plan's premise was half right: on PowerSync's views only
  `INSERT … ON CONFLICT` is rejected. Subquery `UPDATE`/`DELETE`, `UPDATE …
  FROM`, `INSERT OR REPLACE` and `RETURNING` all run fine through the INSTEAD OF
  triggers (probed against the real schema). The regression test therefore pins
  the UPSERT rejection plus "these objects are views", not the wider claim.
- 2026-08-27 — The new rename test exposed a live bug: `watchRecipe` named
  `book`/`book_section` in its watched query, but SQLite **omits a LEFT JOIN
  whose columns are never selected**, so those tables never reached PowerSync's
  trigger set and a renamed book/section left a stale breadcrumb on screen.
  Fixed by selecting a column from each joined table. `watchLibrary` was already
  safe (its join keys aren't unique, so the planner can't drop them) and is now
  covered by a test too.
- 2026-08-27 — `app/pubspec.lock` was in `.gitignore` while being tracked;
  removed the stale ignore line rather than leaving the contradiction.
- 2026-08-27 — The sim smoke filters one framework semantics assertion that any
  Forui dialog triggers while the accessibility tree is live (reproduces in a
  plain widget test with `ensureSemantics()`; forui is already at the newest
  0.22.x). Narrow filter, tech-debt row, everything else still fails the test.

## Notes / open questions

- The documented PowerSync route worked in plain `flutter test`; no `dart test`
  fallback was needed.
- Provider-lifecycle bugs (the `LibraryActions` crash class) are still only
  covered by the one sim smoke — see the narrowed tech-debt row. The standing
  rule remains: mutations go through keep-alive repo providers.
- The Linux/CI leg of the harness (apt `libsqlite3-dev` + the fetched
  extension) is written but unproven — it has not run on a runner yet.

## Step-done checklist

- [x] Roadmap row updated (3.5 → 🟢, with the stale-breadcrumb finding).
- [x] `docs/QUALITY.md` grades rewritten against reality.
- [x] `app/AGENTS.md` focus is a pointer; commands and sim section current.
- [x] `make test-sim` run on a booted iPhone 17 simulator — green.
- [x] Tech-debt rows added (host SQLite, forui semantics) and retired/narrowed
      (view-only SQL, provider lifecycle, pubspec.lock).
- [x] `make ci` green.
