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
| What to build next, and what shipped      | [`docs/exec-plans/roadmap.md`](./docs/exec-plans/roadmap.md) |
| A specific in-flight task's plan          | [`docs/exec-plans/active/`](./docs/exec-plans/active) |
| Ideas the app hasn't built (not debt)     | [`docs/exec-plans/backlog.md`](./docs/exec-plans/backlog.md) |
| Debt someone still owes                   | [`docs/exec-plans/tech-debt-tracker.md`](./docs/exec-plans/tech-debt-tracker.md) |
| Product behaviour (what the app does)     | [`docs/product-specs/`](./docs/product-specs) |
| What a screen looks like                  | [`docs/product-specs/board/`](./docs/product-specs/board) |
| The operating principles agents must hold | [`docs/design-docs/core-beliefs.md`](./docs/design-docs/core-beliefs.md) |
| How each area stands, and its gap         | [`ARCHITECTURE.md`](./ARCHITECTURE.md#where-each-area-stands) |
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

## The design board

[`docs/product-specs/board/`](./docs/product-specs/board) is **one hand-written
HTML file per screen**, plus `index.html` (a status row per view) and
`board.css`. It says what the app looks like **today** — it is not a history.

- **Replace a screen, never append a version.** A design pass rewrites that
  file's frames and refreshes its status date. No `v2` section, no second copy.
- A **proposal** is drawn in the screen's own file, marked `proposed`, until it
  ships; then the frames it replaces are deleted.
- **Decisions do not live here.** Rulings, rejected alternatives, owner quotes,
  sign-offs and test results belong to the exec plan or an ADR, which the
  status line links.
- A frame that knowingly differs from the code says so in one `differs:` line.
- The **status date is a verification date** — the last time somebody read the
  view against `app/lib`. A brief that touches UI re-verifies the view it
  touches before bumping it. Frames drawn but never built live in
  `not-built.html`, each citing its backlog row.

Full rules: [`board/README.md`](./docs/product-specs/board/README.md).

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

**Run the narrowest thing that could fail, and widen only when it passes.** A
full sweep after every small edit is not diligence, it is waste: the simulator
suite alone is ~24 minutes for eight files, and a `make test` for a one-line
test fix buys nothing a single file did not already prove. The cost is not
only time — it is the reviewer's attention, spent on runs that were never in
doubt.

| You changed | Run |
|---|---|
| one test | that test's file: `make test-sim FILE=recipe_editor`, or `flutter test <path>` |
| one feature's code | that feature's tests, then `make analyze` |
| a domain rule, a schema, a shared widget | the full `make test` — the blast radius is genuinely wide |
| anything, before you say a task is done | `make analyze` + `make test` + `make docs-check`, **once** |
| a migration, a sync rule, or the seed | `make ci-full` (needs Docker) |

The full simulator suite is a **gate, not a step**: run it once before landing a
branch, not after each fix inside it. When it goes red, re-run the failing file
alone until it is green, then the suite once to confirm nothing else moved.

Two traps this repo has actually paid for:

- **Never pipe a test run through `tail` or `head`.** The pipe reports the
  *pipe's* exit status, so a red suite looks green. Redirect to a file and read
  the end of it.
- **Never kill a simulator run mid-flight** if you can avoid it. It can leave
  the run's users, the simulator or the app in a state the next run inherits,
  and you will spend longer diagnosing the wreckage than the run had left.

```
make gen          # codegen (Riverpod/Freezed/json)
make analyze      # dart analyze + custom_lint — must be clean
make test         # flutter test + edge-function tests
make docs-check   # doc links resolve; knowledge base is intact
make test-sim     # the simulator gate — FILE=<name> for one file
make ci-full      # everything CI runs, incl. migrations + pgTAP (needs Docker)
```

If a command here is wrong, fix this file in the same change.
