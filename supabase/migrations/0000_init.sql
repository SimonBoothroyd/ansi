-- 0000_init.sql — infrastructure wiring only.
-- The domain data model (household, ingredient, recipe, week_plan, cook_session,
-- shopping_list_*) is defined per the product spec §4 as it's built out — see
-- docs/product-specs/product-spec.md and docs/exec-plans/roadmap.md. This
-- migration only sets up extensions and the PowerSync publication so later
-- migrations have the ground they need.

-- Extensions the design relies on:
create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists pg_trgm;    -- trigram fuzzy match (server-side; ADR-0004)

-- PowerSync publishes row changes to the sync service. Add tables to this
-- publication as they're created (ALTER PUBLICATION powersync ADD TABLE ...).
-- Created empty here; first domain migration will extend it.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    execute 'create publication powersync';
  end if;
end $$;

-- TODO(step-1+): domain tables land in numbered migrations (0001_household.sql,
-- 0002_ingredients.sql, ...), each with:
--   * household_id column + FK
--   * RLS enabled + policies (docs/SECURITY.md)
--   * ALTER PUBLICATION powersync ADD TABLE <t>  (if it should sync)
