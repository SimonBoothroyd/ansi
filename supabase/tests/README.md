# Database tests

pgTAP tests for RLS policies and constraints. Run with `supabase test db`
(also run in CI, `.github/workflows/backend.yml`). Each `*.sql` file wraps its
assertions in `begin … rollback` so runs leave no residue.

- `rls_household_isolation.sql` — data-driven over ALL 17 household-scoped
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
  it: every seeded piece-default row carries a `piece_basis_amount` and
  therefore admits `piece`; exactly as many rows admit `piece` as say it; no
  row with any other default admits it, weight or no weight; a borrowed weight
  matches a live measure of its own row; the check constraint refuses zero;
  and the piece-weight union trigger (0039, the mirror of the density one)
  adds `piece` when a weight arrives and keeps the household's own words.

  What the suite does **not** pin is the seeded POPULATION — no headcount, and
  no "every row says X". The template is a copy of the owner's live household
  rather than a materialization of the rule, and ADR-0014's ruling is *all to
  all, and let the user prune*, so a row that no longer says `fl oz` or quarts
  is a curation rather than a regression. Two invariants a curated list may
  never break stand in their place: every row admits its own `default_unit`
  (the client guard — the picker draws this list and the import validates
  against it), and every unit in a list is either in the rule's derived set
  for that row or an imprecise word (`pinch` · `dash` · `handful` ·
  `to_taste`). A curator may withhold a convertible unit and add a word; he
  may not admit a unit the row cannot convert.
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
- `recipe_measure.sql` — a recipe's own word for one of what it makes (0048):
  the shape (a label that is a word, a positive `per_batch`) and the
  deliberate ABSENCE of a unique `(recipe_id, label)` index, so an offline
  duplicate lands instead of 23505-ing the whole crud transaction; the two
  pointers on `recipe_line_item` and `week_recipe_line_override`, each sayable
  only on a component line, only beside a number and never beside a unit —
  with both rules that demanded a unit still refusing exactly what they always
  refused for a row without a measure (`recipe_line_item.unit` relaxed to
  nullable behind an XOR, 0040's pair rule restated with its old form as the
  `else`); the guard trigger's three refusals
  (another recipe's word, another household's word, a retired word) and its
  happy path; that a line whose word has since gone stays editable and keeps
  its number, because it is unresolved rather than re-read as a count; and the
  boundary — RLS on, no delete policy, in the `powersync` publication.
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
- `household_week_start.sql` — the household's first day of the week and the
  re-home that follows it (0043): the column's shape, default and ISO range,
  and the two questions the re-home asks — `week_key_for()` of a DATE, and
  `week_rekey()` of a seven-day WINDOW, asserted in both directions because a
  rule that only ever slid a key backwards would take Sun 6 Sep out to Mon 31
  Aug on the way home and do it again on every flip. Then a Monday→Sunday flip
  asserted meal by meal — every week back a day, every meal on the calendar day
  it was already on, the Sunday meal OPENING the next week instead of closing
  this one, the tick following its week while a week-less one stays week-less,
  the variant of a recipe that left the week carried and the variant of a
  recipe that stayed left alone, and the row count of all four tables
  unchanged. Then the three properties the setting rests on: a second call
  changes nothing at all (`household.updated_at` included); a flip back
  restores the WHOLE address book — every week row, meal, tick and variant at
  the address it started at, with nothing created, emptied or tombstoned, which
  is what makes this a setting rather than a one-way door; and a week uploaded
  under the old key by a device that was offline across the flip is re-homed by
  the next run — run for real in BOTH shapes, the free window and the one the
  real week already occupies, because the second is the only way two rows can
  claim one window and the only thing that could break `unique (household_id,
  week_start_date)` mid-update. Finally the fence, as plain `authenticated`:
  one household cannot flip another's, can flip its own through the ordinary
  grants (the function is security INVOKER, so 0043's column-narrow `update (…,
  week_starts_on)` grant is load-bearing and `is_template` still is not on that
  list), and a day outside 1..7 is refused by name before anything moves.
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
- `default_measure_dropped.sql` — the retired default-measure machinery is
  gone (0042): no `ingredient.default_measure_id`, no own-measure trigger, no
  index, no backfill function, and `ensure_onboarded()` still clones the
  template's measures into a fresh household without it.
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
