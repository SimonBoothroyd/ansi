# AGENTS.md — backend (Supabase)

Overrides/extends the root `AGENTS.md` for `supabase/`.

## What lives here

- `migrations/` — Postgres schema, applied by the Supabase CLI in order.
- `functions/` — Deno edge functions. The **import + match engine** lives here;
  it is the ONLY place fuzzy matching happens (ADR-0004). Matching never runs
  on-device. Two doors share it: `import-recipe/` (a link or photographed
  pages → a recipe) and `import-receipt/` (photographed till receipt → what was
  paid, line by line). What both need — the household gate, the photo cost caps,
  the SSE frame shape, the failure wordings, the adapters, the cascade — lives in
  `_shared/`, so a change to "how big may a photo be" cannot answer differently
  at the two doors. Both are deployed BY NAME in `deploy-supabase.yml`.
- `seed/` — two seeds with different owners. The **household vocabulary** is
  an export of the owner's live household (`seed/snapshot.jsonl`) turned into
  one `../seed_vocab.sql` by `seed/scripts/gen_seed.ts` — the direction is
  **cloud → seed**, and the curated rows are the input, not a first draft
  something re-derives. The **USDA FoodData Central reference** (`usda_food`,
  server-side only) is generated separately into `../seed_usda.sql`. See
  `seed/README.md`.

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
- **A receipt teaches the vocabulary nothing** (plan 0049, owner). The recipe
  door writes a correction back as an alias; the receipt door writes nothing at
  all and matches afresh every time, because a receipt's words are one store's
  abbreviations. It is held by `import-receipt/no_alias.test.ts`, not by this
  line: a SQL spy asserts every statement that function issues is a `SELECT`.
  What carries over between shops is the PACK, on the ingredient row.
- **A receipt's photos are joined by POSITION, never by item identity.** The
  seam is the longest run of identical consecutive lines shared by the end of
  one photo and the start of the next (`_shared/receipt_join.ts`). A receipt
  honestly prints the same item twice when two were bought, and a joiner that
  de-duplicated by name would delete one of them. `import-and-matching.md` §12.
- **Never commit a real receipt.** This repo is public and a receipt carries a
  card's last four and a loyalty number. `import-receipt/testdata/` is synthetic
  and a test asserts it; the owner's own go in the gitignored
  `import-receipt/__fixtures__/local/`.
- **The model calls STREAM, and the function says so out loud.** `streamJson`
  (`functions/_shared/adapters/http.ts`) is what production extraction goes
  through: `stream: true`, an idle timer instead of a per-attempt wall clock, no
  retry once a delta has arrived, and no RETRY started into a budget too small
  to finish in. While one runs, `import-recipe` emits a `heartbeat` SSE frame,
  so the longest silence the app can see is the heartbeat interval rather than a
  whole model deadline. That is the ONLY reason the model budgets
  (`SANITIZE_DEADLINE_MS`, `TRANSCRIBE_DEADLINE_MS` in `adapters/claude.ts`) may
  exceed the platform's 150 s idle cut-off — reintroduce a buffered call, or
  drop the heartbeats, and they have to shrink back with it. Both halves of the
  ladder are arithmetic tests (`_shared/timeouts.test.ts`,
  `app/test/features/import/edge_import_failures_test.dart`), and the budgets
  are sized from `evals/runs/`, never from the platform's number.
- Migrations are immutable once merged; make a new migration to change schema.
- **Never `npx supabase`, and never take the local stack down mid-run.** The
  CLI is the brew-pinned 2.115.0 and the Makefile shells it by path
  (`$(SUPABASE)`); `npx` resolves a newer CLI that starts pulling a postgres
  image this project does not use. The local stack is **shared by every
  worktree on the machine**: one lane's `db reset` re-applies *its* migration
  set under every other lane, and one lane's `supabase stop` ends every other
  lane's pgTAP run. Reset only from a checkout whose migrations are a superset
  of main's, and say so in the sitrep.

## Driving import locally without a key

The pipeline's one paid, non-deterministic stage is the LLM. Everything after it
— normalize, the match cascade, payload assembly, the HTTP edges — is
deterministic, and that is the half a matching change has to be exercised
against a real Postgres. A saved eval run holds what the model said, verbatim,
for a case in the extraction corpus (`evals/runs/`, local-only), so
`import-recipe` can replay one instead of calling out — the test suite carries
its own small one, `import-recipe/testdata/replay_case.json`:

```
supabase start                                   # the local stack

# serve the function against the local database, keyless
SUPABASE_DB_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
IMPORT_EXTRACT_FIXTURE=$PWD/supabase/functions/import-recipe/testdata/replay_case.json \
  deno run --allow-all --config supabase/functions/deno.json \
  supabase/functions/import-recipe/index.ts

# then POST {"images":["<any base64>"]} with a bearer token carrying a
# household_id claim for a household the local DB has seeded — the replay
# adapter never looks at the bytes, so the PHOTO door (two model calls) runs
# end to end
```

`IMPORT_EXTRACT_FIXTURE` names a run-case file (an `evals/runs/**` one, or the
test fixture); `replay.ts` decodes
its `raw` with the same Claude decoder the live call uses. It is a LOCAL switch
and three things keep it that way, none of them a warning: the var appears in no
deploy script and no `supabase secrets` row (the deployed function's secrets are
`ANTHROPIC_API_KEY` and `IMPORT_ALLOWED_HOUSEHOLDS`, set by hand —
[`cloud-setup`](../docs/cloud-setup.md) §3b); the loader **refuses** when
`ANTHROPIC_API_KEY` is set, so the environment that can really extract never
serves a canned recipe; and the saved responses live under `evals/`, which is not
part of the deployed function. `import-recipe/replay.test.ts` holds all three.

`supabase functions serve` works the same way, with one wrinkle: it mounts only
`supabase/functions` into the runtime container, so the fixture has to be copied
somewhere under that directory first and the env var point at the container path.
Serving the module directly, as above, is the shorter road and is the same
`serveImport()` entry point the deploy runs.

`import-receipt` replays the same way, under its own variable
(`RECEIPT_EXTRACT_FIXTURE`) and with the same two locks, and its fixtures are
committed beside it (`import-receipt/testdata/`, synthetic) rather than under
`evals/`. It hands the saved photos back UNJOINED, so a replay run exercises the
real seam-finder instead of skipping it. See
[`import-receipt/README.md`](functions/import-receipt/README.md).

## Commands

```
supabase start            # local stack
supabase db reset         # re-run migrations + seed
supabase db lint
supabase test db          # pgTAP tests — seventeen suites in tests/ (RLS + the
                          #   usda server-only boundary, onboarding, the token
                          #   hook, unit admission, nested recipes, measures,
                          #   BOTH operator rollouts, portion factor, template
                          #   seed, shopping/week, the household's first day of
                          #   the week, USDA search, the retire guard, and more)
cd functions && deno task test  # edge-function tests (the task carries the
                          #   --allow-read the shared-vector and real-vocab
                          #   suites need; bare `deno test` fails on them)
```
