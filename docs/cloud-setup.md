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
> the files below in this order (release.md §4.2 step 5). Migration `0020`
> made the seed **re-runnable** — the template holds one live row per
> `match_text` and the generated `seed_vocab.sql` upserts on it. (A hand-run
> on 2026-09-03 had doubled the template, 616 rows for 308 names; the answer
> was a **full cloud reset**, not a repair migration — see the posture
> below.) One file is NOT re-runnable and the button knows it:
> `seed_usda.sql` is 8,204 plain inserts into a primary-keyed reference
> table, so it is skipped when the table is already populated (it never
> changes between releases; regenerate + `db reset` if it ever does). The
> commands stay below for the by-hand path.

**The direction is cloud → seed.** The owner's live household rows are the
curated truth; `supabase/seed/snapshot.jsonl` is an export of them and
`supabase/seed_vocab.sql` is generated from it (`supabase/seed/README.md` has
the export command and the regeneration). What this section does is the other
half of that loop: it **promotes the snapshot back to the template**, so every
household created after it clones the curated rows.

Run the vocab seed via the **Management API** (uses your CLI login, no DB
password):

```bash
supabase db query --linked -f supabase/seed_vocab.sql
```

This creates the "Home" **template** household (`00000000-…-aa`, `is_template
= true` since migration 0008) and its whole curated vocabulary in one file:
ingredients with their densities, macros, provenance, piece weights and
explicit `allowed_units`, plus their aliases and measures. The counts are
computed into `supabase/seed/counts.json` when the seed is generated, never
typed into a doc. Onboarding users never join a template: `ensure_onboarded`
**clones** its vocab (minus `manual`/`import_correction` rows) into each fresh
household. Run the reference seeds as well — without them the "create a new
ingredient" USDA search has nothing to search:

```bash
supabase db query --linked -f supabase/seed_usda.sql     # 8204-food reference (Foundation 2025-04-24 + SR Legacy)
supabase db query --linked -f supabase/seed_usda_index.sql # BM25 search index over it (0029) — probe_usda RAISES without it
```

`seed_vocab.sql` ends with its own invariants (R1 volume-default ⇒ density,
R2 kitchen density band, R3 the piece rule, plus "every measure resolves to a
live row"). It is transactional: a violation rolls the whole file back and
names the offending rows.

The measures ride in the same file now ("1 potato, medium = 213 g",
USDA-FDC-sourced with per-row provenance since 0010) and land on the
**template** vocab only. That insert is idempotent: re-running it no-ops on
labels the template already has. How they reach households:

- **New households** get them cloned at onboarding (`ensure_onboarded`),
  which stamps `household.backfilled_at` at creation.
- **Already-onboarded households do NOT retrofit from a template reseed
  alone** — the backfill does that, **exactly once per household** (0011):
  a household whose `backfilled_at` is null gains the template's measures
  the next time its user signs in (the session controller re-runs
  `ensure_onboarded` opportunistically), then is stamped. The old
  zero-live-measures gate is gone: a household that deliberately deleted its
  measures stays deleted (the 7.7 editor ships deletion).
- To **roll a reseeded template's measures out to existing households**,
  run
  [`supabase/rollout_measure_refresh.sql`](../supabase/rollout_measure_refresh.sql)
  (§2b): insert-missing by (ingredient `match_text`, measure `label`), never
  an update or a delete, idempotent. The older path — soft-delete a
  household's measure rows and clear `backfilled_at` so the clone re-runs on
  the next sign-in — only works by wiping the household's user-authored
  measures along with the seeded ones (the clone leg needs **zero live
  measures**; a household that keeps any live row is merely re-stamped
  without cloning), which was acceptable only while dev data was throwaway.
  **Since 2026-09-03 (§2c) it is not**: do not run that leg against a
  household with real measures.

Note migration 0009 also touched the **sync streams** — redeploy
`docker/powersync-cloud.streams.yaml` (step 3 below) so `ingredient_measure`
actually reaches devices (its rules are `SELECT *`, so 0010's `source`,
and 0012's `basis_amount`/`allowed_units`, ride along without a further
stream change).

`supabase db query --linked "<sql>"` also runs read/verify queries. Destructive
statements (`truncate`, `delete`) against cloud are intentionally blocked by the
harness — a human runs those, or use soft-delete (`update … set deleted_at`).

**A hand statement that retires an `ingredient` must re-point its lines
first** — every live `recipe_line_item`, `plan_entry` and
`week_recipe_line_override` naming the row — and since migration `0041` the
database refuses the retire otherwise, naming the count
(*retire refused: 2 live lines still use this ingredient; re-point them
first*). `select ingredient_live_line_uses('<id>')` is the read-only way to
ask first, and `select * from repair_lines_at_retired_ingredients()` re-points
whatever an earlier pass already broke onto the single live row of the same
`match_text`, reporting what it could not resolve.

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
copies it verbatim and re-associates aliases/measures by it), then moves four
things, every one of them monotone — they only ever ADD:

