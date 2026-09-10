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
  (0014), [ADR-0014](../../docs/decisions/0014-all-to-all-admission.md) (0037,
  a family is admitted whole) and ADR-0015 (0039, a piece weight is a row
  fact): `default_allowed_units()` / `density_unlocked_units()` vectors that
  mirror `app/test/features/ingredients/allowed_units_test.dart` CASE FOR CASE
  (each block names the Dart test it twins), so a drift between the SQL and
  Dart mirrors fails one suite or the other; the materialization trigger; the
  flour shape 0021 exists for (a density landing server-side on a stripped
  cup /g row restores `cup`) and 0021's backfill post-state as a table-wide
  invariant; that the backfill and the seed refresh
  UNIONED rather than re-materialized (curated additions and removals both
  survive); that every piece-default produce row with a density admits
  cup/tbsp/ml (this assertion REPLACED the seed-level produce patch — one
  source of the fact, per ADR-0009); the density→`allowed_units` union
  trigger; and the USDA search door (`probe_usda` — read-only, ranked, capped,
  and offering weak rows rather than withholding them).

  The **`piece` guard** turned inside out with ADR-0015. It used to pin that
  no seeded ingredient carrying a measure admits `piece` — the outcome of 143
  hand-written removals. It now pins the RULE and the seed's data landing on
  it: all 76 seeded piece-default rows carry a `piece_basis_amount` and
  therefore admit `piece`; no row with any other default admits it, weight or
  no weight; a borrowed weight matches a live measure of its own row; the
  check constraint refuses zero; and the piece-weight union trigger (0039, the
  mirror of the density one) adds `piece` when a weight arrives and keeps the
  household's own words.
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
- `shopping_week.sql` — the shopping overlay's week scope (0019 and 0036):
  `shopping_list_entry.week_start_date` exists, is a nullable `date` (the
  column still admits the week-less rows an older client wrote), and carries
  the household+week index the list read runs on; that a free-text item stores
  the week it was added on, like the top-up beside it, and that
  `shopping_free_text_week_backfill()` lands a week-less free-text row on the
  ISO Monday of its own `created_at` — the soft-deleted one included, so an
  undelete cannot resurrect a week-less row — and is a no-op on a second run;
  that `shopping_list_contribution` gained NOTHING (a top-up
  rides its entry's week); that no unique index arrived with it, so the same
  ingredient can sit on two weeks AND still twice on one week — the offline
  duplicate 0006 deliberately allows; and that the identity XOR, the
  contribution cascade and household RLS are all unchanged by it.
- `measure_rollout.sql` — the monotone `ingredient_measure` rollout
  ([`../rollout_measure_refresh.sql`](../rollout_measure_refresh.sql), plan
  0023): a template measure the household's matching ingredient lacks
  is inserted (keyed on ingredient `match_text` + measure `label`; columns
  verbatim; fresh `updated_at`); an existing live measure keeps its own
  weight; the household's own measures are untouched; a soft-deleted label
  is never resurrected; a tombstoned template measure, a `manual` template
  ingredient's measure and a basis-mismatched one never cross; soft-deleted
  households/ingredients and the template itself gain nothing; a second run
  is a no-op. pgTAP cannot include a file outside `tests/`, so the script's
  statement is mirrored verbatim between `>>>`/`<<<` markers inside a temp
  function — `make db-lint` diffs the two blocks.
- `ingredient_rollout.sql` — the monotone `ingredient` rollout
  ([`../rollout_ingredient_refresh.sql`](../rollout_ingredient_refresh.sql)),
  the same mirrored-block shape as `measure_rollout.sql` (its own
  `>>>`/`<<<` pair, its own `make db-lint` diff), wrapped in a plpgsql temp
  function so the statement's `ROW_COUNT` — the number the operator reads off
  the run — is itself assertable. All four legs: (a) a null density filled
  from the template, and a household's own density kept on a row the
  statement does rewrite; (b) `allowed_units` unioned — the household's unit
  kept, the template's added; (c) a null piece weight filled with its
  `piece_source` beside it, an own weight kept; and (d) **fibre**, the one
  key inside `macros` this script writes: a row still holding exactly the
  template's four figures on the same `macros_basis` gains the template's
  `fiber` and nothing else moves (`status`, `source`, every other column
  untouched; `updated_at` bumped), while a row with one figure edited, a
  flipped basis, a `fiber` of its own, a tombstone, no template counterpart,
  or no macros at all is left exactly as it is. Plus: a soft-deleted
  household gains nothing, the template itself is never written, and a second
  run touches 0 rows.
- `default_measure.sql` — the default count measure (0023, plan 0024 seam D1),
  **retired by ADR-0015** and kept for one release because the data is durable.
  Nothing reads `ingredient.default_measure_id` any more and the generated seed
  no longer writes it, so this suite is what keeps the machinery honest while
  it is still there: the column is a nullable FK with `on delete set null` (a
  hard-deleted measure clears the default rather than dangling it); the
  own-measure trigger refuses a measure belonging to another ingredient or
  another household; the backfill (`ingredient_default_measure_backfill()`)
  fills a NULL by (`match_text`, measure `label`) per household, never
  overwrites a household's own choice, and is a no-op on a second run. The
  suite CALLS that backfill and then reads what it filled: 129 of its 132
  frozen pairs land, and **the thirteen measured rows it misses are asserted BY
  NAME** — the nine fragment sets, `lentil canned` (added after the snapshot
  froze) and the three rows plan 0039 renamed out from under it. A frozen
  pointer going stale against a moving vocabulary is the argument ADR-0015
  makes; `ensure_onboarded()` still carries what is there into a new household
  BY LABEL, re-keyed onto that household's own measure rows.
- `portion_factor.sql` — `household_member.portion_factor` (0026, exec plan
  0027 front P): defaults to 1 so every pre-existing member is the one-portion
  eater the head-count always meant (P-D6); the range check refuses below ¼
  and above 3 and admits both ends (P-D2); under RLS a member sets the
  partner's factor and their own, an UPDATE aimed at another household's
  member touches 0 rows, and the column-narrow grant means `display_name` and
  `auth_user_id` raise `42501` from the client (P-D3 — the one UPDATE door the
  table has).
- `access_token_hook.sql` — `add_household_claim()` (0007/0008): injects the
  `household_id` claim for an onboarded user (oldest live membership,
  agreeing with `current_household_id()`), passes a not-yet-onboarded user's
  event through unchanged, and is executable only by `supabase_auth_admin`.

Add a test here whenever a new table's RLS or a constraint needs defending.
