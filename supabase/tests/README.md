# Database tests

pgTAP tests for RLS policies and constraints. Run with `supabase test db`
(also run in CI, `.github/workflows/backend.yml`). Each `*.sql` file wraps its
assertions in `begin … rollback` so runs leave no residue.

- `rls_household_isolation.sql` — data-driven over ALL 13 household-scoped
  tables: a household can't read or write another's rows (select isolation +
  cross-household insert rejection per table); `usda_food` is denied to client
  roles but readable by `service_role`. New table? Add one setup row + one
  `iso_case` row.
- `onboarding.sql` — `ensure_onboarded()` (0007, hardened in 0008): advisory
  lock taken; the template household is never joinable and stays member-less;
  join fills the open seat; a third user gets a fresh household; the template
  clone excludes `source='manual'` ingredients and `'import_correction'`
  aliases; no template → clean no-op (empty vocab); idempotency.
- `unit_admission.sql` — ADR-0008 unit admission (0012) as amended by
  [ADR-0009](../../docs/decisions/0009-density-unlocks-both-families.md)
  (0014) and brought to parity with the app by 0021 (plan 0020 D4c + J3:
  basis-strict mates, the density unlock derived as `derived(with) −
  derived(without)` of default unit AND basis, the per-word imprecise gate):
  `default_allowed_units()` / `density_unlocked_units()` vectors that mirror
  `app/test/features/ingredients/allowed_units_test.dart` CASE FOR CASE (each
  block names the Dart test it twins), so a drift between the SQL and Dart
  mirrors fails one suite or the other; the materialization trigger; the
  flour shape 0021 exists for (a density landing server-side on a stripped
  cup /g row restores `cup`) and 0021's backfill post-state as a table-wide
  invariant; that the backfill and the seed refresh
  UNIONED rather than re-materialized (curated additions and removals both
  survive); that every piece-default produce row with a density admits
  cup/tbsp/ml (this assertion REPLACED the seed-level produce patch — one
  source of the fact, per ADR-0009); the density→`allowed_units` union
  trigger; the USDA stub prefill trigger, including that a stub insert
  survives a prefill that throws; and the plan-0022 /
  [ADR-0010](../../docs/decisions/0010-piece-is-an-admission-fact.md) `piece`
  guard — no seeded ingredient carrying a measure admits `piece`, while the
  derived rule still gives a measure-less count row its fallback. That pass is
  DATA (`seed/curation_overrides.jsonl`), not a rule, so this assertion is the
  only thing standing between a regenerated seed and a silently restored
  `piece`.
- `nested_recipes.sql` — a recipe as an ingredient (0017, exec plan 0021
  D1/D2/D5): the line-item identity XOR (`ingredient_id` ⊻ `sub_recipe_id`)
  and the "a component carries no `measure_id`" fence; the yield checks
  (positivity, both-or-neither per denomination, no second without a first,
  and the DIFFERENT-family rule) plus the `unit_family()` vectors that mirror
  `UnitFamily` in `app/lib/core/units/units.dart`; and the cycle/household
  guard trigger — self-link, two-step and three-step cycles, the UPDATE leg,
  that a soft-deleted link doesn't count, and that a `sub_recipe_id` can
  never reach another household's recipe (from `authenticated` AND from a
  superuser write, where RLS isn't doing the work).
- `shopping_week.sql` — the shopping overlay's week scope (0019, week-redesign
  D3): `shopping_list_entry.week_start_date` exists, is a nullable `date` (null
  = the global free-text staple), and carries the household+week index the list
  read runs on; that `shopping_list_contribution` gained NOTHING (a top-up
  rides its entry's week); that no unique index arrived with it, so the same
  ingredient can sit on two weeks AND still twice on one week — the offline
  duplicate 0006 deliberately allows; and that the identity XOR, the
  contribution cascade and household RLS are all unchanged by it.
- `measure_rollout.sql` — the monotone `ingredient_measure` rollout
  ([`../rollout_measure_refresh.sql`](../rollout_measure_refresh.sql), plan
  0023 lane B): a template measure the household's matching ingredient lacks
  is inserted (keyed on ingredient `match_text` + measure `label`; columns
  verbatim; fresh `updated_at`); an existing live measure keeps its own
  weight; the household's own measures are untouched; a soft-deleted label
  is never resurrected; a tombstoned template measure, a `manual` template
  ingredient's measure and a basis-mismatched one never cross; soft-deleted
  households/ingredients and the template itself gain nothing; a second run
  is a no-op. pgTAP cannot include a file outside `tests/`, so the script's
  statement is mirrored verbatim between `>>>`/`<<<` markers inside a temp
  function — `make db-lint` diffs the two blocks.
- `access_token_hook.sql` — `add_household_claim()` (0007/0008): injects the
  `household_id` claim for an onboarded user (oldest live membership,
  agreeing with `current_household_id()`), passes a not-yet-onboarded user's
  event through unchanged, and is executable only by `supabase_auth_admin`.

Add a test here whenever a new table's RLS or a constraint needs defending.
