-- 0006_shopping.sql — shopping list from the cook plan (roadmap step 6).
--
-- The OUTPUT of the derived pipeline (spec §4). The list is assembled by
-- summing per-ingredient contributions, but only the parts that CANNOT be
-- re-derived are stored here:
--
--   * `shopping_list_entry`   — one row per ingredient the user has *touched*
--                               (checked it off, or topped it up), plus
--                               free-text non-food items ("paper towels").
--                               Holds the check-off state (spec §4: check-off is
--                               on the entry, not per contribution).
--   * `shopping_list_contribution` — the stored breakdown. Only `manual`
--                               contributions live here. The `cook_session`
--                               contributions are DERIVED live from the batch
--                               cook plan (which is itself derived — step 5, no
--                               cook_session table), so there is no stable
--                               `source_cook_session_id` to persist and nothing
--                               to reconcile when the week or a recipe changes.
--                               Each device re-derives them from the synced
--                               week + recipes. The column is carried per spec
--                               §4 for forward-compat but stays null in v1.
--
-- Why derive rather than materialize (matching steps 4/5): the cook plan is a
-- pure function of the week + recipe shelf-life, so snapshotting contributions
-- would need regeneration/reconciliation on every plan edit — the complexity
-- those steps deliberately avoided. Storing only check-off + manual keeps sync
-- clean: two users share check-off and top-ups; the derived totals are local.
--
-- Lifecycle / sync note (the recipe-deleted-but-checked case): an entry is only
-- displayed while it has at least one *live* contribution (a derived cook one or
-- a persisted manual one) or is a free-text item. If a recipe is deleted, its
-- cook contribution vanishes and an ingredient entry with no manual top-up drops
-- off the list — its checked row stays inert (harmless) and its check-state
-- returns if the ingredient is re-planned. Recipe deletion never touches the
-- vocab `ingredient` row, so `ingredient_id` never dangles. A "clear list / new
-- trip" action is deferred (a sync concern — step 7).
--
-- Still LOCAL-ONLY (no `.connect()` — sync is step 7). RLS / grants / publication
-- are authored now, same shape as 0003/0004/0005, so step 7 only calls
-- `.connect()`.

-- One rolled-up line: an ingredient (ingredient_id set) OR a free-text item
-- (free_text set, e.g. a non-food staple). Holds the check-off state and anchors
-- the manual contributions. `unit` is the preferred display/entry unit (nullable
-- — a bare non-food item has none). At most one live entry per ingredient per
-- household (enforced in app logic: find-or-create).
create table shopping_list_entry (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  ingredient_id uuid references ingredient(id),   -- null for a free-text item
  free_text     text,                             -- null for an ingredient
  category      text,                             -- aisle group for a free-text item
  checked       boolean not null default false,   -- check-off is on the entry
  unit          text,                             -- preferred display unit (nullable)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,                      -- soft-delete tombstone (spec §3)
  -- Exactly one of ingredient_id / free_text identifies the line.
  check ((ingredient_id is not null) <> (free_text is not null))
);

-- The stored breakdown behind an entry's total. v1 only ever stores `manual`
-- contributions (top-ups + a quantity on a free-text item); `cook_session` rows
-- are derived, never persisted. `source_cook_session_id` is carried per spec §4
-- but stays null until (if ever) cook sessions gain stable ids.
create table shopping_list_contribution (
  id                     uuid primary key default gen_random_uuid(),
  household_id           uuid not null references household(id),
  entry_id               uuid not null references shopping_list_entry(id) on delete cascade,
  source_type            text not null default 'manual'
                           check (source_type in ('cook_session', 'manual')),
  source_cook_session_id text,                   -- always null in v1 (derived)
  quantity               numeric,                -- nullable (a bare non-food item)
  unit                   text,
  note                   text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz
);

-- Foreign-key / lookup indexes.
create index shopping_list_entry_household_idx on shopping_list_entry (household_id);
create index shopping_list_entry_ingredient_idx on shopping_list_entry (ingredient_id);
create index shopping_list_contribution_entry_idx on shopping_list_contribution (entry_id);
create index shopping_list_contribution_household_idx on shopping_list_contribution (household_id);

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (same shape as 0001..0005).
alter table shopping_list_entry enable row level security;
alter table shopping_list_contribution enable row level security;

create policy shopping_list_entry_read on shopping_list_entry
  for select using (household_id = current_household_id());
create policy shopping_list_entry_write on shopping_list_entry
  for insert with check (household_id = current_household_id());
create policy shopping_list_entry_update on shopping_list_entry
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

create policy shopping_list_contribution_read on shopping_list_contribution
  for select using (household_id = current_household_id());
create policy shopping_list_contribution_write on shopping_list_contribution
  for insert with check (household_id = current_household_id());
create policy shopping_list_contribution_update on shopping_list_contribution
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Table privileges mirror the policies (no DELETE — soft delete). service_role
-- (edge functions, seed) bypasses RLS.
grant select, insert, update on shopping_list_entry to authenticated;
grant select, insert, update on shopping_list_contribution to authenticated;
grant all on shopping_list_entry, shopping_list_contribution to service_role;

-- Sync these down with the household's data (bucket wiring lands in step 7's
-- powersync.yaml).
alter publication powersync add table shopping_list_entry, shopping_list_contribution;
