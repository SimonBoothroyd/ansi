# Exec plan: Post-step-7 hardening sweep

- **Status:** done
- **Owner:** agents (seven parallel workstreams + a closing pass), 2026-08-27
- **Roadmap step:** Step 7.4 — post-step-7 hardening sweep
  ([roadmap row](../roadmap.md))
- **Created:** 2026-08-27 (written as the durable record after the sweep
  landed; the roadmap 7.4 row carries the one-line summary)

## Goal

Pay down the criticals the post-step-7 review found — data-corrupting sync
bugs, session races, onboarding privacy/races — and tighten every layer the
review graded soft, without adding features.

## What shipped (the seven workstreams)

1. **Connector** (`app/lib/core/sync/connector.dart`): decodes the three
   server `jsonb` columns (`recipe.steps`, `plan_entry.eaters`,
   `ingredient.macros`) before upload — the old string upload double-encoded
   them on the round-trip and crashed every reader — and every PUT defaults
   `deleted_at: null`, so a local re-insert clears a server tombstone.
   Unit-tested against real `ps_crud` ops, incl. fatal-vs-transient
   PostgREST handling.
2. **Recipe saves** (`recipe_repository_impl.dart`): `saveRecipe` diffs
   children against the stored tree (kept ids update, new insert, dropped
   soft-delete) instead of delete + re-insert, which had tombstoned every
   child server-side on any edit.
3. **Session** (`core/sync/session.dart`): a sealed state machine
   (`SignedOut/Connecting/Error/Ready`) with `refreshSession()` after
   onboarding (the signup token lacks the `household_id` claim → empty first
   sync), retry/sign-out on `/connecting`, cached-household offline relaunch,
   serialized auth events, and the initial `_handle` deferred via
   `scheduleMicrotask` (killing the launch-time uninitialized-provider
   StateError).
4. **Migration 0008 + pgTAP**: advisory-locked `ensure_onboarded` (no
   seat-race double-joins), vocab cloned from the `is_template` household
   (excluding `manual`/`import_correction` — private data never leaves a
   household), column-level grant lock on `is_template`; ~50 pgTAP
   assertions incl. the access-token hook and an all-13-tables RLS loop.
5. **Domain honesty + watch coverage**: density ≤ 0 and unknown units
   excluded from conversions, imprecise dedupe, same-day batch hint,
   two-device shopping-entry merge; `watch()` LEFT-JOIN gaps closed with a
   structural watch-coverage test.
6. **Search**: query normalization + word-boundary matching (was raw prefix).
7. **Docs + UI polish**: `make docs` really generates
   `docs/generated/db-schema.md`; glyphs → `FLucideIcons`;
   `allowedUnitsFor` unit filtering; group-name doubling and quick-pick
   summaries fixed. Plus the auth-aware, self-provisioning `make test-sim`.

## Verified

- **On-device (fresh install, in-app sign-up):** vocab (291) + default book
  sync immediately; restart mints no duplicate book; method steps round-trip
  as a real jsonb array with no crash; a title edit leaves every child row
  live.
- **`make ci`** green across the merge.
- **Closing pass (this plan):** the smoke's `TODO(step7-fixes)` deferred
  assertions were re-enabled — method steps typed and asserted on the recipe
  view, the saved recipe re-opened and edited (children survive the server
  round-trip), the rendered title asserted post-save, scenario 3's
  `db.disconnect()` removed so week → cook → shop runs over **live sync**
  with an explicit `plan_entry.eaters` round-trip assertion, and the guarded
  session pre-mount collapsed to a plain `ProviderScope` (root cause fixed by
  workstream 3). `make test-sim` green twice consecutively on the iPhone 17
  sim, 2026-08-27.

## Decision log

- 2026-08-27 — Sweep run as seven parallel, independently-merged workstreams;
  this plan written afterwards as the durable record (the wave worked from
  the review findings, not a pre-staged plan).
- 2026-08-27 — Scenario 3 of the smoke stays one `testWidgets` (3a–3c build
  on each other's data; live-sync coverage was the point, not the split).

## Notes / open questions

- Remaining tails live in the [tech-debt tracker](../tech-debt-tracker.md):
  airplane-mode queue-drain and two-client concurrent-edit tests, the
  Google browser sign-in (→ plan 0009), ghost-users-after-reset dev UX,
  edit-top-up unit filtering.

## Step-done checklist

- [x] Roadmap row updated: 7.4 links here; status was already 🟢.
- [x] `docs/QUALITY.md` grade for every area touched matches reality (sync,
      recipes, shopping, docs/harness rows refreshed).
- [x] `app/AGENTS.md` "Current focus" and command list still true (test-sim
      section rewritten: auth-aware, self-provisioning, live sync).
- [x] `make test-sim` run on a booted simulator: green ×2 (2026-08-27,
      iPhone 17 sim, all three scenarios incl. live-sync week→cook→shop).
- [x] Tech-debt rows added/retired honestly (smoke-deferred-asserts row
      retired; airplane-mode/two-client, ghost-user, edit-top-up rows stand).
- [x] `make ci` green.
