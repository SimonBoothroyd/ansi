# Cloud setup runbook — Supabase + PowerSync + Google

How to point Mise at real cloud infrastructure (Supabase Cloud + PowerSync
Cloud + Google OAuth), and the gotchas we hit doing it the first time
(2026-08-27, step 7). Day-to-day development does **not** need any of this — the
local stack (`make db-up` + dev email/password) is free, offline, and covers
everything sync-related. Reach for cloud only to exercise Google sign-in or a
real multi-device deployment.

Two independent local-vs-cloud choices: **Supabase** (local CLI vs a cloud
project) and **PowerSync** (local docker Open Edition vs PowerSync Cloud). Auth
and sync must point at the **same** Supabase — a cloud-issued JWT won't verify
against a PowerSync pointed at local Postgres, and the data lives in different
places.

For the *local* stack's own gotchas (self-hosted PowerSync service config), see
the memory note referenced from the step-7 exec plan; this doc is cloud-only.

## 1. Supabase Cloud project

1. **Create the project.** Note the project ref (e.g. `REDACTED-PROJECT-REF`).
   Data-API security toggles at creation: **Enable Data API = ON** (the app
   writes through PostgREST and calls `ensure_onboarded` via RPC), **Automatically
   expose new tables = OFF** (our migrations grant explicitly — keeps `usda_food`
   server-only by default), **Enable automatic RLS = OFF** (migrations enable RLS
   per table themselves).
2. **Push migrations.** `supabase link --project-ref <ref>` (prompts for the DB
   password) then `supabase db push`. This creates the schema, RLS, the
   `powersync` publication, and the `ensure_onboarded` / `add_household_claim`
   functions. **`db push` does NOT run seeds** (see step 2).
3. **Bound WAL growth** (ADR-0002 gotcha — an idle free-tier instance with a
   logical-replication slot can fill its disk):
   ```bash
   supabase postgres-config update --project-ref <ref> \
     --config max_wal_size=1GB --config max_slot_wal_keep_size=1GB
   ```
   (Flags go *after* the subcommand on recent CLIs.)
4. **Auth hook** (dashboard, NOT `config.toml` — cloud ignores the local file):
   **Authentication → Auth Hooks → Custom Access Token → enable → select
   `public.add_household_claim`.** This injects `household_id` into every JWT.
   **Load-bearing: no hook ⇒ no claim ⇒ nothing syncs.**
5. **Google provider:** **Authentication → Sign In / Providers → Google →** paste
   the client id/secret from a Google Cloud **Web** OAuth client whose authorized
   redirect URI is `https://<ref>.supabase.co/auth/v1/callback`. Google OAuth and
   Supabase Auth are both free at this scale. Keep the OAuth consent screen in
   "Testing" and add the household's Google accounts as test users — no
   verification needed for a private app.
6. **Redirect URL:** **Authentication → URL Configuration →** add
   `io.mise.app://login-callback` (Site URL + Redirect URLs). This is the app's
   deep-link scheme (registered natively in `ios/Runner/Info.plist` and
   `android/app/src/main/AndroidManifest.xml`).
7. **Dev convenience:** turn **Confirm email OFF** while testing email/password
   (Sign In / Providers → Email) — the free tier rate-limits confirmation emails
   hard. Turn it back on before anything real. (OAuth users are auto-confirmed.)

## 2. Seed the cloud vocab

`db push` ships schema, not data — a fresh cloud household has no ingredients.
Run the vocab seed via the **Management API** (uses your CLI login, no DB
password):

```bash
supabase db query --linked -f supabase/seed.sql
```

This creates the "Home" **template** household (`00000000-…-aa`, `is_template
= true` since migration 0008) + 291 ingredients + 88 aliases. Onboarding users
never join a template: `ensure_onboarded` **clones** its vocab (minus
`manual`/`import_correction` rows) into each fresh household. Run the other
two seeds as well so the cloud vocab carries macros — without them every cloud
ingredient is an honest-but-empty stub (this bit us: cloud showed no macros):

