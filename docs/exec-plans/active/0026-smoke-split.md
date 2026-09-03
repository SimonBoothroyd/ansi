# Exec plan: the sim smoke — independent files, then the missing editor legs

- **Status:** active
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
- [ ] The recipe-editor file gains the method-chip legs (select → To
      ingredient; tap chip → rename; a timer) and the create-new-from-editor
      leg with the flesh-out form actually filled (name + default unit),
      asserting the quantity sheet opens on the form's units and the stub row
      survives the sync round trip.
- [x] Wall time per file and for the directory recorded here after the first
      green run. **2026-09-03, iPhone 17 (incremental build, local stack):**
      import 1:23 · ingredients 1:47 · nested 1:56 · the whole directory
      **7:19 wall (6:31 of test time)**. Auth, editor and week each passed
      alone in the lane; their individual times were lost with the lane's
      transcript (API cut-offs) and belong in the next re-drive.
- [ ] Docs updated: `app/AGENTS.md` (the smoke paragraph), `docs/QUALITY.md`
      (CI row's smoke sentence, Recipes row's "unrun by the lane" note),
      `docs/design-docs/navigation.md` (the file reference), the tracker rows
      that name `app_test.dart` or "scenario N".

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

## Notes / open questions

- Trap (memory, plan 0022): a worktree lane branches from an old commit and
  has no `.env.local`. Lanes `git merge --ff-only main` first and copy
  `.env.local` from the main checkout into the worktree root before any
  `make test-sim`.
- The `3 clove` flake (tracker 2026-09-02) should get cheaper to chase once
  the editor file runs alone; do not pad timeouts.
- Run time was never recorded for the one-file suite; record it here now.

## Step-done checklist

- [ ] Roadmap: no row of its own; note under the CI/harness row in
      `docs/QUALITY.md` instead.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` smoke paragraph and command list true.
- [ ] `make test-sim` (directory) green on a booted simulator, recorded here.
- [ ] Tech-debt rows added for corners cut, retired/narrowed for the legs
      this plan pays (density entry, Library v2 taps, the 2026-09-03 sim row).
- [ ] `make ci` green.