- **(a) `density_g_per_ml`** — **filled** where the household's is null and
  the template's is not. A household's own density is never overwritten.
- **(b) `allowed_units`** — **extended** to the union of the two lists. A unit
  the household admitted is never removed.
- **(c) `piece_basis_amount`** (+ the `piece_source` that rides with it) — the
  same fill-only rule as (a). A weight the household typed keeps its number
  AND its provenance.
- **(d) `macros -> 'fiber'`** — the one key inside `macros` the script writes,
  and only under a **sameness guard**: the household's row must have macros,
  lack a `fiber` key, share the template's `macros_basis`, and still hold
  *exactly* the template's four figures (`macros - 'fiber'` equal on both
  sides). Fibre became the optional fifth macro after the live households were
  seeded, so their rows carry four keys where the reference set has known the
  fifth all along — and filling it is honest only where nobody has edited the
  figures, because an edited row's fibre is not the template's to give. The
  four original figures are never rewritten; a row that already carries its
  own `fiber` keeps it.

`updated_at` is bumped so PowerSync replicates the rows down. It never touches
rows the household created itself (no template counterpart) or soft-deleted,
never writes `source` or `status`, and never moves `default_unit`, measures or
aliases. Re-running it is a no-op. The pgTAP suite
`supabase/tests/ingredient_rollout.sql` mirrors the statement verbatim and
pins all four legs; `make db-lint` fails if the two drift.

Human-run sequence, after the §2 reseed commands above:

```bash
# 1. reseed the template — the §2 block, unchanged (seed_vocab.sql).

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

This generalizes: it is written as "carry the template's density, units, piece
weight and fibre forward", not as a one-off FAO patch, so re-run it after any
future template reseed that fills densities or piece weights, widens unit
admission, or gains a macro key the households lack. A rollout that has to
move a *different* ingredient column is this script with another monotone leg
— keep the fill-only/union-only shape, and where the new value only makes
sense beside numbers the household has not touched, guard it on sameness the
way (d) does, or a household's own edits get clobbered.

**Measures have their own leg, the same shape:**
[`supabase/rollout_measure_refresh.sql`](../supabase/rollout_measure_refresh.sql).
A regenerated `seed_vocab.sql` lands new measures on the template only;
this script joins each non-template household's live `ingredient` rows to
the template's by **`match_text`**, then for every live template measure on
that ingredient **inserts** it where the household's ingredient has no row
with that **`label`** — live or tombstoned. (`match_text` + `label` is the
key `ensure_onboarded` re-associates measures by, and the only identity a
measure has.) It copies exactly what the clone copies — `label`,
`basis_amount`, `sort_order`, `source` — and the fresh row's `updated_at` is
what PowerSync replicates. It never updates or deletes a measure: a live row
keeps its own weight even where the template's now differs, a label the
household soft-deleted stays deleted, the household's own (`manual`,
no-counterpart) measures are untouched, measures of `manual` template
ingredients and of soft-deleted template rows never cross, and a household
ingredient whose `macros_basis` disagrees with the template's is skipped
(`basis_mismatch_skipped` in its preview) rather than handed a number in the
wrong unit. It neither reads nor resets `household.backfilled_at`.
Re-running it is a no-op. It is a separate file on purpose: the `ingredient`
script's contract is fill-only/union-only on that row's own columns, this
one's is insert-missing rows — one file each keeps both contracts legible.

Human-run sequence for the measures leg — after the steps above, or alone
(the two scripts are independent):

```bash
# 5. PREVIEW (read-only): per-household `to_insert`, `already_present_untouched`,
#    `tombstoned_kept_dead`, `basis_mismatch_skipped`, `own_measures_untouched`.
supabase db query --linked "$(sed -n '/^-- with tpl_household as/,/^-- order by h.name, h.id;/p' \
  supabase/rollout_measure_refresh.sql | sed 's/^-- //; s/^--$//')"

