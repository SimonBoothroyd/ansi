# Ansi

A shared, offline-first recipe and meal-planning app for a two-person household.
Plan the week you *want to eat*; Ansi derives what to cook in batches (bounded by
each dish's shelf life) and builds a shopping list that buys each thing once.

Ansi (né Mise; *mise-en-place* is still the soul). The old name survives only
where changing it would break something live — see
[`docs/exec-plans/tech-debt-tracker.md`](./docs/exec-plans/tech-debt-tracker.md).

Flutter · Forui · Supabase (Postgres + Auth + Storage) · PowerSync (offline sync)

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

## Testing

```bash
make test         # app unit/widget tests + edge-function tests
make test-app     # flutter test only
make coverage     # flutter test --coverage, report in app/coverage/
make evals        # run the matching eval harness (see evals/README.md)
```

## License

MIT — see `LICENSE`.
