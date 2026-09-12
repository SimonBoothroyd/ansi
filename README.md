# Ansi

A shared, offline-first recipe and meal-planning app for a two-person household.
Plan the week you *want to eat*; Ansi derives what to cook in batches (bounded by
each dish's shelf life) and builds a shopping list that buys each thing once.

Ansi (né Mise; *mise-en-place* is still the soul). The rename shipped on
2026-09-01 and reached everything that runs — package, identifiers, bundle ids,
OAuth scheme. "Mise" survives only in finished records (completed plans, ADRs,
captured eval runs) and in the pre-rename OAuth redirect entry the cloud
still lists until a Google sign-in has been walked on an `io.ansi.app` build
([`docs/cloud-setup.md`](./docs/cloud-setup.md), the dashboard checklist).

Flutter · Forui · Supabase (Postgres + Auth + Storage) · PowerSync (offline sync)

## How this is built — read this first

**This project is entirely vibe-coded.** Every line of application code, every
test, migration, edge function and generated seed, and most of the prose under
`docs/`, was written by AI coding agents (Claude Code). The humans — a
two-person household, one of them a developer — have never hand-written the
code. What they do is steer: they write and review the product spec, the
decision records, the execution plans and the design board, look at the app on
a phone, and send the agents back with notes. The repo's conventions
(`AGENTS.md`, the structural tests, `make docs-check`) exist to keep agents
honest across sessions, not as a record of human craft.

Read the code with that in mind. It is tested, it runs a real household's
kitchen every week, and it has been reviewed by a person at the level of
behaviour and design rather than line by line. If you contribute, the same
mode works: change the docs and the plan, and let an agent do the typing.

## Repository

```
app/         Flutter client
supabase/    Postgres migrations + Deno edge functions (import + matching)
docker/      Local PowerSync service (compose + sync rules)
evals/       Eval harness for the import/matching pipeline
docs/        Architecture, decision records (ADRs), and the product spec
scripts/     Bootstrap, codegen, and USDA seed helpers
```

Agent/contributor conventions live in `AGENTS.md` — a lean *map* into the
`docs/` knowledge base (the system of record; see `docs/README.md`).
Architecture: `ARCHITECTURE.md`. Roadmap + status: `docs/exec-plans/roadmap.md`.

## Quick start

```bash
scripts/bootstrap.sh          # checks tooling, installs deps, copies env template
cp .env.local.template .env.local   # then fill in Supabase + PowerSync values
make db-up                    # supabase start + local PowerSync service
make run                      # launch the Flutter app
```

Prerequisites: Flutter 3.44+, Dart 3.8+, the Supabase CLI, Deno, and Docker.
`scripts/bootstrap.sh` checks these and tells you what's missing.

Those are floors; **CI pins exact versions, and local should match them** —
Flutter `3.47.1` (`.github/workflows/app.yml`; 3.47.2's Dart adds an analyze
warning), Deno `2.9.5` and the Supabase CLI `2.115.0` (`backend.yml`), Postgres
`17` (`supabase/config.toml`). Each pin is commented where it lives with the red
run that bought it. Bump a pin and your local tool in the same commit.

## Testing

```bash
make test         # app unit/widget tests + edge-function tests
make test-app     # flutter test only
make coverage     # flutter test --coverage, report in app/coverage/
make evals        # run the matching eval harness (see evals/README.md)
```

## License

MIT — see `LICENSE`.
