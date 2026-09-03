# Exec plan: the sim smoke — independent files, then the missing editor legs

- **Status:** done (2026-09-03)
- **Owner:** Simon (orchestrating) · agent lanes
- **Roadmap step:** cross-cutting (test harness; follows 3.5 and 7.4)
- **Created:** 2026-09-03

## Goal

`make test-sim` becomes a set of independently runnable files under
`app/integration_test/`, each seeding its own prerequisites, so a red at the
tail of one flow re-runs in one file rather than the whole suite — and then
the two flows the sim has never driven (method chips; a new ingredient created
from inside the editor) get their legs.

## Why now

The one-file suite (2,462 lines, six `testWidgets` sharing one in-process
session and one throwaway database) carries hard data chains: 1 → all (the
sign-in), 2 → 3 (the favourited two-day recipe), 4 → 5 (the chilli stub).
`--plain-name` runs a scenario mechanically but its prerequisites are missing,
so every red costs a full run, and every tracker row asking to *extend* a
scenario (there are four) makes that worse. Flutter's own guidance, and the
common shape of these suites, is one file per flow with prerequisites seeded
rather than driven through earlier tests.

The sim layer earns its keep for what only a real stack proves — sync round
trips, triggers, RLS, the root-navigator rules, provider wiring between real
repositories and real screens. It has none of that on the editor's chips or
its add-new chain, both of which are host-tested over fakes only.

## Acceptance criteria

- [x] `app/integration_test/` holds one file per flow — `auth_test.dart`,
      `recipe_editor_test.dart`, `week_test.dart`, `import_test.dart`,
      `ingredients_test.dart`, `nested_test.dart` — and a `support/` library
      with the shared boot, provisioning, waits and finders. `app_test.dart`
      is gone. (`d421331`)
- [x] Every file passes **alone** (`flutter test integration_test/<file>.dart`
      with the dart-defines) on a booted sim over the local stack, and the
      directory run is green. (2026-09-03, iPhone 17: six files alone, then
      the directory 6/6.)
- [x] Only `auth_test.dart` drives the sign-in gate; every other file signs in
      programmatically in `setUpAll` and provisions its **own** household
      (`support/stack.dart`, `SmokeStack`). No `lib/` change was needed: the
      session controller picks the in-memory session up on pump.
- [x] Prerequisites are seeded through the app's own repositories over the
      throwaway `PowerSyncDatabase` (real code, real sync), never through the
      UI of another flow: the week file seeds its favourited two-day recipe
      through `SqliteRecipeRepository.saveRecipe`, the ingredients file its
      stub through `createStub`.
- [x] `make test-sim` still runs the directory; `make test-sim FILE=week
      DEVICE=<udid>` runs one file on a chosen sim. The Makefile help line
      says so.
- [x] The recipe-editor file gains the method-chip legs (select → To
      ingredient; tap chip → rename; a timer) and the create-new-from-editor
      leg with the flesh-out form actually filled (name + default unit),
      asserting the quantity sheet opens on the form's units and the stub row
      survives the sync round trip. **Landed 2026-09-03 (lane B, finished
      by the orchestrator):** select → To ingredient, tap → rename, select →
      To timer, the refs on `recipe.steps` after the round trip; the Optional
      switch → `optional = 1` + the page tag; create-new → Create & flesh out
      → the form over the picker → the quantity sheet on the form's units →
      the stub row (`allowed_units` a real array). `make test-sim
      FILE=recipe_editor`: **2:33 of test time, 3:25 wall**.
- [x] Wall time per file and for the directory recorded here after the first
      green run. **2026-09-03, iPhone 17 (incremental build, local stack):**
      import 1:23 · ingredients 1:47 · nested 1:56 · the whole directory
      **7:19 wall (6:31 of test time)**. Auth, editor and week each passed
      alone in the lane; their individual times were lost with the lane's
      transcript (API cut-offs) and belong in the next re-drive.
- [x] **Lane C:** the ingredients file gains the tracker legs on the form it
      already opens — the density entry both phrasings (the round-tripped
      `allowed_units` asserted as a jsonb array), "Counts as" set → back →
      reopened → stuck — plus plan 0027's M-D1/D2/D3 and U-D1/U-D2 legs.
      `make test-sim FILE=ingredients` green, **2026-09-03, iPhone 17 Pro
      Max: 3:06 wall (2:26 of test time, 24 s incremental build)**, one
      `testWidgets` still. `make ci` green. No `lib/` change.
- [x] Docs updated: `app/AGENTS.md` (the smoke paragraph), `docs/QUALITY.md`
      (CI row's smoke sentence, Recipes row's "unrun by the lane" note),
      `docs/design-docs/navigation.md` (the file reference), the tracker rows
      that name `app_test.dart` or "scenario N". (Lane C: the AGENTS.md
      ingredients line, the Ingredients-manager QUALITY row, the 2026-08-29
      row retired, the 2026-09-03 sim row narrowed to the import leg.)

## Approach

Lane A is sequential and foundational; B and C fan out on top of it, each on
its own booted simulator (`-d <udid>`), each provisioning its own household so
the shared local backend is never a collision.