```bash
supabase db query --linked -f supabase/seed_usda.sql     # 8262-food reference
supabase db query --linked -f supabase/seed_prefill.sql  # macros/density onto vocab
supabase db query --linked -f supabase/seed_measures.sql # starter measures (0009/0010, step 7.6)
```

`seed_measures.sql` (GENERATED — see `supabase/seed/README.md`) adds the
starter measures ("1 potato, medium = 213 g", USDA-FDC-sourced with per-row
provenance since 0010) onto the **template** vocab only. It is idempotent:
re-running it no-ops on labels the template already has. How they reach
households:

- **New households** get them cloned at onboarding (`ensure_onboarded`),
  which stamps `household.backfilled_at` at creation.
- **Already-onboarded households do NOT retrofit from a template reseed
  alone** — the backfill does that, **exactly once per household** (0011):
  a household whose `backfilled_at` is null gains the template's measures
  the next time its user signs in (the session controller re-runs
  `ensure_onboarded` opportunistically), then is stamped. The old
  zero-live-measures gate is gone: a household that deliberately deleted its
  measures stays deleted (the 7.7 editor ships deletion).
- To **roll a reseeded template out to existing households** (dev data is
  throwaway): a human soft-deletes their measure rows —
  `update ingredient_measure set deleted_at = now(), updated_at = now()` (add
  a `where` to keep the template's fresh rows if it was reseeded first) —
  **and clears the run-once marker**
  (`update household set backfilled_at = null where not is_template`); the
  backfill then re-clones on each household's next sign-in.

Note migration 0009 also touched the **sync streams** — redeploy
`docker/powersync-cloud.streams.yaml` (step 3 below) so `ingredient_measure`
actually reaches devices (its rules are `SELECT *`, so 0010's `source` column
rides along without a further stream change).

`supabase db query --linked "<sql>"` also runs read/verify queries. Destructive
statements (`truncate`, `delete`) against cloud are intentionally blocked by the
harness — a human runs those, or use soft-delete (`update … set deleted_at`).

## 3. PowerSync Cloud instance

Dashboard at powersync.com → create an instance (free tier). Then:

1. **Database Connections → Postgres.** Paste the Supabase connection URI from
   **Supabase → Connect → Connection string → URI**, using the **Direct** (or
   Session pooler) connection on port `5432` — **not** the Transaction pooler
   (6543): logical replication needs a direct/session connection. Leave SSL on.
   The `powersync` publication (from migration 0000) is auto-detected. Wait for
   a green "Connected".
2. **Client Auth.** Check **Use Supabase Auth**, set **JWKS URI** to
   `https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`, and — **the gotcha
   we hit** — add `authenticated` to **JWT Audience**. Supabase stamps every user
   token with `aud: "authenticated"`; without this, PowerSync 401s with
   `PSYNC_S2105 Unexpected "aud" claim value`. **Save and Deploy.**
3. **Sync Streams.** This instance uses the edition-3 **streams** format (not
   legacy `bucket_definitions`). Custom JWT claims are read with
   `auth.parameter('household_id')`; a stream bundles multiple tables via a
   `queries:` list and `auto_subscribe: true`. **The committed
   [`docker/powersync-cloud.streams.yaml`](../docker/powersync-cloud.streams.yaml)
   is the source of truth**: paste that file into the Sync Streams editor →
   Validate → Deploy whenever it changes (the dashboard has no config API, so
   the repo copy is the record and the dashboard is a deploy target).
   `scripts/check_stream_drift.sh` (in `make docs-check`) keeps it
   table-for-table in lockstep with the local `docker/powersync.yaml`.
   Copy the instance URL (`https://<id>.powersync.journeyapps.com`) into
   `cloud.env` at the repo root.

## 4. Point the app at cloud

The app reads three `--dart-define`s (see the `Makefile`). To run against cloud
without disturbing local `.env.local`, pass them inline:

```bash
flutter run -d <device> \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key: sb_publishable_…> \
  --dart-define=POWERSYNC_URL=https://<id>.powersync.journeyapps.com
```

The **publishable key** (`sb_publishable_…`, Supabase → Project Settings → API
Keys) is the modern anon key and is public by design. Sign in → the session
controller onboards + connects → the `/connecting` screen shows until the first
sync completes → the Library appears, populated from cloud.

## Dashboard-only config checklist

These toggles live only in the two dashboards — no public endpoint or CLI can
read them back, so `scripts/cloud_verify.sh` cannot check them. Walk this table
whenever cloud misbehaves or after touching either dashboard, and record the
walk in the ledger below. Endpoints come from `cloud.env` at the repo root.

| # | Setting (where) | Expected value |
|---|-----------------|----------------|
| 1 | Auth hook (Supabase → Authentication → Auth Hooks → Custom Access Token) | **Enabled**, function `public.add_household_claim`. Load-bearing: no hook ⇒ no `household_id` claim ⇒ nothing syncs. |
| 2 | Redirect URLs (Supabase → Authentication → URL Configuration) | Site URL + Redirect URLs include `io.mise.app://login-callback` |
| 3 | Email confirmations (Supabase → Authentication → Sign In / Providers → Email) | OFF while testing email/password (free-tier rate limits); **turn back ON before anything real**. `cloud_verify.sh` warns while it's off. |
| 4 | Google provider (same screen → Google) | Enabled, with the Web OAuth client id/secret (§1.5). `cloud_verify.sh` checks this one via `/auth/v1/settings`. |
| 5 | PowerSync JWKS URI (PowerSync dashboard → instance → Client Auth) | "Use Supabase Auth" checked; JWKS URI = `<CLOUD_SUPABASE_URL>/auth/v1/.well-known/jwks.json` |
| 6 | PowerSync JWT audience (same screen) | Includes `authenticated` — without it every token 401s with `PSYNC_S2105` (§3.2). |
| 7 | Sync Streams (PowerSync dashboard → instance → Sync Streams) | Exact paste of [`docker/powersync-cloud.streams.yaml`](../docker/powersync-cloud.streams.yaml) → Validate → **Deploy**. Any manual dashboard edit is drift. |

## Verify it — `scripts/cloud_verify.sh` + `scripts/smoke_auth.sh`

`scripts/cloud_verify.sh` (reads `cloud.env`) is the strictly read-only health
check: JWKS/ES256, auth health + provider settings, PostgREST reachability,
PowerSync liveness, stream-drift, and a printed read-only SQL block for
`supabase db query --linked` (migration count, hook function, RLS coverage,
WAL bounds, macros count, junk-household census). Run it from a clean checkout;
record the result in the ledger below.

`scripts/smoke_auth.sh` exercises the auth → onboarding → `household_id`-claim
path against any Supabase (local or cloud) over HTTP, complementing the pgTAP
test (which tests the DB function directly):

```bash
SUPABASE_URL=https://<ref>.supabase.co \
SUPABASE_ANON_KEY=<publishable key> ./scripts/smoke_auth.sh
```

A ✓ means the dashboard hook is correctly wired (the JWT carries `household_id`).

## Gotchas, condensed

- **`aud: authenticated`** must be in PowerSync's JWT Audience (§3.2).
- **Auth hook is a dashboard setting on cloud** (`config.toml` is local-only) and
  is load-bearing for sync.
- **Edition-3 streams**: `auth.parameter('claim')`, `queries:` list,
  `auto_subscribe`. Client `powersync 1.18.0` speaks it (verified).
- **Direct/Session connection, not Transaction pooler** for PowerSync.
- **`db push` doesn't seed**; a fresh cloud household starts empty.
- **Free-tier rate limits**: confirmation-email sends throttle hard (disable for
  dev); rapid auth request bursts can return transient 404s — retry/slow down.
- **WAL config** (§1.3) or an idle instance fills its disk.
- **Mixing local + cloud on one device**: signing a device that has local dev
  data into cloud drains that local write-queue *up* to cloud (real behavior).
  For a clean slate, sign out first (clears local) or clear app data.

## Last verified (ledger)

Newest first. One entry per verification pass: what was checked, what passed,
what was left. Append an entry after every `cloud_verify.sh` run against cloud
or any dashboard-config walk.

### 2026-08-28 — step 7.5 completion pass (exec plan 0009)

Human steps done (Simon): seeds run (`seed_usda.sql` + `seed_prefill.sql`),
PowerSync instance URL into `cloud.env`, streams YAML pasted + deployed,
janitor SQL run. Then verified read-only:

- `./scripts/cloud_verify.sh`: **7 ok · 1 warn · 0 fail** — the warn is the
  known dev-mode autoconfirm; PowerSync liveness probe OK against the real
  instance URL.
- Template vocab carries macros: **248/291** (matches local parity).
- Template household is **member-less** (the leftover `diag…` E2E membership
  was soft-deleted — the janitor's example pattern is `smoke%`, so `diag%`
  needed a second pass) and holds **0 live recipes** (the two E2E test
  recipes soft-deleted).

**Google sign-in: verified end-to-end** (later the same day): consent screen →
`io.mise.app://login-callback` → session → `ensure_onboarded` → fresh
household with the full template clone (291 rows, 248 with macros) and the
default book uploaded. One live bug found: the default in-app browser sheet
never dismisses after the redirect (the app signs in underneath while the
sheet shows "loading") — fixed with `authScreenLaunchMode:
LaunchMode.externalApplication` in `sign_in_view.dart`; confirm the dismissal
on the next cloud sign-in (tracker row). Exec plan 0009 complete.

### 2026-08-28 — step 7.5 verification pass (exec plan 0009)

Verified (read-only unless noted):

- Migrations **9/9** — `supabase db push` applied `0008_onboarding_hardening`
  (sanctioned mutation); the seeded "Home" household is now `is_template =
  true` and the only template.
- JWKS serves a single **ES256** (EC) key; GoTrue healthy (v2.195.0).
- `/auth/v1/settings`: **Google enabled**, email/password enabled,
  **autoconfirm ON** (email confirmations still off — dev mode, see checklist
  row 3).
- PostgREST up (anon `401` — denied by RLS/grants, as designed).
- `add_household_claim` exists; RLS enabled on all **14** tables; WAL bounded
  (`max_wal_size` = `max_slot_wal_keep_size` = 1 GB).
- Stream-drift check green (13 tables, column lists equal, no `usda_food`).
- Publishable key fetched via `supabase projects api-keys` → `cloud.env`.

Not yet verified / open (in order of bite):

- **Vocab seeds not applied**: `seed_usda.sql` + `seed_prefill.sql` against
  cloud were permission-blocked in the agent session. Cloud vocab is still
  291 macro-less stubs (`usda_food` = 0). Human runs §2's two commands, then
  re-checks the macros count (expect ≈ 248 complete).
- **PowerSync checks skipped**: `CLOUD_POWERSYNC_URL` is `FILL_ME` — paste the
  instance URL into `cloud.env`, paste + deploy the streams YAML (checklist
  row 7), then run `./scripts/cloud_verify.sh` end to end.
- **Template hygiene**: the 2026-08-27 E2E user (`diag…@mise.app`) still holds
  a live seat in the now-template "Home", which also carries that session's 2
  recipes. Templates must be member-less — run the janitor SQL from
  `scripts/smoke_auth.sh`'s teardown block (service-role; soft-delete the
  membership; the recipes are inert but can be soft-deleted for tidiness),
  and delete the auth user in the dashboard.
- **Google browser sign-in**: still never performed (the one non-scriptable
  check). Dashboard checklist rows 1–2 and 5–7 unwalked this pass (no public
  surface; the applied hook *function* exists, but the dashboard toggle was
  last confirmed working during the 2026-08-27 E2E).
