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

This creates the "Home" household (`00000000-…-aa`) + 291 ingredients + 88
aliases. `onboard`ing users then join Home and sync that vocab. (`seed_usda.sql`
is server-only reference for import — not needed for app sync;
`seed_prefill.sql` adds macros if wanted.)

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
   `queries:` list and `auto_subscribe: true`:
   ```yaml
   config:
     edition: 3
   streams:
     household:
       auto_subscribe: true
       queries:
         - SELECT * FROM household WHERE id = auth.parameter('household_id')
         - SELECT * FROM household_member WHERE household_id = auth.parameter('household_id')
         - SELECT * FROM ingredient WHERE household_id = auth.parameter('household_id')
         # …every synced table; usda_food is NEVER listed (ADR-0005)
   ```
   Validate + Deploy. Copy the instance URL (`https://<id>.powersync.journeyapps.com`).

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

## Verify it — `scripts/smoke_auth.sh`

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
