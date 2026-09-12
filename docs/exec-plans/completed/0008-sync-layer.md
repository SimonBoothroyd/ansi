# Exec plan: Sync layer — PowerSync + household + offline queue

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 7 — sync layer (`app/lib/core/sync`, `docker/`, `supabase/`)
- **Created:** 2026-08-27

## Goal

Turn the offline-only app (steps 1–6 open the local PowerSync db but never
`.connect()`) into a real shared-household app: sign in, resolve the household,
connect PowerSync, and let the offline write queue reconcile between two
devices. The three faked-local tables (`ingredient`/`ingredient_alias` bundle-
seeded; `household_member` bootstrap-seeded) flip to server-owned synced tables,
and the hardcoded `kDevHouseholdId` gives way to the signed-in user's household.

Because all dev data is throwaway, onboarding is simple and destructive — no
migration/preservation machinery.

## Decisions (confirmed with Simon, 2026-08-27)

- **Infra: both.** Wire + verify against the local stack (`make db-up`); keep
  everything cloud-ready (env-switched) with a documented cloud/Google cutover.
- **Auth: dev auth now, Google OAuth wired.** Local Supabase email/password
  proves sync end-to-end this step; the Google button ships but is verified
  later against the real Google project.
- **Vocab: flip to synced.** Server owns the vocab (macros already present
  server-side after `seed_prefill.sql`); sync it down, drop `VocabSeeder`.

## Acceptance criteria

- [x] `0007_sync.sql`: `household_member.sort_order`; `ensure_onboarded()`
      (SECURITY DEFINER, idempotent); `add_household_claim()` access-token hook
      injecting `household_id`; starter-vocab clone for a fresh household.
- [x] `supabase/config.toml`: access-token hook registered; dev email/password;
      Google provider documented (commented). (JWKS lives in `powersync.yaml`.)
- [x] `docker/powersync.yaml`: `replication.connections` wired (discrete PG
      fields); the `household` bucket lists all 13 synced tables; client-auth via
      Supabase JWKS (ES256).
- [x] `schema.dart`: `ingredient`/`ingredient_alias`/`household_member` (+ new
      `household`) flipped to synced; `ingredient.macros` +
      `ingredient_alias.household_id`/`source` added to mirror the server.
- [x] `MiseConnector` implemented (`fetchCredentials` + `uploadData`); unit-tested.
- [x] Auth: session provider + `SignInView` (dev email/password + Google button);
      router redirect; `bootstrap` initialises Supabase, session controller calls
      `ensure_onboarded`, connects on session, disconnects on sign-out; seeders
      removed.
- [x] `currentHouseholdId` provider; `kDevHouseholdId` removed from the four repo
      write paths (kept as the tests' default).
- [x] Tests: connector unit; repos still green on real schema (flipped views);
      pgTAP onboarding/token-hook test. `make ci` green.
- [x] Live-stack sync verified: service replicating; a real onboarded ES256 token
      returned the household bucket (414 ops) over `/sync/stream`. (Full
      two-device UI run + offline-queue drain → the auth-aware `make test-sim`
      rewrite, tracked as tech-debt.)
- [x] Docs: roadmap, SECURITY, QUALITY, ADR-0006, READMEs, this log.

## Approach

Dependency order:

1. **Server** — `0007_sync.sql` + `config.toml`; verify with `supabase db reset`
   / `supabase test db` (real Postgres, deterministic).
2. **Sync rules** — finish `docker/powersync.yaml`.
3. **Client schema flip** — `schema.dart`.
4. **Connector** — `MiseConnector`.
5. **Auth + bootstrap** — session provider, `SignInView`, router redirect,
   `bootstrap` connect/disconnect, remove seeders.
6. **De-hardcode household** — `currentHouseholdId` provider + the four repos.
7. **Tests + docs + two-device sim/web run.**

## Decision log

- 2026-08-27 — **Plan approved** (both infra; dev auth now + OAuth wired; flip
  vocab to synced). Local stack tooling (supabase 2.115, docker) confirmed
  runnable, so the server slice was verified against real Postgres.
- 2026-08-27 — **Onboarding = join-or-create RPC.** `ensure_onboarded` joins a
  household with < 2 live members (the seeded "Home" locally, so A and B share
  it) else creates one and clones the richest household's vocab+aliases (keyed on
  `match_text`). Chosen over an `auth.users` trigger so the client can await a
  resolved `household_id` before `.connect()`. Pinned by `supabase/tests/
  onboarding.sql` (9 assertions, incl. the clone path). See ADR-0006.
- 2026-08-27 — **`household_id` via an access-token hook**, per the boundary the
  0001 migration already anticipated. Verified live: an onboarded user's reissued
  JWT carries `household_id`; a bare user's does not.
- 2026-08-27 — **De-hardcoding pattern.** Each of the four write-path repos took
  an optional `householdId` (default `kDevHouseholdId`, kept for tests); the
  providers pass `currentHouseholdIdProvider`. Zero repo-test churn.
- 2026-08-27 — **Two-provider database split.** `powerSyncDatabaseProvider` (the
  concrete db, for `.connect()`) + `databaseProvider` (the `SqliteConnection`
  surface repos/tests use) derived from it. Tests still override `databaseProvider`
  directly — unchanged.
