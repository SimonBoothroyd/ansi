# AGENTS.md — Ansi

> A **map, not a manual.** This file is a table of contents that points at the
> real sources of truth in `docs/`. Keep it ~100 lines. When a rule needs more
> than a line, it lives in a doc and is linked from here. (This structure follows
> OpenAI's "harness engineering": the repo is the system of record; AGENTS.md is
> the entry point for progressive disclosure — see `docs/README.md`.)
>
> Humans: read `README.md`. Nested `AGENTS.md` files (in `app/`, `supabase/`,
> `evals/`) override this one for their subtree — the closest file wins.

## What this is

Ansi — a shared, offline-first recipe + meal-planning app for a two-person
household. You plan the week you *want to eat*; the app derives what to cook in
batches (bounded by shelf life) and buys each thing once.

## Where to look (the docs are the source of truth)

| You need…                                | Go to |
|------------------------------------------|-------|
| The big-picture map of the system        | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Why a choice was made                     | [`docs/decisions/`](./docs/decisions) (ADRs) |
| What to build next, and current status    | [`docs/exec-plans/roadmap.md`](./docs/exec-plans/roadmap.md) |
| A specific in-flight task's plan          | [`docs/exec-plans/active/`](./docs/exec-plans/active) |
| Product behaviour (what the app does)     | [`docs/product-specs/`](./docs/product-specs) |
| The operating principles agents must hold | [`docs/design-docs/core-beliefs.md`](./docs/design-docs/core-beliefs.md) |
| The quality bar per area                  | [`docs/QUALITY.md`](./docs/QUALITY.md) |
| Secrets, auth, RLS                        | [`docs/SECURITY.md`](./docs/SECURITY.md) |
| Standing up cloud (Supabase/PowerSync/Google) | [`docs/cloud-setup.md`](./docs/cloud-setup.md) |
| Shipping — app release tags, Supabase deploys | [`docs/release.md`](./docs/release.md) |
| How the knowledge base itself works       | [`docs/README.md`](./docs/README.md) |
| Offline knowledge of key dependencies     | [`docs/references/`](./docs/references) |

Subtree rules: [`app/AGENTS.md`](./app/AGENTS.md) ·
[`supabase/AGENTS.md`](./supabase/AGENTS.md) ·
[`evals/AGENTS.md`](./evals/AGENTS.md)

## The three invariants that shape everything

1. **Matching is online-only.** The phone never fuzzy-matches; the match engine
   lives server-side. No embedding model or 8k-row reference set in `app/`.
   (ADR-0004.)
2. **Domain is pure Dart.** `app/lib/core/units` and every `*/domain/` folder must
   not import `package:flutter`. Enforced mechanically in CI.
3. **Honest numbers.** A `stub` ingredient (missing density/macros) is excluded
   from conversions and macro totals. Never invent a value to make math work.

## Golden rules

- **Docs are part of the code.** A change that alters behaviour updates the
  relevant doc in the same PR. Stale docs are bugs. (`make docs-check` enforces
  link integrity; see `docs/README.md` on doc-gardening.)
- **Every change lands with a test.** No new logic in `core/` or a `domain/`
  without a mirrored test. CI blocks on analyze + test.
- **Enforce invariants, not style.** Prefer a lint or structural test over a prose
  rule. If you keep repeating a correction, promote it into tooling.
- **Boring, legible dependencies.** Favour what an agent can fully reason about
  in-repo. Secrets via `--dart-define`/env, never committed.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`…).

## Verify before you claim done

```
make gen          # codegen (Riverpod/Freezed/json)
make analyze      # dart analyze + custom_lint — must be clean
make test         # flutter test + edge-function tests
make docs-check   # doc links resolve; knowledge base is intact
```

If a command here is wrong, fix this file in the same change.
