-- 0003_recipes.sql — single-user recipes (roadmap step 2).
--
-- A recipe is a title + base servings + an ordered method, holding ordered
-- ingredient groups ("for the sauce"), each holding ordered line-items (an
-- ingredient + quantity + unit). Groups and line-items are their OWN rows, not
-- nested JSON, for two reasons: independent adds union cleanly under sync (spec
-- §3 conflict model), and each carries a `sort_order` so ordering survives
-- last-write-wins field edits.
--
-- Step 2 runs LOCAL-ONLY: the app opens PowerSync's local SQLite but never
-- connects (see docs/exec-plans/active/0002-single-user-recipes.md). This
-- migration is authored now anyway so Postgres and the client schema.dart stay
-- in lockstep and step 7 only has to call .connect() — the RLS/grants/publication
-- below are the same boundaries every synced table already follows (0001/0002).
--
-- Deferred to their own steps (columns intentionally absent to avoid churn):
--   * book_id / section  → step 3 (books table doesn't exist yet)
--   * recipe photo        → needs Storage + auth
-- Shelf-life columns (keeps_for_days, freezable, freezer_days) ARE included now:
-- the spec attaches them to Recipe and step 5 (cook plan) reads them; landing the
-- columns here avoids a later table rewrite. No UI drives them in step 2.

create table recipe (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references household(id),
  title           text not null,
  servings_base   numeric not null default 1 check (servings_base > 0),
  steps           jsonb not null default '[]'::jsonb,  -- ordered array of text
  keeps_for_days  int,                 -- fridge shelf life; drives step-5 clustering
  freezable       boolean not null default false,
  freezer_days    int,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz          -- soft-delete tombstone (spec §3)
);

-- A named group of line-items within a recipe ("For the sauce"). name nullable:
-- a recipe with no explicit grouping has a single unnamed group.
create table ingredient_group (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  recipe_id     uuid not null references recipe(id) on delete cascade,
  name          text,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- One ingredient line in a group. quantity nullable so imprecise units ("to
-- taste") carry no number; unit is a units.dart Unit id (e.g. 'g', 'tbsp').
create table recipe_line_item (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  group_id      uuid not null references ingredient_group(id) on delete cascade,
  ingredient_id uuid not null references ingredient(id),
  quantity      numeric,
  unit          text not null,        -- units.dart Unit id
  note          text,                 -- e.g. "finely chopped"
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- Foreign-key lookup indexes.
create index recipe_household_idx     on recipe (household_id);
create index group_recipe_idx         on ingredient_group (recipe_id);
create index group_household_idx      on ingredient_group (household_id);
create index line_item_group_idx      on recipe_line_item (group_id);
create index line_item_ingredient_idx on recipe_line_item (ingredient_id);
create index line_item_household_idx  on recipe_line_item (household_id);

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (same shape as 0001/0002).
alter table recipe enable row level security;
alter table ingredient_group enable row level security;
alter table recipe_line_item enable row level security;

create policy recipe_read on recipe
  for select using (household_id = current_household_id());
create policy recipe_write on recipe
  for insert with check (household_id = current_household_id());
create policy recipe_update on recipe
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

create policy group_read on ingredient_group
  for select using (household_id = current_household_id());
create policy group_write on ingredient_group
  for insert with check (household_id = current_household_id());
create policy group_update on ingredient_group
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

create policy line_item_read on recipe_line_item
  for select using (household_id = current_household_id());
create policy line_item_write on recipe_line_item
  for insert with check (household_id = current_household_id());
create policy line_item_update on recipe_line_item
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Table privileges mirror the policies (no DELETE — soft delete). service_role
-- (edge functions, seed) bypasses RLS.
grant select, insert, update on recipe to authenticated;
grant select, insert, update on ingredient_group to authenticated;
grant select, insert, update on recipe_line_item to authenticated;
grant all on recipe, ingredient_group, recipe_line_item to service_role;

-- Sync these down with the household's data. Bucket entries land in step 7's
-- powersync.yaml wiring; the publication membership is set now.
alter publication powersync add table recipe, ingredient_group, recipe_line_item;
