-- 0002_ingredients.sql — the ingredient data model (roadmap step 1).
--
-- Implements the two-tier vocabulary from docs/product-specs/import-and-matching.md
-- §5.2. The split is the biggest match-quality lever: the thing we MATCH AGAINST
-- (`ingredient`, the household's lean curated vocab, ~150–300 rows, synced) is
-- kept separate from the thing we SEARCH WHEN CREATING (`usda_food`, the full FDC
-- reference, ~8k rows, server-side only, never matched at import — ADR-0005).
--
-- `match_text` is the normalized form (§7) written on each row. It is filled by
-- the shared normalization function — NOT a generated column, because §7
-- normalization is more than lowercasing (singularize, strip prep verbs, keep
-- form/state words). That function is a step-8 artifact; until it exists, writers
-- supply match_text. The batch seed pipeline MUST call the same normalizer, or
-- the gold labels drift from the live cascade (see import-and-matching.md §7).
--
-- Honest numbers (invariant 3): density/macros are nullable. A row missing them
-- is status='stub' and is excluded from conversions and macro totals until a
-- human completes it (§9 stub lifecycle). Never invent a value here.

-- The household vocabulary: match target + the only ingredient data that syncs.
create table ingredient (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references household(id),
  canonical_name    text not null,
  category          text,
  default_unit      text not null,      -- a units.dart Unit id (e.g. 'g', 'ml')
  density_g_per_ml  numeric,            -- nullable; null → stub
  macros            jsonb,              -- {kcal, protein, carb, fat}; nullable
  status            text not null default 'stub'
                      check (status in ('complete', 'stub')),
  source            text,               -- 'usda_fdc:<id>' | 'manual' | 'barcode'
                                        -- | 'import_stub' | 'seed'
  match_text        text not null,      -- normalized canonical_name (§7)
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz         -- soft-delete tombstone (spec §3)
);

-- Aliases are their own table (not an array) so they can be trigram-indexed and
-- so import corrections write back cleanly as new rows (§8 learning loop).
create table ingredient_alias (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  ingredient_id uuid not null references ingredient(id) on delete cascade,
  alias_text    text not null,          -- as originally seen/entered
  match_text    text not null,          -- normalized form (§7)
  source        text not null           -- 'seed' | 'import_correction' | 'manual'
                  check (source in ('seed', 'import_correction', 'manual')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- Read-only reference. Server-side ONLY: never synced, never matched at import
-- (ADR-0005). Used for the "create new ingredient" search and stub prefill (§9).
-- Global, so no household_id.
create table usda_food (
  fdc_id            int primary key,
  description       text not null,
  category          text,
  density_g_per_ml  numeric,
  macros            jsonb,
  match_text        text not null
);

-- Trigram indexes power the fuzzy cascade (§6). pg_trgm is enabled in 0000.
create index ing_match_trgm   on ingredient       using gin (match_text gin_trgm_ops);
create index alias_match_trgm on ingredient_alias using gin (match_text gin_trgm_ops);
create index usda_match_trgm  on usda_food        using gin (match_text gin_trgm_ops);

-- Foreign-key lookup indexes.
create index ingredient_household_idx    on ingredient (household_id);
create index alias_ingredient_idx        on ingredient_alias (ingredient_id);
create index alias_household_idx         on ingredient_alias (household_id);

-- RLS: household-scoped tables let a member read/write only their own rows.
-- Deletes are soft (update deleted_at), so no delete policy.
alter table ingredient enable row level security;
alter table ingredient_alias enable row level security;

create policy ingredient_read on ingredient
  for select using (household_id = current_household_id());
create policy ingredient_write on ingredient
  for insert with check (household_id = current_household_id());
create policy ingredient_update on ingredient
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

create policy alias_read on ingredient_alias
  for select using (household_id = current_household_id());
create policy alias_write on ingredient_alias
  for insert with check (household_id = current_household_id());
create policy alias_update on ingredient_alias
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- usda_food: RLS on with NO policies denies all client access. Only the service
-- role (edge functions, seed job) reaches it, and it bypasses RLS. This is the
-- mechanical enforcement of "server-side only" — never exposed via PostgREST.
alter table usda_food enable row level security;

-- Table privileges (see 0001). authenticated grants mirror the policies (no
-- DELETE — soft delete). usda_food is granted to NO client role — "server-side
-- only" (ADR-0005) is now enforced at the grant layer too, not just RLS.
grant select, insert, update on ingredient to authenticated;
grant select, insert, update on ingredient_alias to authenticated;
grant all on ingredient, ingredient_alias, usda_food to service_role;

-- Sync the resolved household vocab down; usda_food is deliberately absent.
-- Bucket/sync rules that mirror these boundaries land in step 7 (powersync.yaml).
alter publication powersync add table ingredient, ingredient_alias;
