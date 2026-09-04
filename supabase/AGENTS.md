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
  against at import (ADR-0005). Only resolved `ingredient` rows sync down. It is
  granted to no client role, so the one thing that reads it on a client's behalf
  — `probe_usda`, the search door — is `security definer` by necessity. It
  WRITES NOTHING: it returns a ranked short-list and a person applies the pick
  through the app's ordinary write path. The four `usda_search_*` tables are a
  re-shaping of the same reference set and live under the same rule: RLS on, no
  grant to any client role, reached only through that door.
- **The extraction LLM never sees the vocabulary and never matches** — it only
  emits raw structured lines. Matching is deterministic and testable (see
  `evals/`). Design: `docs/product-specs/import-and-matching.md`.
- Migrations are immutable once merged; make a new migration to change schema.

## Commands

```
supabase start            # local stack
supabase db reset         # re-run migrations + seed
supabase db lint
supabase test db          # pgTAP tests — eleven suites in tests/ (RLS + the
                          #   usda server-only boundary, onboarding, the token
                          #   hook, unit admission, nested recipes, measures +
                          #   their rollout, portion factor, template seed,
                          #   shopping/week, USDA search)
cd functions && deno task test  # edge-function tests (the task carries the
                          #   --allow-read the shared-vector and real-vocab
                          #   suites need; bare `deno test` fails on them)
```
