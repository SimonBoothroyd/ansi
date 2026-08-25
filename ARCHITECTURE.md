# Architecture

> The top-level map of the system for humans and agents. Deeper detail lives in `docs/` (see `docs/README.md`); the *why* behind choices is in `docs/decisions/`.

This is the "why", cross-referenced to decision records (`docs/decisions/`). The
"what to build next" lives in `docs/exec-plans/roadmap.md`. Product behaviour lives
in `docs/product-specs/`.

## Stack (decided)

| Layer            | Choice                                   | ADR |
|------------------|------------------------------------------|-----|
| Client framework | Flutter 3.44+                            | 0002 |
| UI components    | Forui (shadcn-style, MIT)                | 0002 |
| State / DI       | Riverpod 3 (codegen) + go_router         | 0003 |
| Models           | Freezed + json_serializable              | 0003 |
| Backend          | Supabase (Postgres + Auth + Storage)     | 0002 |
| Offline sync     | PowerSync (local SQLite + upload queue)  | 0002 |
| Auth             | Google OAuth via Supabase Auth           | 0002 |
| Import extraction| Flash-tier multimodal LLM, server-side   | 0004 |

## The shape of the app

Feature-first + MVVM, which is the layout Flutter's own architecture guide
recommends. Each feature is a vertical slice:

```
lib/features/<feature>/
  domain/         # entities + repository interfaces — PURE DART, no Flutter
  data/           # repository implementations, DTOs, PowerSync queries
  presentation/   # Views (widgets) + ViewModels (Riverpod notifiers)
```

`lib/core/` holds cross-cutting code that never depends on a feature: the unit
system, config, router, theme, the PowerSync database, and the `Result` type.
`lib/shared/` holds reusable widgets.

**Dependency direction:** `presentation → domain ← data`. Views read state from
ViewModels; ViewModels call repository *interfaces* in `domain/`; `data/`
implements them. This is what makes ViewModels and domain logic testable by
overriding a repository provider with a fake — no widget tree, no network.

**Domain purity is enforced.** `core/units` and every `domain/` folder must not
import `package:flutter`. CI greps for violations (`.github/workflows/app.yml`).
It keeps the most important logic (unit conversion, batch clustering, list
aggregation) runnable as plain Dart tests.

## The sync model

One shared household dataset; both members full read/write; everything scoped to
`household_id`. PowerSync owns the write queue: the app reads and writes a local
SQLite database and syncs when online.

Conflict resolution (spec §3): independent rows (list contributions, recipes)
union on concurrent adds and never collide; field edits are last-write-wins
(fine for two trusted users); deletes are soft-delete tombstones. No CRDTs.

```
Flutter app  ──writes──▶  local SQLite  ──PowerSync queue──▶  Supabase Postgres
     ▲                        │                                     │
     └──────reactive reads────┘◀──────PowerSync sync stream─────────┘
```

## The one architectural spine: matching is online-only (ADR-0004)

Recipe import is the only place fuzzy matching happens, and import is always
online (we're either fetching a webpage or calling a vision model). That single
fact means the phone never needs an embedding model or the 8,000-row USDA
reference set. The match engine lives entirely server-side (a Supabase edge
function); only human-readable, already-resolved `ingredient` rows sync to the
device.

Two lookups that look similar but are different jobs (design doc §10):

- **Machine proposes, then a human confirms** — import reconciliation. Online,
  full ranked cascade, auto-accepts above a threshold. Server-side.
- **Human picks from a list** — the manual "Add ingredient" search. Offline,
  typo-tolerant retrieval over ~150–300 synced rows. On-device.

## Two-tier ingredient vocabulary (ADR-0005)

- `ingredient` — the household's lean, curated vocabulary (~150–300 rows). The
  match target, and the only ingredient data that syncs to devices.
- `usda_food` — the full USDA FoodData Central reference, read-only,
  server-side only. Used to *create* ingredients and to prefill stubs. Never
  matched against at import.

Matching against a couple hundred ingredients the household actually uses is
high-precision; matching against 8k SR Legacy rows is not.

Both tables (+ `ingredient_alias`) live in `supabase/migrations/0002`; the rows
that fill them (the two seeds) are the remaining step-1 work.

## Data flow: plan → cook → shop

The whole product is one derivation pipeline (spec §4):

```
week_plan (what you want to eat)
   │  group by recipe, split by shelf life (greedy, O(n log n))
   ▼
batch cook plan (cook_session rows: when to cook, at what scale)
   │  one contribution per (cook_session, ingredient)
   ▼
shopping list (summed in canonical base, with per-source provenance)
```

The cook plan and shopping list are *derived views*, not hand-authored. That is
the core product thesis — see `docs/product-specs/product-spec.md` §4.

## Environments & secrets

Client config (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POWERSYNC_URL`) is injected
at build time via `--dart-define` and read in `lib/core/config/env.dart`. Nothing
sensitive is committed. The extraction model key is a **server-side** secret set
on the edge function, never shipped to the client.
