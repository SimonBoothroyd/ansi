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
  (0014): `default_allowed_units()` / `density_unlocked_units()` vectors —
  the SAME shapes `app/test/features/ingredients/allowed_units_test.dart`
  pins, so a drift between the SQL and Dart mirrors fails one suite or the
  other; the materialization trigger; that the backfill and the seed refresh
  UNIONED rather than re-materialized (curated additions and removals both
  survive); that every piece-default produce row with a density admits
  cup/tbsp/ml (this assertion REPLACED the seed-level produce patch — one
  source of the fact, per ADR-0009); the density→`allowed_units` union
  trigger; and the USDA stub prefill trigger, including that a stub insert
  survives a prefill that throws.
- `access_token_hook.sql` — `add_household_claim()` (0007/0008): injects the
  `household_id` claim for an onboarded user (oldest live membership,
  agreeing with `current_household_id()`), passes a not-yet-onboarded user's
  event through unchanged, and is executable only by `supabase_auth_admin`.

Add a test here whenever a new table's RLS or a constraint needs defending.