# 6. run the rollout (idempotent; reports INSERT 0 <rows added>)
supabase db query --linked -f supabase/rollout_measure_refresh.sql

# 7. re-run the preview: `to_insert` should now read 0 for every household.
```

**The piece weight needs no script at all** (ADR-0015). What one of a thing
weighs is a scalar on the row (`ingredient.piece_basis_amount`, in the row's
basis unit), so it clones with the ingredient the way `density_g_per_ml` does
and reaches a fresh household for free. **For households that already exist,
the migration's own backfill copies each row's curated default measure's
`basis_amount` into the piece weight** — the number the "Counts as" pointer
used to name, written where the model now keeps it, stamped
`borrowed from <label>` in `piece_source`. It is a copy, not a derivation, and
it fills a null only, so a household that has typed its own weight keeps it.
Nothing here needs the measures leg above to have run first, and there is no
follow-up statement to remember. (What needed no script was that column's own
*arrival*. A **later** template reseed that fills a piece weight the household
still lacks travels the ordinary way — leg (c) of the ingredient rollout
above.)

`ingredient.default_measure_id` and `ingredient_default_measure_backfill()`
stay in the database for one release, **unread by every client** from the
piece-weight migration onward. Do not run the old backfill against a
piece-weight stack: it writes a column nothing looks at.

**The template's changed default units do not reach existing households.**
A reseed re-materializes the template's `default_unit` (and with it which rows
are `piece`-default at all), and neither the ingredient rollout nor the
measures script carries a default unit across — `allowed_units` and
`default_unit` on a live household's row are that household's own statement
(ADR-0009 rule 3). So a row the reseed re-defaults on the template keeps its
old default on the household, and a household row left `piece`-default with no
weight is the **stranded default** the flesh-out form flags and refuses to save
until somebody types a number or switches the unit. That is by design: it is
one row at a time, in front of a person, rather than a script re-deciding how a
household buys a thing.

**Interplay between the three scripts: none — each owns one table or column.**
The
`ingredient` script never reads or writes `ingredient_measure`; the measures
script never writes `ingredient`; neither touches `household.backfilled_at`.
Run them in either order. The run-once `backfilled_at` clone inside
`ensure_onboarded` (0011, described in §2) still exists for the pre-0009
heal, but it is **not** a rollout path any more: it needs zero live measures,
so reaching a household through it costs that household its user-authored
measures. Since 2026-09-03 (§2c) that price is not payable — the measures
script above costs nothing, which is why measures now get a script too.

### 2c. The posture: data is durable now (owner ruling, 2026-09-03)

Two rulings landed the same evening, in this order, and the second governs:

1. *"I don't want 10,000 migrations… prefer reset and make sure the db is
   fixed for the future."* — so the doubled template was answered with a
   **full cloud reset** (ledger below), and `0020` carries only the
   future-proofing (template-only unique indexes), no data repair.
2. *"Unless I say so, the data is not ephemeral."* — the big changes are
   believed done, so that reset was meant to be the last free
   one. The owner called **one more** for the v0.7.0 release (2026-09-08, ledger
   below): the app is prod-ready from here and real time goes into stubs and
   recipes, so **that reset is the last one.** From here the
   household data on the cloud and on the phones is real:
   - **No `supabase db reset --linked` without an explicit owner call.**
   - **Migrations preserve rows**: additive columns, backfills, `if not
     exists`; never a drop, a rewrite, or a tombstone sweep of household data.
   - A fix that is tempting to write as a data repair is a design question for
     the owner, not a migration.
   - The §2 rollout notes that say "acceptable because dev data is throwaway"
     (the measures wipe-and-re-clone) are **no longer acceptable**; a reseed
     reaches existing households only through the §2b rollout scripts —
     `rollout_ingredient_refresh.sql` for `ingredient` columns,
     `rollout_measure_refresh.sql` for measures — both monotone by
     construction.

The app's own memory said "data is ephemeral through the roadmap" since
2026-08-26; that era ended here.

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

### 2026-09-12 — two hand statements on the owner's household: a repair, and a measure

- **The Sauerkraut line, repaired.** The round-seven data pass (2026-09-11
  02:04Z) retired the duplicate Sauerkraut row — an import's row carrying
  the placeholder alias — and did not re-point the one live recipe line that
  named it: Sauerkraut, to taste, in *Smashed Edamame Toast*. Every reader
  drops a line at a retired row, so the recipe read as one line short until
  the owner noticed the next day. Run on his say-so: the line moved to the
  seeded Sauerkraut row, and that row admits `to_taste` again — the units
  pass could not see the line's unit as in use because the line pointed at
  the retired row. Readback: the line's ingredient live, `to_taste`
  admitted. No plan entry or week override named the retired row; it was the
  only broken line on cloud. The rule this taught is in §2a above; migration
  `0041` (pending the next deploy) refuses the retire outright and repairs
  any line already left this way.
- **Persian cucumbers, measured.** On the Cucumber row, on his ask: a
  `Persian cucumber` measure at 85 g (Trader Joe's 1 lb bag, five to six per
  bag), first on the row so it is the typical one; the seeded `cucumber` at
  301 g second; a `bag (1 lb)` at 454 g third. Macros stay USDA 168409 per
  100 g. Both reach the seed on the next pull.

### 2026-09-11 (night) — round nine on cloud (v0.13.2): the learned lines leave the vocabulary

- **Owner-ruled data pass, run from here on his say-so (I-D2 A):** eight
  import-learned aliases retired on his household — the seven that were
  whole printed lines or a state ("fresh basil, reserved for garnish",
  "stone-ground mustard or Creole mustard", "smoked chilli harissa paste, or
  ordinary harissa paste", "olive oil or cooking oil of choice", "Olive oil,
  for frying", "vegan cheddar or American cheese", "boiling water") and the
  one that repeated its row's own name ("red wine"). The six learned names
  stay (butter beans, diced fresh tomatoes, chipotle chile flakes, dried
  sage, fresh mushrooms, sweet white sorghum flour). Rows untouched.
- `deploy-supabase` run `34667684551` from `main@e1de1d3`, `reseed_template`
  **ticked**: link ✓ · `db push` (nothing new) ✓ · `functions deploy
  import-recipe` ✓ (the learning loop now refuses a candidate with a comma,
  an "or", a slash or a bracket, so this class does not come back) · sync
  streams ✓ · the seed ✓, regenerated from the household after the pass.
- Read-only readback: template and household both **315** live rows, all
  `complete`, **302** measures, **145** aliases — identical for the first
  time, no generator-dropped leftovers.
- `cloud_verify.sh`: **9 ok · 0 warn · 0 fail**, first pass.
- **No §2b rollout:** one household, the snapshot's own source.

### 2026-09-11 (evening) — round eight on cloud (v0.13.1): the streamed function for real, and the 315-row template

- `deploy-supabase` run `34658424680` from `main@7e94d5a`, `reseed_template`
  **ticked**: link ✓ · `db push` (nothing new — v0.13.1 carries no migration)
  ✓ · `functions deploy import-recipe` ✓ — the model calls now stream and the
  function heartbeats every ten seconds, so a slow reading no longer trips
  the client's silence budget (the round-seven symptom: a 12 s photo then a
  60 s text timeout) · sync streams ✓ · the seed ✓, generated from the
  owner's household after the units pass and his last additions.
- Read-only readback after the reseed: the template holds **315** live rows,
  **315** `complete`, **302** measures and **152** aliases — `counts.json`
  to the row; **19** template rows retired over the seed's life. The owner's
  household reads the same 315 / 302, plus one alias the generator drops on
  purpose: `red wine` on the row named Red Wine, learned by an import before
  the namespace rule closed that door (v0.13.1 makes such a learning a
  no-op). Harmless; it goes when he next tidies the row.
- `cloud_verify.sh`: **9 ok · 0 warn · 0 fail**, first pass.
- **No §2b rollout:** still one household, the snapshot's own source.
- Local-stack note, since it cost an hour: the `ansi-powersync` container
  bind-mounts `docker/powersync.yaml` from whichever checkout ran `make
  db-up` last. Ours had followed a dead landing checkout since 2026-09-05, so
  `week_recipe_line_override` never replicated locally — the app's own copy
  was fine, a second client's never arrived. `docker compose … up -d
  --force-recreate powersync` from the main checkout is the fix; the tell is
  a "Write checkpoint" in the service log with no "Flushed" after it.

### 2026-09-11 (later) — the units pass on the owner's household, and the vocabulary complete

- **Owner-ruled data pass, run from here on his say-so:** every row's
  `allowed_units` lost the label units (`fl oz`, `pint`, `quart`, `litre`),
  the imprecise words on fats, baking staples and counted things, and the
  spoons on `lb`/`kg` rows — `oz` rows keep their spoons by his ruling. 297
  rows, 1,235 units, every statement a strict subset of the row's list and
  none touching its default unit. Checked first against every unit a recipe
  line, plan entry or shopping row states (90 ingredient-and-unit pairs):
  no removal collided. Readback: **313** live rows, **0** still admitting
  `fl oz`.
- The owner had completed the last 18 stubs in the app the same day; the
  read-only export after the pass reads **313** rows, all `complete`, 299
  measures, 149 aliases, 8.3 units per row on average (was 12.3). That export
  is the seed's snapshot from here; the template is promoted on the next
  deploy with `reseed_template` ticked.

### 2026-09-11 — round seven on cloud (v0.13.0): 0040, the streamed function, and the owner's vocabulary as the template

- `deploy-supabase` run `34561587312` from `main@50d9213`, `reseed_template`
  **ticked**: link ✓ · `db push` applied **`0040`** (`week_recipe_line_override`
  — one variant per week and recipe, RLS trio, indexes) ✓ · `functions deploy
  import-recipe` ✓ — the function now answers as an event stream (one event
  per stage, the payload last), and the app it ships with reads nothing
  else, so the two went out together per §4's order · sync streams ✓ (the
  new table rides the same button) · the seed ✓ — `seed_vocab.sql`, generated
  from the owner's live household, was applied over the old template.
- Read-only readback after the deploy (the same export the seed is built
  from): the template holds **315** live rows, **297** `complete` and **18**
  `stub`, **296** measures and **148** aliases — the owner's household, row
  for row. The four rows the old template carried that the snapshot did not
  (eight deleted stubs, eight renamed keys) were retired by the reseed's own
  retire step, so the template holds no name the household does not.
- `cloud_verify.sh`: first pass **8 ok · 0 warn · 1 fail** — the PowerSync
  instance was still restarting after the sync-config deploy; second pass a
  minute later **9 ok · 0 warn · 0 fail**.
- **No §2b rollout:** the only household is the owner's, and it is the
  snapshot's source. A second household would clone the new template on
  onboarding; an existing one would need the rollout, which is fill-only —
  a value the owner corrected does not overwrite a wrong one already held.

### 2026-09-09 — fibre on cloud (v0.12.0): a reseed, and a rollout that had nothing to do

- `deploy-supabase` run `34426524223` from `main@9708f50`, `reseed_template`
  **ticked**: link ✓ · `db push` (nothing new — v0.12.0 carries no migration) ✓
  · `functions deploy import-recipe` ✓ · sync streams ✓ · the five seeds ✓.
  An earlier run the same evening (`34409373514`, `main@b2c03cb`, no reseed)
  deployed the import function's timeout ladder and its 504 copy.
- Read-only readback after the reseed: the template holds **319** live rows,
  **271** of them with a `fiber` key — and the household **the same 271 of
  319**. The seed had carried fibre inside `macros` since the USDA reference
  was generated; the household's clone took it along, and only the app never
  read the key until v0.12.0. The twelve rows without it are honest gaps in
  the reference (vinegars, canned tomatoes, cooked rice, a few curated rows).
- The §2b previews, both scripts: **0 on every leg** for the household
  (`leg_d_fibre_fills` 0 · `own_macros_kept_as_is` 0 · 2 household-only rows
  and 1 deleted row left alone · measures `to_insert` 0 of 272). Neither
  rollout was run — there was nothing to carry, and an idempotent no-op is
  not worth a write on a live household. Leg (d) (fibre under the sameness
  guard) exists for the next reseed that changes a figure.
- `cloud_verify.sh`: **9 ok · 0 warn · 0 fail**.
- Shipped as `v0.12.0` (release run `34423455276`) before this cloud pass —
  allowed by §4's order because the release carries no schema change.

### 2026-09-08 (evening) — the piece weight on cloud (v0.8.0): 0039 and a reseed

- `deploy-supabase` run `34274932829` from `main@f52f8dc`, `reseed_template`
  **ticked**: link ✓ · `db push` applied **`0039`** (piece weight — the two
  columns, the 5-arg `default_allowed_units()`, the fill-only backfill from
  each row's curated default measure, the `piece` union and its trigger,
  `ensure_onboarded` carrying the columns) ✓ · `functions deploy
  import-recipe` ✓ · sync streams ✓ · the five seeds ✓ (`seed_curation` R3
  now asserts every piece-default template row is weighed; no rename this
  round, so §5.3 did not apply).
- Read-only readback after the deploy: the template holds **76**
  piece-default rows, all weighed; the household holds **77**, weighed on all
  but **Mint** and **Red Cabbage** — the two rows whose curated default was
  "ask me each time" when the vocabulary was cloned. The reseed changed
  Mint's template default to `g` (not carried to households by design) and
  gave Red Cabbage the `head, medium` weight.
- `cloud_verify.sh`: **9 ok · 0 warn · 0 fail**.
- Shipped as `v0.8.0` (release run `34275484036`: guard ✓ · android ✓, APK
  93 MB + AAB 80 MB on the Release · ios compile proof ✓ · `play-internal`
  skipped by design) after the cloud legs, per §4's order.
- **The §2b ingredient rollout, owner-run the same evening:** the preview
  read 1 unit extension before and **0 on every leg** after; leg (c) carried
  Red Cabbage's `head, medium` weight (839 g) down from the template. The
  household now holds 77 piece-default rows, weighed on all but **Mint** —
  the template's Mint moved to a `g` default, which a rollout never carries,
  so that row stays a stranded piece default the form asks about on its next
  open. The measures leg was not needed — `seed_measures.sql` did not change.
  The preview block does not yet count leg (c) separately; the readback query
  above is how it was checked.

### 2026-09-08 — round six on cloud (v0.7.0): the database rebuilt from scratch

- **Why a reset (owner call, §2c):** *"when we release / redeploy, I want to
  start remote db from scratch… the app is basically prod ready, and I'm going
  to start actually investing time fixing stubs, uploading recipes."* So the
  0035/0036/0037 widening backfills, the §2b rollouts and plan 0039's operator
  statement all became moot: a fresh database carries the current rule and
  the current seed, and every household created from here clones them.
- `supabase db reset --linked --yes` from `main@df269df`: every migration
  through **`0037`** (all-to-all admission, `mg` retired, free-text items
  week-scoped, the mass ladder), all five seeds in `config.toml` order,
  `seed_curation` green on the first run (no rename in this round, so the
  §5.3 trap did not apply).
- `deploy-supabase` run `34237512787` from `main@df269df`, `reseed_template`
  NOT ticked (the reset seeded): link ✓ · `db push` no-op ✓ · `functions
  deploy import-recipe` ✓ (the shared normalizer no longer knows `mg`) ·
  sync streams ✓.
- `cloud_verify.sh`: **9 ok · 0 warn · 0 fail** (sign-up was already off).
- Shipped as `v0.7.0` (release run `34237807444`: guard ✓ · android ✓, APK
  93 MB + AAB 80 MB on the Release · ios compile proof ✓ · `play-internal`
  skipped by design) after the cloud legs, per §4's order.
- **What the reset cost, and the legs still owed (owner):** every onboarded
  household and auth user. Re-onboard from the phone (§3c: sign-up on, sign
  in, sign-up off), then **re-set `IMPORT_ALLOWED_HOUSEHOLDS`** to the new
  household id — the function secrets survive a reset and still name the dead
  household. Template readback (319 live ingredients · 133 default measures
  expected) is the owner's `--linked` leg.
- **Same day, two data-only follow-ups, no app release:** the audit's
  cinnamon-stick density cleared (reseed run `34239697371`), then the
  provenance card on the new household printed only the FDC id — the seed
  never wrote `source_label` (0027's fill was a migration, empty table on a
  reset) and `ensure_onboarded()` never cloned it. Fixed by the seed writing
  the label with the stamp and **`0038`** (the clone carries label + score;
  nameless `usda_fdc:` rows named from the reference, all households):
  `deploy-supabase` run `34240823083`, `reseed_template` ticked, all five
  legs ✓. Run `34240557813` before it deployed the OLD `main` by mistake (a
  fast-forward run on the wrong branch) and changed nothing.
  `cloud_verify.sh` after each: **9 ok · 0 warn · 0 fail**.

### 2026-09-05 — round five on cloud (plans 0034–0040): 0032–0034, and a reseed that had to be repaired

- `deploy-supabase` run `33960660473` from `main@426eae6`, `reseed_template`
  ticked: **link, `db push`, the edge function and the PowerSync streams all
  succeeded**; the template reseed **failed** on its own guard —
  `seed_curation R3: 136 of 133 curated default measures landed`.
- **Cause, and it is a rule now (release.md §5.3):** plan 0039 renamed six
  vocabulary rows. The seed inserts by `match_text`, so against a long-lived
  template a rename is an INSERT: the six new names arrived and five old rows
  stayed (`00 Flour`, `French Green Lentils`, `Coconut Milk`, `Hot Chili`,
  `Baked Beans`; `Ground Clove` was already absent). Three of those five
  carried a `default_measure_id` — 133 + 3 = 136, which is exactly what the
  guard reported. `seed_curation` is transactional and rolled back cleanly;
  `seed.sql` had already committed its inserts.
- **Repair, owner-approved, scoped to the template household
  (`…0000000000aa`, member-less, zero recipe lines referencing the rows):**
  their measures tombstoned, then the five rows tombstoned with
  `default_measure_id` nulled. A sixth followed — `Doppio Zero Flour`, which
  the failed run had inserted and which the owner then renamed again to
  `Tipo 00 Flour` (the bag's name; `doppio zero flour` rides as an alias, and
  the USDA link was repointed from the old key to `tipo flour`).
- `deploy-supabase` run `33961320740` from `main@2348fa0`, `reseed_template`
  ticked: **green**. Template read back on cloud: **319 live ingredients, 133
  default measures, 283 with macros** — the three numbers the seed and
  `cloud_verify` both expect.
- `cloud_verify.sh`: **9 ok · 0 warn · 0 fail**, before and after.
- Shipped as `v0.6.0` (release run `33961427290`) after the cloud push, per the
  order §4 insists on: schema first, then the app that writes it.
- **Still owed:** plan 0039's operator statement (Parts 1 and 2) has NOT been
  run against the real household — the renames, splits and new aliases are on
  the TEMPLATE only. Existing households reach the new vocabulary through §2b,
  by hand, and that is the owner's to run.

### 2026-09-04 — the backlog cleared in one run (plans 0027, 0029, 0030): 0026–0031

- `deploy-supabase` run `33903467804` from `main@8bc7419`, `reseed_template`
  NOT ticked (nothing in this wave changes the seeded vocabulary; **0031**
  rewrites stored keys in place): link ✓ · `db push` ✓ (**0026**
  `portion_factor` · **0027** `usda_source_label` — `source_label` /
  `source_score`, `probe_usda` with a `limit` · **0028**
  `allowed_units_jsonb_repair` · **0029** `usda_search_ranking` — the prefill
  trigger and its function dropped, BM25 over `usda_search_token` / `_term` /
  `_doc` / `_stats`, the index built by the migration's own
  `usda_rebuild_search_index()` · **0030** `usda_search_hardening` — RLS on
  the four index tables, the unread trigram index dropped · **0031**
  `tinned_is_canned` — `match_text` rewritten where it carried `tinned`,
  duplicates tombstoned) · `functions deploy import-recipe` ✓ (the `tinned`
  fold and the fused-amount token in the normalizer) · sync streams ✓
  (`household_member` now lists `portion_factor`).
- `cloud_verify`: **9 ok · 0 warn · 0 fail** — JWKS ES256, auth, REST, RLS
  on all **19** tables (14 household-scoped + `usda_food` + the four index
  tables), `usda_search_stats` populated, 14 synced tables with equal column
  lists, template vocab 272 of 308 with macros.
- **Readback (owner leg — agents are gated from `--linked` on purpose), run
  by the owner 2026-09-04, every value as expected:** `select max(version) from supabase_migrations.schema_migrations;`
  → **`0031`** · `select count(*) from ingredient where jsonb_typeof(allowed_units)
  = 'string';` → **`0`** (0028) · `select count(*) from ingredient_alias where
  match_text ~ '\mtinned\M' and deleted_at is null;` → `0` (0031) ·
  `select n_docs from usda_search_stats;` → **`8204`** (0029) · `select
  column_name from information_schema.columns where table_name =
  'household_member' and column_name = 'portion_factor';` → **`portion_factor`** (0026).
- Tagged **`v0.5.0`** after this push (release.md §5 order) — release run
  `33903706382`.

### 2026-09-03 (day) — field test round three (plan 0025): 0024 pint + quart, 0025 optional lines

- `deploy-supabase` run `33757959262` from `main@35d4ed5`, `reseed_template`
  NOT ticked (the seed diff in this wave is the R1 assertion list only, and
  **0024** carries its own additive UNION backfill of `allowed_units`, so no
  reseed and no rollout leg): link ✓ · `db push` ✓ (**0024** `quart_pint` —
  `unit_family()`, `default_allowed_units()`, `density_unlocked_units()`
  re-created with `pt`/`qt`, backfill counted; **0025** `optional_line` —
  `recipe_line_item.optional boolean not null default false`) · `functions
  deploy import-recipe` ✓ (unchanged code) · sync streams ✓ (`select *`, so
  the new column rides).
- `cloud_verify`: **9 ok · 0 warn · 0 fail** (JWKS ES256, auth, REST, RLS
  surfaces, PowerSync reachable, 14 tables with equal column lists).
- **Readback (owner leg — agents are gated from `--linked` on purpose):**
  `select max(version) from supabase_migrations.schema_migrations;` → expect
  `0025` · `select count(*) from ingredient where allowed_units ? 'qt';` and
  `… ? 'pt'` → expect every `l`-admitting row for `qt`, every `cup`-admitting
  row for `pt` (Vegetable Broth among them) · `select column_default from
  information_schema.columns where table_name = 'recipe_line_item' and
  column_name = 'optional';` → `false`. **Run by the owner 13:0x UTC:**
  `qt` **168** = `l` **168**, `pt` **514** = `cup` **514** (the D2b rule
  holds row-for-row across every household), `optional` default **false**
  (0025 applied; the max-version query was not run separately — the column
  is the proof).
- Tagged **`v0.4.0`** after this push (release.md §5 order).

### 2026-09-03 (night) — field test round two (plan 0024): 0021–0023, the default-measure curation

- `deploy-supabase` run `33715780637` from `main@12ba7ae`, `reseed_template`
  ticked: link ✓ · `db push` ✓ (**0021** admission mirror, **0022**
  singularize invariants — the parallel debt pass — and **0023**
  `default_measure`) · `functions deploy import-recipe` ✓ · sync streams ✓ ·
  **reseed ✓** (the borrowed `pepper, medium`, the 132 curated defaults).
- Human legs, run right after (durable data — both row-preserving):
  `rollout_measure_refresh.sql` (insert-missing; nothing to report) and
  `select ingredient_default_measure_backfill()` → **1** row filled on the
  household (the pepper whose medium had only just arrived).
- **Readback:** `schema_migrations` max `0023` · template 132 defaults, 0
  admitting `piece` · household `8ac5c4d0-…f07d` 132 defaults over 271
  measures · sample defaults: cucumber, ginger → `piece, 1 inch`, onion →
  `onion, medium`, red bell pepper → `pepper, medium`, broccoli → none.
  `cloud_verify`: **9 ok · 0 warn · 0 fail**.
- Tagged **`v0.3.0`** after this push (release.md §5 order).

### 2026-09-03 (later) — full cloud reset after the doubled template; reseed becomes a button

- **Why a reset:** a by-hand `seed.sql` against the already-seeded project
  doubled the template (616 rows / 308 names, aliases ×3, measures 273/270,
  ginger's measures twice). Owner ruling the same night — §2c — *reset,
  never patch*: `supabase db reset --linked --yes` from `main@000a7cb`
  (every migration through **`0020`**, all five seeds in `config.toml`
  order), then `deploy-supabase` run `33705387598` (link ✓ · `db push` no-op
  ✓ · `functions deploy import-recipe` ✓ · **sync streams ✓** · reseed
  skipped, as intended after a reset).
- **Readback:** template 308 live ingredients · 0 tombstoned · 112 aliases ·
  270 measures · **0 admit `piece`** · 272 with macros · `jalapeno` once ·
  ginger = `piece, 1 inch 12 g` + `slice 2.2 g` · `usda_food` 8,204 ·
  `schema_migrations` max `0020`. `cloud_verify`: 8 ok · 1 warn (public
  sign-up open for the re-onboarding) → **9 ok · 0 warn · 0 fail** once Simon
  turned sign-up off again (§3c) at 02:05.
- **What the reset cost:** every onboarded household and auth user
  (`households: 0`). Simon re-onboarded at 01:58 UTC → household
  `8ac5c4d0-…f07d` (1 member); **`IMPORT_ALLOWED_HOUSEHOLDS` re-set to it**
  at 02:00 (the function secrets survive a reset, so the allowlist still
  named the dead household — remember this leg after any future reset,
  which under §2c is now an owner call). The second phone joins that
  household through the normal join flow.
- **Fixed for the future:** `0020` = template-only unique indexes on
  `ingredient(match_text)` and `ingredient_alias(ingredient_id, match_text)`
  (live rows), the generated `seed.sql` upserts on them, `seed_usda.sql` is
  skipped by the button when the reference table is populated, and
  `deploy-supabase` carries the `reseed_template` input (first green run
  with it: `33704952842`). `powersync/cli.yaml` lets the streams leg run
  (runs `33704042001` onward).

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
