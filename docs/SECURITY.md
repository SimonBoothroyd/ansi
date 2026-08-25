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

## Auth & data isolation

- Google OAuth via Supabase Auth (ADR-0002).
- Everything is scoped to `household_id`. **Row-Level Security policies** on every
  table are what enforce that a household only ever reads/writes its own rows —
  the client is untrusted. PowerSync sync rules must mirror those boundaries so
  the device only syncs its household's data.
- Deletes are soft-delete tombstones (spec §3), not hard deletes.

## Checklist when adding a table

- [ ] `household_id` column + FK
- [ ] RLS enabled with select/insert/update policies scoped to the caller's household
- [ ] **Explicit GRANTs** matching those policies — RLS filters rows, but a role
      still needs the base grant to reach the table (local default privileges
      only auto-grant `Dxt`). Grant `authenticated` what its policies allow (no
      `delete` — deletes are soft), `grant all` to `service_role`, and grant
      server-only tables to no client role. See `migrations/0002_ingredients.sql`.
- [ ] Added to the PowerSync publication and sync rules (`docker/powersync.yaml`)
- [ ] No secret or PII in a synced column that shouldn't leave the server