- 2026-08-27 — **Live-stack infra fixes** (all needed before sync worked; saved
  to memory [[mise-powersync-supabase-local-stack]]): ES256 tokens ⇒ verify via
  **JWKS** not HS256; the auth hook needs a full `supabase stop/start`; jpgwire
  honours `sslmode: disable` only via **discrete** PG fields; `start -r unified
  -c` CLI; `sync_rules: content: |` inline format. End state proven: HTTP 200 +
  the `household` bucket (414 ops) over `/sync/stream` with a real token.
- 2026-08-27 — **`/connecting` gate (bug fix, found on the cloud sim run).** The
  first cut redirected to the app the instant a Supabase session existed, but the
  session controller resolves `household_id` a beat later (onboard → connect →
  `waitForFirstSync`). So the Library built, read `currentHouseholdId`, and threw
  a `ProviderException` until the session settled. Fixed: `router` is now a
  provider with a two-stage redirect — no session → `/sign-in`; signed in but
  `AppSession` not ready → `/connecting` (a "Setting up…" screen); ready → the
  app. Refreshes on auth *and* session-controller changes. Verified on the sim
  (app reaches the Library, no crash).
- 2026-08-27 — **Deep-link scheme registered natively.** `io.mise.app` added to
  `ios/Runner/Info.plist` (`CFBundleURLTypes`) and
  `android/app/src/main/AndroidManifest.xml` (a VIEW/BROWSABLE intent-filter) so
  the OAuth redirect (`io.mise.app://login-callback`) reopens the app.
- 2026-08-27 — **Cloud stood up + E2E verified against real infra.** Supabase
  Cloud project + PowerSync Cloud instance (edition-3 **Sync Streams**, not
  legacy `bucket_definitions`; `auth.parameter('household_id')`). Runbook:
  [`docs/cloud-setup.md`](../../cloud-setup.md). Two cloud-specific gotchas
  found: PowerSync's **JWT Audience must include `authenticated`** (Supabase's
  `aud`), and the auth hook is a **dashboard** setting on cloud. End state: the
  real app on the iOS sim signed in, onboarded, connected, and synced
  **bidirectionally** — cloud's 291-ingredient vocab down, the sim's local
  recipes up into cloud Home (via `MiseConnector.uploadData`, through RLS).
  Client `powersync 1.18.0` speaks edition-3 streams — no SDK bump needed.

## What is and isn't tested

Being explicit (the code is real; the coverage is uneven):

**Automated, in `make ci`:**
- Connector decision logic (`isFatalPostgrestError`, `fetchCredentials` when
  signed out) — unit test.
- Every repo against the *real* flipped PowerSync schema (views) — repo tests,
  green with the synced-table flip.
- Domain logic unchanged (units, cook plan, shopping) — still green.

**Automated, local gate (`supabase test db`, not CI):**
- `ensure_onboarded` (idempotent, join-then-create, vocab clone) +
  `add_household_claim` — pgTAP (`supabase/tests/onboarding.sql`, 9 assertions).

**Manual / live, one-off (NOT automated):**
- Local stack: PowerSync service replicating; `/sync/stream` returned the
  household bucket (414 ops) with a real token.
- Cloud, via the real app on the iOS sim + `scripts/smoke_auth.sh`: sign-in →
  onboard → `household_id` claim → PowerSync connect → bidirectional sync (vocab
  down, recipes up). The `/connecting` gate fix.

**NOT tested at all (known gaps):**
- **Google OAuth browser flow** — never exercised end-to-end (no real Google
  login performed). Only the code path, deep-link, and dashboard config exist.
- **Offline queue drain on network loss** — the upload path works (recipes
  reached cloud), but airplane-mode → reconnect was not explicitly exercised.
- **Two-device concurrent sync / conflict resolution** (LWW, union of
  independent rows) — the model is spec'd but untested with two live clients.
- **`uploadData` patch/delete mapping** — only inserts were observed syncing up;
  update and soft-delete op mapping is unverified live.
- **Fresh-cloud-household vocab clone** — cloud "Home" was seeded manually; the
  `ensure_onboarded` clone path for a brand-new household is pgTAP-tested locally
  but not exercised on cloud.
- **`make test-sim`** integration smokes — skipped (auth-gate rewrite pending).

## Notes / open questions

- Per-household vocab clone is only exercised by a *fresh* household (local dev
  joins the seeded "Home"); a truly empty cloud DB has nothing to clone — needs a
  vocab template. Cloud-cutover task.
- The `make test-sim` smoke pre-dates the auth gate and now lands on `/sign-in`;
  it needs an auth-aware rewrite (override the session or stub the gate).
  Tracked in the tech-debt tracker. CI is unaffected (`flutter test` skips
  `integration_test/`).

## Cloud / Google cutover

Done for one project and written up as a runbook:
[`docs/cloud-setup.md`](../../cloud-setup.md) — Supabase project + migrations +
Data-API toggles + WAL config + auth hook + Google provider + URL config, the
cloud vocab seed, the PowerSync Cloud instance (streams + JWKS +
`authenticated` audience), and pointing the app at cloud via `--dart-define`.
Remaining for a *real* launch: verify the Google browser flow with a real
account; a starter-vocab template for brand-new cloud households (tech-debt).

## Step-done checklist

- [x] Roadmap row updated (status + one line shipped/deferred).
- [x] `docs/QUALITY.md` sync grade → 🟢.
- [x] `docs/SECURITY.md` auth/onboarding/token-hook section; ADR-0006 added.
- [x] `make ci` green; live-stack sync verified (recorded above).
