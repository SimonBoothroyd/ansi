# Security & secrets

Hobby scale, but the basics are non-negotiable.

## Secrets

- **Never commit secrets.** `.env.local` is gitignored; `.env.local.template`
  documents the shape. Client config reaches the app via `--dart-define` (see
  `app/lib/core/config/env.dart` and the `Makefile`).
- **The extraction model API key is server-side only.** It's a Supabase edge
  function secret and must never ship in the Flutter bundle. (ADR-0004.)
- The Supabase **anon key** is public by design; it is *not* a secret. Real
  protection comes from Row-Level Security, below.
- **A hosted web build publishes every `--dart-define` it was compiled with.**
  They are baked into `main.dart.js`, which anyone can read: the anon key
  (public anyway) and both endpoints. The endpoints are kept as repo secrets so
  a public repo's logs never print them, and hosting hands them out, so what
  keeps it safe is the one setting that must not be relaxed — **public sign-up
  stays OFF**, or a stranger with the endpoints can provision a household.
  Trade and owed steps: [`release.md` §6.2](./release.md#62-the-trade-hosting-publishes-the-endpoints).

## Auth & data isolation

- **Sign-in** (step 7): Google OAuth via Supabase Auth (ADR-0002) is the real
  path; a dev email/password sign-in also ships for local development. The
  router gates the whole app behind a session (`/sign-in`).
- **Onboarding** (`ensure_onboarded`, migration 0007, hardened in 0008): a
  `SECURITY DEFINER` RPC the app calls right after sign-in. It joins the user
  to a household with room (v1 = two people) or creates one, cloning the
  starter vocab from the **template household** (`household.is_template`, the
  seeded "Home") — never from another user's household, and excluding
  `source='manual'` ingredients and `'import_correction'` aliases (private
  typed-in data never leaves its household); no template → empty vocab, not an
  error. Template households are never joinable and stay member-less, so RLS
  and the sync rules (both membership-resolved) never expose them. Concurrent
  onboards serialise on an advisory lock (no seat-race double-joins), and
  clients can't flip `is_template` (column-level UPDATE grant). Household /
  member inserts have **no client policy** — they happen only here, privileged.
- **The `household_id` JWT claim**: an access-token hook (`add_household_claim`,
  migration 0007, registered in `config.toml`) injects the caller's
  `household_id` into every issued token. PowerSync sync rules
  (`docker/powersync.yaml` locally; its cloud twin
  `docker/powersync-cloud.streams.yaml`, kept in lockstep by
  `scripts/check_stream_drift.sh`) scope every bucket by that claim, so a
  device only ever syncs its own household's data. **The hook is load-bearing** — with no
  claim, nothing syncs. Note: Supabase local issues **ES256** tokens, verified
  by PowerSync via the Supabase **JWKS** endpoint (not a shared secret); and a
  `config.toml` hook change needs a full `supabase stop && supabase start`.
- Everything is scoped to `household_id`. **Row-Level Security policies** on every
  table enforce that a household only ever reads/writes its own rows — the
  client is untrusted. The sync rules mirror those boundaries.
- Deletes are soft-delete tombstones (spec §3), not hard deletes — the PowerSync
  connector maps even a stray CRUD delete to a `deleted_at` update.
- **Standing up a real cloud project** (Supabase Cloud + PowerSync Cloud + Google
  OAuth), and the gotchas that bite — see [`cloud-setup.md`](./cloud-setup.md).

## Checklist when adding a table

- [ ] `household_id` column + FK
- [ ] RLS enabled with select/insert/update policies scoped to the caller's household
- [ ] **Explicit GRANTs** matching those policies — RLS filters rows, but a role
      still needs the base grant to reach the table (local default privileges
      only auto-grant `Dxt`). Grant `authenticated` what its policies allow (no
      `delete` — deletes are soft), `grant all` to `service_role`, and grant
      server-only tables to no client role. See `migrations/0002_ingredients.sql`.
- [ ] Added to the PowerSync publication and **both** sync-rule files
      (`docker/powersync.yaml` + `docker/powersync-cloud.streams.yaml` — the
      drift check fails CI if only one is updated). A server-only *column* must
      be excluded from the rule's SELECT (an explicit column list, as
      `household_member` does for `auth_user_id`) — what a rule selects is
      exactly what ships to devices; omitting the column from the client schema
      alone does not keep it off the wire
- [ ] No secret or PII in a synced column that shouldn't leave the server
