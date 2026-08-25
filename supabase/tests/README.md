# Database tests

pgTAP tests for RLS policies and constraints. Run with `supabase test db`
(also run in CI, `.github/workflows/backend.yml`). Each `*.sql` file wraps its
assertions in `begin … rollback` so runs leave no residue.

- `rls_household_isolation.sql` — a household can't read or write another's rows;
  `usda_food` is denied to client roles but readable by `service_role`.

Add a test here whenever a new table's RLS or a constraint needs defending.
