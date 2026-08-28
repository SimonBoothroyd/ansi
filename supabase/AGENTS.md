# AGENTS.md — backend (Supabase)

Overrides/extends the root `AGENTS.md` for `supabase/`.

## What lives here

- `migrations/` — Postgres schema, applied by the Supabase CLI in order.
- `functions/` — Deno edge functions. The **import + match engine** lives here;
  it is the ONLY place fuzzy matching happens (ADR-0004). Matching never runs
  on-device.
- `seed/` — USDA FoodData Central seed (server-side reference `usda_food`, +
  the initial household vocabulary).

## Rules

- **Every table is household-scoped and RLS-protected.** The client is untrusted.
  See `docs/SECURITY.md` — new tables need RLS policies AND matching PowerSync
  sync rules (`docker/powersync.yaml`) before they're usable.
- **RLS filters; GRANTs gate — you need both.** RLS only narrows rows a role can
  already reach. Migrations here run as `postgres`, and local default privileges
  auto-grant `authenticated`/`anon` only `Dxt` (not select/insert/update) — so a
  new table is *inaccessible to the app* until you `grant` explicitly. Grant
  `authenticated` exactly what its policies allow (omit `delete` — deletes are
  soft), `grant all … to service_role`, and grant server-only tables (`usda_food`)
  to no client role at all. See `migrations/0002_ingredients.sql` for the pattern.
- **`usda_food` is server-side only** — never synced to the device, never matched
  against at import (ADR-0005). Only resolved `ingredient` rows sync down.
- **The extraction LLM never sees the vocabulary and never matches** — it only
  emits raw structured lines. Matching is deterministic and testable (see
  `evals/`). Design: `docs/product-specs/import-and-matching.md`.
- Migrations are immutable once merged; make a new migration to change schema.

## Commands

```
supabase start            # local stack
supabase db reset         # re-run migrations + seed
supabase db lint
supabase test db          # pgTAP tests (tests/ — RLS, onboarding, token hook)
cd functions && deno test # edge-function tests
```
