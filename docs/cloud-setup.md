# Cloud setup runbook — Supabase + PowerSync + Google

How to point Ansi at real cloud infrastructure (Supabase Cloud + PowerSync
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
   `io.ansi.app://login-callback` (Site URL + Redirect URLs). This is the app's
   deep-link scheme (registered natively in `ios/Runner/Info.plist` and
   `android/app/src/main/AndroidManifest.xml`, and locally in
   `supabase/config.toml`).

   > **Scheme rename, 2026-09-01 (Mise → Ansi) — cutover half done.** The
   > scheme moved from `io.mise.app://login-callback` to
   > `io.ansi.app://login-callback`. Where it stands:
   >
   > - **Repo side: done.** Every registration (`ios/Runner/Info.plist`,
   >   `android/app/src/main/AndroidManifest.xml`, `supabase/config.toml`) and
   >   the code that builds the redirect now say `io.ansi.app`.
   > - **Dashboard: both URLs listed.** Redirect URLs carry `io.ansi.app://…`
   >   **and** the old `io.mise.app://…`, deliberately — a build from either
   >   side of the rename can complete a redirect while the cutover is open.
   > - **Not yet verified: nobody has signed in on a new-scheme build.** The
   >   new URL is listed, not exercised. Until one Google sign-in succeeds
   >   end to end on an `io.ansi.app` build, treat the new entry as untested.
   >
   > **Closing the cutover** is one act, in this order: walk a Google sign-in
   > on a new build → confirm it lands (session + `household_id` claim) →
   > *then* remove the `io.mise.app` entry from Redirect URLs and tick
   > checklist row 2. Removing it earlier strands any build still on the old
   > scheme; leaving it forever keeps a dead redirect target listed.
7. **Dev convenience:** turn **Confirm email OFF** while testing email/password
   (Sign In / Providers → Email) — the free tier rate-limits confirmation emails
   hard. Turn it back on before anything real. (OAuth users are auto-confirmed.)

## 2. Seed the cloud vocab

`db push` ships schema, not data — a fresh cloud household has no ingredients.

> **Since 2026-09-03 this whole section is one button:** Actions →
> **deploy-supabase** → Run workflow with **`reseed_template`** ticked runs
> the five files below in this order (release.md §4.2 step 5). Migration
> `0020` made the seed **re-runnable** — the template holds one live row per
> `match_text` and the generated `seed.sql` upserts on it — after a hand-run
> on 2026-09-03 had doubled the template (616 rows for 308 names; `0020`
> tombstones such duplicates at `db push`). One file is NOT re-runnable and
> the button knows it: `seed_usda.sql` is 8,204 plain inserts into a
> primary-keyed reference table, so it is skipped when the table is already
> populated (it never changes between releases; regenerate + `db reset` if it
> ever does). The commands stay below for the by-hand path.

Run the vocab seed via the **Management API** (uses your CLI login, no DB
password):

```bash
supabase db query --linked -f supabase/seed.sql
```

This creates the "Home" **template** household (`00000000-…-aa`, `is_template
= true` since migration 0008) + 308 ingredients + 112 aliases (counts as of
2026-09-01; `supabase/seed/vocab.jsonl` is the source they are generated from).
Onboarding users
never join a template: `ensure_onboarded` **clones** its vocab (minus
`manual`/`import_correction` rows) into each fresh household. Run the other
two seeds as well so the cloud vocab carries macros — without them every cloud
ingredient is an honest-but-empty stub (this bit us: cloud showed no macros):

```bash
supabase db query --linked -f supabase/seed_usda.sql     # 8204-food reference (Foundation 2025-04-24 + SR Legacy)
supabase db query --linked -f supabase/seed_prefill.sql  # macros/density onto vocab
supabase db query --linked -f supabase/seed_measures.sql # starter measures (basis_amount since 0012)
supabase db query --linked -f supabase/seed_curation.sql # allowed_units refresh + curation overrides (0012/7.8)
```

`seed_curation.sql` must run LAST: it re-materializes the template's
`allowed_units` with the densities prefill just landed, then applies the
audited curation overrides (`supabase/seed/curation_overrides.jsonl`).

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
  backfill then re-clones on each household's next sign-in. One honest
  nuance: the clone leg still requires **zero live measures**, so a
  household that keeps any live row (its own `manual` measures included) is
  merely re-stamped without cloning — this rollout only works by wiping a
  household's user-authored measures along with the seeded ones, which is
  acceptable solely because dev data is throwaway.

Note migration 0009 also touched the **sync streams** — redeploy
`docker/powersync-cloud.streams.yaml` (step 3 below) so `ingredient_measure`
actually reaches devices (its rules are `SELECT *`, so 0010's `source`,
and 0012's `basis_amount`/`allowed_units`, ride along without a further
stream change).

`supabase db query --linked "<sql>"` also runs read/verify queries. Destructive
statements (`truncate`, `delete`) against cloud are intentionally blocked by the
harness — a human runs those, or use soft-delete (`update … set deleted_at`).

### 2b. Rolling reseeded `ingredient` columns onto existing households

> **Not needed for migration-borne changes.** Migration `0014` (ADR-0009's
> admission amendment) backfills `allowed_units` for **every** household at
> `db push` time — §2b exists for *seed-borne* template changes only, which
> never reach existing households on their own.

A template reseed reaches **new** households only: `ensure_onboarded` clones
the vocab exactly once, at household creation. An already-onboarded household
keeps the copy it was born with — and wipe-and-re-onboard is not an option for
a household holding real recipes. So a reseed that improves the vocab (the
2026-08-31 FAO/INFOODS density fills, and the produce rows those densities
let into cup/tbsp/ml) needs an explicit rollout:
[`supabase/rollout_ingredient_refresh.sql`](../supabase/rollout_ingredient_refresh.sql).

It joins every non-template household's `ingredient` rows to the template's by
**`match_text`** (the identity that survives cloning — `ensure_onboarded`
copies it verbatim and re-associates aliases/measures by it), then moves
exactly two columns, both monotonically: it **fills** `density_g_per_ml` where
the household's is null and the template's is not, and **extends**
`allowed_units` to the union of the two lists. `updated_at` is bumped so
PowerSync replicates the rows down. It never overwrites a household's own
density, never removes a unit it admitted, never touches rows the household
created itself (no template counterpart) or soft-deleted, and never writes
`source`/`status`/`macros`. Re-running it is a no-op.

Human-run sequence, after the §2 reseed commands above:

```bash
# 1. reseed the template — the §2 block, unchanged (seed_curation.sql LAST).

# 2. PREVIEW (read-only): per-household blast radius. Copy the commented
#    preview block from the top of the script into the SQL editor, or:
supabase db query --linked "$(sed -n '/^-- with tpl_household as/,/^-- order by h.name, h.id;/p' \
  supabase/rollout_ingredient_refresh.sql | sed 's/^-- //; s/^--$//')"

# 3. run the rollout (idempotent; reports the rows it touched)
supabase db query --linked -f supabase/rollout_ingredient_refresh.sql

# 4. re-run the preview: every leg should now read 0.
```

Then **each family member signs out and back in, or just waits** — the rows
arrive over normal sync; no re-onboarding, no reinstall. (Sign-out/in is only
the impatient path; nothing about the rollout requires a new JWT.)

This generalizes: it is written as "carry the template's `density_g_per_ml`
and `allowed_units` forward", not as a one-off FAO patch, so re-run it after
any future template reseed that fills densities or widens unit admission. A
rollout that has to move a *different* ingredient column is this script with
another monotone leg — keep the fill-only/union-only shape, or a household's
own edits get clobbered.

**Interplay with the measures backfill: none — they are separate mechanisms.**
`ingredient_measure` retrofits through the run-once `backfilled_at` clone
inside `ensure_onboarded` (0011, described above); this script never reads or
writes `ingredient_measure` or `household.backfilled_at`, and never
resurrects a soft-deleted row. Run them in either order. The measures path
still costs a household its user-authored measures (it needs zero live rows to
clone) — this one costs nothing, which is exactly why `ingredient` gets a
script instead of a marker reset.

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
   is the source of truth**, and the **deploy-supabase workflow deploys it**
   (release.md §4) via the PowerSync CLI — run that workflow whenever the file
   changes, and **after any cloud `db reset`**. The manual fallback is the
   dashboard's Sync Streams editor: paste → Validate → Deploy.
   `powersync pull instance --instance-id <id>` (with a `PS_ADMIN_TOKEN`) reads
   back what is actually deployed when drift is suspected.
   `scripts/check_stream_drift.sh` (in `make docs-check`) keeps the repo copy
   table-for-table in lockstep with the local `docker/powersync.yaml` — but it
   compares the two *repo* files only; it cannot see the deployed instance,
   which is exactly how the 2026-09-01 measures outage stayed invisible: the
   deployed streams predated `ingredient_measure`, so the vocab synced and the
   measures never left the server, on every device, with every check green.
   Copy the instance URL (`https://<id>.powersync.journeyapps.com`) into
   `cloud.env` at the repo root.

## 3b. Deploy the import edge function (step 8)

Recipe import calls the `import-recipe` edge function. It is **not** deployed by
`db push` — functions ship separately, and their secrets are set separately.

**Order matters: migrations before app builds.** `supabase db push` must run
before an app build that writes new columns reaches a device. PostgREST rejects
a write naming a column it doesn't know (`PGRST204`), and PowerSync retries the
failed upload forever — sync wedges entirely, not just the one row. (Observed
live: the step-8 sim suite against a local stack that predated migration 0013 —
`make db-reset` locally, `db push` on cloud, is the cure and the prevention.)

```bash
supabase functions deploy import-recipe          # deploys the function
supabase secrets set ANTHROPIC_API_KEY=sk-ant-…  # PLACEHOLDER — paste the real key
supabase secrets set IMPORT_ALLOWED_HOUSEHOLDS=<household uuid>
```

Never commit either value, and never paste a real key into this file or a
transcript — `supabase secrets set` is the only place they belong. `supabase
secrets list` shows the names (and a digest), not the values.

- **`ANTHROPIC_API_KEY`** — the extraction provider (Claude Haiku 4.5). Missing
  ⇒ the function returns a clear 500 rather than silently degrading.
- **`IMPORT_ALLOWED_HOUSEHOLDS`** — a comma-separated allowlist of household
  UUIDs permitted to spend model tokens. This is the cost fence on a personal
  project with a public sign-in surface: a caller with a valid JWT but a
  household outside the list is refused before any model call. Get the uuid from
  the JWT's `household_id` claim (or `select id from household where not
  is_template`).

`SUPABASE_DB_URL` and the service-role key are injected by the platform — don't
set them. The function reads the caller's `household_id` from the **verified
JWT** and never from the request body, so a service-role DB connection stays
safely household-scoped.

Verify a deploy: sign in on the device and import a URL. On failure, `supabase
functions logs import-recipe` shows the handled `{error, detail}` the app
surfaces.

## 3c. Turn public sign-up OFF

The cloud project is a **private household app**, but a Supabase project with
email/password enabled will happily create an account for anyone who finds the
anon key (which is public by design). So sign-up is disabled:

**Dashboard → Authentication → Sign In / Providers → "Allow new users to sign
up" = OFF.**

Existing users still sign in; Google OAuth users already onboarded still sign
in; nobody new can self-provision. Add a household member by inviting them from
the dashboard (Authentication → Users → Invite) rather than by re-opening
sign-up. Note this also blocks `scripts/smoke_auth.sh`, which self-provisions a
throwaway user — flip sign-up on for the length of that run, then off again.

`scripts/cloud_verify.sh` checks this toggle (via `/auth/v1/settings`) and fails
if sign-up is open.

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

These settings live in the two dashboards (or, for row 9, in function secrets).
Most have no readable endpoint, so `scripts/cloud_verify.sh` can't check them —
the exceptions are noted per row. Walk this table whenever cloud misbehaves or
after touching either dashboard, and record the walk in the ledger below.
Endpoints come from `cloud.env` at the repo root.

| # | Setting (where) | Expected value |
|---|-----------------|----------------|
| 1 | Auth hook (Supabase → Authentication → Auth Hooks → Custom Access Token) | **Enabled**, function `public.add_household_claim`. Load-bearing: no hook ⇒ no `household_id` claim ⇒ nothing syncs. |
| 2 | Redirect URLs (Supabase → Authentication → URL Configuration) | **Cutover open (§1.6).** Both `io.ansi.app://login-callback` (the current scheme) and `io.mise.app://login-callback` (the pre-rename one) are listed — confirmed on the dashboard 2026-09-01. **Not verified:** no Google sign-in has been walked on an `io.ansi.app` build, so the new entry is listed but untested. Do that sign-in, then remove the `io.mise.app` entry and mark this row verified — not before. |
| 3 | Email confirmations (Supabase → Authentication → Sign In / Providers → Email) | OFF while testing email/password (free-tier rate limits); **turn back ON before anything real**. `cloud_verify.sh` warns while it's off. |
| 4 | Google provider (same screen → Google) | Enabled, with the Web OAuth client id/secret (§1.5). `cloud_verify.sh` checks this one via `/auth/v1/settings`. |
| 5 | PowerSync JWKS URI (PowerSync dashboard → instance → Client Auth) | "Use Supabase Auth" checked; JWKS URI = `<CLOUD_SUPABASE_URL>/auth/v1/.well-known/jwks.json` |
| 6 | PowerSync JWT audience (same screen) | Includes `authenticated` — without it every token 401s with `PSYNC_S2105` (§3.2). |
| 7 | Sync Streams — deployed config matches [`docker/powersync-cloud.streams.yaml`](../docker/powersync-cloud.streams.yaml) | Deployed by the **deploy-supabase workflow** (release.md §4); dashboard paste is the fallback. Verify with `powersync pull instance` when in doubt — this is the one row no repo-side check can see, and stale streams starve devices silently (2026-09-01). Any manual dashboard edit is drift. |
| 8 | **Public sign-up** (Supabase → Authentication → Sign In / Providers → "Allow new users to sign up") | **OFF** (§3c). The anon key is public by design, so an open sign-up lets a stranger provision a household. `cloud_verify.sh` checks this and fails if it's open. Turn it on only for the length of a `smoke_auth.sh` run, then off again. |
| 9 | **Edge-function secrets** (`supabase secrets list`) | `ANTHROPIC_API_KEY` and `IMPORT_ALLOWED_HOUSEHOLDS` both present, and `import-recipe` deployed (§3b). Values are never readable — the listing shows names only, which is all this row checks. |

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
- **`db push` doesn't deploy edge functions either** — `supabase functions
  deploy import-recipe` + `supabase secrets set …` are separate steps (§3b).
- **Sign-up must stay OFF** (§3c): the anon key is public, so an open sign-up is
  an open door. `smoke_auth.sh` needs it briefly — remember to close it again.
- **Mixing local + cloud on one device**: signing a device that has local dev
  data into cloud drains that local write-queue *up* to cloud (real behavior).
  For a clean slate, sign out first (clears local) or clear app data.

## Last verified (ledger)

Newest first. One entry per verification pass: what was checked, what passed,
what was left. Append an entry after every `cloud_verify.sh` run against cloud
or any dashboard-config walk.

### 2026-09-03 — polish pass (plan 0022) deploy

- `deploy-supabase` run `33702716396` from `main@fb13bf3`: **link ✓ · `db
  push` ✓ (0018 fold_diacritics, 0019 shopping_week) · `functions deploy
  import-recipe` ✓ (the shared normalizer's diacritic fold) · sync streams
  ✗** — `powersync@0.10.0 deploy sync-config` now refuses without a
  `powersync/` project directory ("Run powersync init cloud … first"), so
  the leg never ran. **No-op for this deploy**: `docker/powersync-cloud.streams.yaml`
  last changed at `3c9d75e` (before the pass) and both rules on the tables
  0019 touched are `select *`, so the cloud streams already match. Fixing
  the leg is a tracker row; re-run it after any cloud `db reset`.
  **Fixed the same night:** the CLI needs a project directory even with an
  explicit file path, so the repo now carries `powersync/cli.yaml` (`type:
  cloud`, nothing else — no `service.yaml`, so this button can never rewrite
  the instance config) and the workflow's `validate` is scoped to
  `--validate-only sync-config`. Runs `33703880935` (directory present,
  unscoped validate still wanted `service.yaml`) → `33704042001` **all four
  legs green**, streams deployed ("Deployment operation completed
  successfully"). `cloud_verify` after it: 8 ok · 1 warn · 0 fail.
- `scripts/cloud_verify.sh`: **8 ok · 1 warn · 0 fail** (the warn is the
  standing junk-household census).
- **Still human-run, not yet done:** the template reseed for the piece
  curation + the folded seed (§2: `seed.sql` → `seed_usda` → `seed_prefill`
  → `seed_measures` → `seed_curation`, the last one last). Note that §2b's
  rollout only *extends* `allowed_units`, so the piece **removal** reaches
  existing households only by wipe-and-re-onboard (dev data is throwaway).
- App: `v0.2.0` tagged at the same commit after this deploy (release.md §5
  order: cloud first, then the tag).

### 2026-09-01 — full cloud reset and rebuild

Human steps done (Simon): **`supabase db reset --linked`** — the cloud database
dropped and rebuilt from every migration `0000`–`0016` (17 files) and all five
seeds in `config.toml`'s order (`seed.sql` → `seed_usda.sql` →
`seed_prefill.sql` → `seed_measures.sql` → `seed_curation.sql`) — then
`supabase functions deploy import-recipe`.

What this settles:

- **`0014`–`0016` are on cloud.** ADR-0009 admission, the never-fail USDA
  prefill trigger, the density-change trigger, prefill-on-rename, and
  `probe_usda()` all landed with the rebuild. The step-8.5 deferral ("not yet
  pushed to cloud") is retired — the roadmap row was trued up in the same pass
  as this entry.
- **The template vocab is current.** The rebuilt seeds carry the FAO/INFOODS
  fills *and* step 8.5's **D4d** hand pass, plus Canned Diced Tomatoes: **308
  ingredients · 112 aliases · 297 with a density · 270 measures over 142
  ingredients** (measured against a local `db reset` off the same committed
  seeds).
- **§2b's rollout was not needed this cycle.** `rollout_ingredient_refresh.sql`
  exists to carry a *reseeded template* onto households that were onboarded
  earlier. A reset is a rebuild, not a patch — there is no older clone left to
  carry forward, so the script has nothing to do until the next seed-borne
  change lands on a standing database.

Left open, in order of bite:

- **`cloud_verify.sh` has not been re-run since the rebuild.** The last clean
  run (9 ok · 0 warn · 0 fail) predates it. Run it before trusting any row
  below.
- **A rebuild takes the database back to the seeds' state.** Households,
  recipes, and anything else the DB held are gone — dev data is throwaway by
  standing rule. Note the interaction with **§3c**: public sign-up is OFF, so
  if the reset also cleared `auth.users`, the first sign-in needs sign-up
  flipped on for that one run (then off again) or a dashboard invite. Confirm
  which at the next sign-in rather than assuming.
- **Dashboard-only settings live outside the database** and a reset does not
  touch them — but checklist row 1's target, `public.add_household_claim`, was
  dropped and recreated by the rebuild. The hook resolves the function by
  name, so it should still bind; the next sign-in carrying a `household_id`
  claim is the proof.
- **The OAuth scheme cutover is still open** (§1.6, checklist row 2): both
  redirect URLs are listed, and no sign-in has been walked on an `io.ansi.app`
  build. That one sign-in closes three of these bullets at once.

### 2026-08-31 — step-8 hardening rollout

Human steps done (Simon): signup disabled + email provider off (Google-only,
§3c); `ANTHROPIC_API_KEY` + `IMPORT_ALLOWED_HOUSEHOLDS` secrets set;
`import-recipe` deployed (twice — the hardened function, then the
benchmark-v2 adapter revision); §2 template reseed (FAO densities + produce
volume admission) followed by `rollout_ingredient_refresh.sql` per §2b —
preview → rollout → preview-reads-zero. Google sign-in verified live on the
sim against cloud (external-browser flow foregrounds cleanly). Then verified
read-only:

- `./scripts/cloud_verify.sh`: **9 ok · 0 warn · 0 fail** — including the new
  signup-disabled check and the Google-only email posture (script updated this
  pass to treat email/password disabled as the intended cloud state).

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
