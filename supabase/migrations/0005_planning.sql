-- 0005_planning.sql — week planning (roadmap step 4).
--
-- The INPUT to the derived pipeline (spec §4). You plan the single active week
-- you *want to eat*: a `week_plan` holds `plan_entry` rows — one per meal — each
-- naming a recipe, a day, a user-typed meal slot, and who is eating. There is no
-- batch/leftover thinking here; that is derived downstream (step 5's cook plan).
--
-- One active week = the week containing today (Monday-first); older `week_plan`
-- rows are simply the past, reached only through "copy last week" (spec §4, no
-- calendar). `week_start_date` is that Monday, so a week is addressed by date.
--
-- Multiple entries per (day, slot) are allowed (different breakfasts, a lunch
-- for one) — they are independent rows, so concurrent adds union cleanly under
-- sync (spec §3). Meal slots are free text, NOT a preset enum (spec §8): the
-- client offers Breakfast/Lunch/Dinner but stores whatever the user types.
--
-- `eaters` is a JSON array of `household_member` ids. It is a field on the
-- entry, not a join table: two trusted users, and spec §3 makes field edits
-- last-write-wins. `household_member` itself lands in 0001; no auth exists yet,
-- so the client seeds two local members (see schema.dart) until step 7 syncs the
-- real ones.
--
-- `portions` resolves spec §8's open `portions_override` question: demand for an
-- entry defaults to |eaters| but can be bumped (big appetites), so it is stored
-- as a nullable int — null means "track |eaters|", a number overrides it.
--
-- Still LOCAL-ONLY (no `.connect()` — sync is step 7). RLS / grants / publication
-- are authored now, same shape as 0003/0004, so step 7 only calls `.connect()`.

create table week_plan (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references household(id),
  week_start_date  date not null,        -- the Monday this week begins on
  label            text,                 -- optional user label; usually null
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,          -- soft-delete tombstone (spec §3)
  unique (household_id, week_start_date)
);

-- One planned meal. day_of_week is 0=Monday .. 6=Sunday (Monday-first grid).
-- recipe_id is the dish; meal_slot is the free-text slot label; eaters is a
-- JSON array of household_member ids; sort_order breaks ties within a slot.
create table plan_entry (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  week_plan_id  uuid not null references week_plan(id) on delete cascade,
  day_of_week   int not null check (day_of_week between 0 and 6),
  meal_slot     text not null,        -- free text ("Breakfast", "Dinner", …)
  recipe_id     uuid not null references recipe(id),
  eaters        jsonb not null default '[]'::jsonb,  -- household_member ids
  portions      int,                  -- null → defaults to |eaters| (spec §8)
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- Foreign-key / lookup indexes.
create index week_plan_household_idx   on week_plan (household_id);
create index plan_entry_week_idx       on plan_entry (week_plan_id);
create index plan_entry_household_idx  on plan_entry (household_id);
create index plan_entry_recipe_idx     on plan_entry (recipe_id);

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (same shape as 0001/0002/0003/0004).
alter table week_plan enable row level security;
alter table plan_entry enable row level security;

create policy week_plan_read on week_plan
  for select using (household_id = current_household_id());
create policy week_plan_write on week_plan
  for insert with check (household_id = current_household_id());
create policy week_plan_update on week_plan
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

create policy plan_entry_read on plan_entry
  for select using (household_id = current_household_id());
create policy plan_entry_write on plan_entry
  for insert with check (household_id = current_household_id());
create policy plan_entry_update on plan_entry
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Table privileges mirror the policies (no DELETE — soft delete). service_role
-- (edge functions, seed) bypasses RLS.
grant select, insert, update on week_plan to authenticated;
grant select, insert, update on plan_entry to authenticated;
grant all on week_plan, plan_entry to service_role;

-- Sync these down with the household's data (bucket wiring lands in step 7's
-- powersync.yaml).
alter publication powersync add table week_plan, plan_entry;