1. **Lane A — the split** (one worktree lane).
   - `support/` : `SmokeStack` (provision household over HTTP, programmatic
     sign-in, throwaway db, `pumpApp` and the two provider-override boots,
     `pumpUntilFound`, `waitForDb`, `waitForSyncRoundTrip`, `scrollTo`,
     `fieldIn`, `tapTab`, the error filter), plus the editor/week/import
     helpers that more than one file needs. `off_fixture.dart` stays.
   - Move each scenario into its file unchanged in behaviour; replace the
     cross-scenario reads with seeds through `SqliteRecipeRepository` /
     the ingredient repository over the throwaway db, then
     `waitForSyncRoundTrip` before the UI is opened.
   - Programmatic sign-in: `Supabase.instance.client.auth.signInWithPassword`
     in `setUpAll` (in-memory storage, as today). The app must reach the
     Library on pump without the gate; if the session controller needs a
     nudge, fix the seam rather than driving the gate.
   - Makefile: directory run unchanged; a `FILE=` variant.
   - Verify: each file alone, then the directory, on the booted sim.
     `make ci` green. One conventional commit per slice.
2. **Lane B — editor legs** (after A lands): chips + create-new-from-editor
   in `recipe_editor_test.dart`; the optional toggle in the unit sheet.
3. **Lane C — tracker legs** (after A lands, parallel with B): density entry
   and "Counts as" into `ingredients_test.dart` (tracker 2026-08-29 and
   2026-09-03 rows); the four Library v2 taps into a Library leg of
   `auth_test.dart` or its own `library_test.dart` (tracker 2026-09-02 row).
   ✅ **The Library half landed 2026-09-03 (lane D)** as its own
   `library_test.dart` + `support/library.dart`: fold/unfold, the title
   search with its `DID YOU MEAN` band and the clear, rename through the
   book `⋯`, the refused delete (count + "Move them to…"), and the reorder
   sheet — the rename and the order asserted in the local db after the round
   trip. **28 s of test time, 1:49 wall** (47 s of that the Xcode build) on
   the iPhone 17. The tracker row is retired.
   2026-09-03 rows) — **landed 2026-09-03**, together with plan 0027's
   ingredients sim legs (M-D1/D2/D3, U-D1/U-D2) on the same form; the four
   Library v2 taps into a Library leg of `auth_test.dart` or its own
   `library_test.dart` (tracker 2026-09-02 row) — **not in lane C's brief,
   still open**.

## Decision log

- 2026-09-03 — **Split, not idempotent scenarios.** Find-or-create
  prerequisites inside one file would fix re-runs but not length or
  independence. Owner agreed to the split.
- 2026-09-03 — **Programmatic sign-in outside the auth file.** The gate is
  one flow's subject, not every file's tax; the in-memory session the app
  already uses means a `setUpAll` sign-in is picked up on pump.
- 2026-09-03 — **Seed through repositories, not HTTP and not the UI.** The
  repositories are the real write path and already run against real
  PowerSync views in host tests; seeding through them keeps the sync leg real
  and the file's UI focused on its own flow.
- 2026-09-03 — **One household per file.** Provisioning is seconds over HTTP
  and makes parallel lanes on separate sims safe against the one shared
  backend.

- 2026-09-03 — **Lane A landed by cherry-pick, not fast-forward.** The lane
  was cut off four times by API overload before it could report; the
  orchestrator committed its work-in-progress from the worktree, ran the
  last two files and the directory itself, and cherry-picked the verified
  commit onto main (a release-docs commit had landed on main meanwhile).
- 2026-09-03 — **Time per file is the point.** A red in one flow now costs
  under two minutes to re-run, against seven for the old suite — the reason
  the split was worth doing before Lanes B and C add legs.
- 2026-09-03 (lane D) — **The Library legs are a file, not a leg of
  `auth_test.dart`.** The auth file's subject is the gate and it is the one
  file that starts signed out; a Library leg there would have paid the gate
  before every tap. Its own file signs in programmatically like the rest and
  seeds the second book and the recipe through `SqliteBookRepository` /
  `SqliteRecipeRepository`, so nothing it asserts came from another flow's UI.
- 2026-09-03 (lane D) — **The reorder sheet and the `DID YOU MEAN` band
  ride along.** The tracker row asked for four taps; the two it left out cost
  a few seconds each and were the last Library v2 surfaces no sim drove, so
  the row retires whole rather than narrowing.

## Notes / open questions

- Trap (memory, plan 0022): a worktree lane branches from an old commit and
  has no `.env.local`. Lanes `git merge --ff-only main` first and copy
  `.env.local` from the main checkout into the worktree root before any
  `make test-sim`.
- The `3 clove` flake (tracker 2026-09-02) should get cheaper to chase once
  the editor file runs alone; do not pad timeouts.
- Run time was never recorded for the one-file suite; record it here now.

- 2026-09-03 — **Lanes B and C were killed and landed as work in progress** by
  the orchestrator: three parallel sim lanes saturated the machine (load
  50–110) and two of them idled waiting for background runs. Their files ran
  green alone afterwards on one simulator, serially — the standing rule now
  (owner, 2026-09-03: one sim, one run at a time).

## Step-done checklist

- [x] Roadmap: no row of its own; note under the CI/harness row in
      `docs/QUALITY.md` instead.
- [x] `docs/QUALITY.md` grade for every area touched matches reality.
- [x] `app/AGENTS.md` smoke paragraph and command list true (seven files).
- [x] `make test-sim` (directory) green on a booted simulator, recorded here
      (6/6 in 7:53 before the B/C/D legs; then editor 3:25 · ingredients 2:58 ·
      library 1:49 · week 1:16 alone).
- [x] Tech-debt rows added for corners cut, retired/narrowed for the legs
      this plan pays (density entry, Library v2 taps, the 2026-09-03 sim row).
- [x] `make ci` green.
