# ADR-0006: Sync auth, the household JWT claim, and onboarding

- **Status:** Accepted
- **Date:** 2026-08-27
- **Context:** roadmap step 7 (sync layer)

## Context

Steps 1–6 ran offline-only. Step 7 turns on PowerSync sync between a household's
devices. That needs three things decided: how a device authenticates to the
sync service, how the sync service knows which household a device may see, and
how a freshly signed-in user acquires a household in the first place.

## Decision

- **A `household_id` JWT claim, injected by a Supabase access-token hook.**
  `add_household_claim` (migration 0007, registered in `supabase/config.toml`)
  resolves the caller's household from `household_member` and writes it into
  every issued token. PowerSync sync rules (`docker/powersync.yaml`) parameter
  each bucket by `request.jwt() ->> 'household_id'`. This mirrors the RLS
  boundaries (a device syncs exactly what its household's RLS would allow) and
  needs no per-request database lookup in the sync rules.

- **Onboarding is a `SECURITY DEFINER` RPC (`ensure_onboarded`), not a trigger.**
  The app calls it right after sign-in, before `.connect()`. It is idempotent
  and, for v1's two-person household, joins an existing household with room or
  creates a fresh one (cloning the starter vocab). Household/member inserts have
  no client RLS policy — they happen only inside this privileged function. An
  RPC (over a trigger on `auth.users`) keeps onboarding testable and lets the
  client await a resolved `household_id` before connecting.

- **Token verification is asymmetric (ES256) via JWKS.** Supabase issues ES256
  user tokens; PowerSync verifies them against Supabase's JWKS endpoint rather
  than sharing an HS256 secret. Works identically local and cloud.

- **Dev email/password now; Google OAuth wired but verified at cloud cutover.**
  Local Supabase email/password exercises the whole sync/household/queue path
  today; the Google button ships (ADR-0002's real auth) and is verified against
  a real Google project when the cloud instance exists.

- **The client never hard-deletes.** Deletes are soft tombstones (spec §3); the
  connector maps even a stray PowerSync CRUD delete to a `deleted_at` update, so
  it never issues a DELETE the RLS grants would reject.

## Consequences

- The access-token hook is load-bearing: no claim ⇒ nothing syncs. A
  `config.toml` hook change requires a full `supabase stop && supabase start`
  (not just `db reset`) to reach GoTrue.
- v1 has no invite flow and no per-household vocab *template* — a brand-new
  cloud household clones vocab from an existing one, which a truly empty cloud
  database won't have. Documented as a cloud-cutover task (spec §8 open
  question: household membership/invites).
- Local self-hosted PowerSync connects to Postgres with discrete connection
  fields (so `sslmode: disable` is honoured) and stores buckets in the same
  Postgres. See `docs/exec-plans/completed/0008-sync-layer.md` for the wiring.
