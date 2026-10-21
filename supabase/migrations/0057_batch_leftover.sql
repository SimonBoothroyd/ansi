-- 0057_batch_leftover.sql — what became of a batch's uneaten portions (exec
-- plan 0054, phase 3).
--
-- A planned meal is assumed bought, so every planned portion nobody ticked is
-- a leftover. The leftover itself is DERIVED — a batch's planned portions less
-- the shares its eaters ticked — and nothing is stored for it. What is stored
-- is the household's answer once the batch's days are over: of the portions
-- left, how many were kept, binned, or eaten after all (a forgotten tick).
-- Only `binned` is waste.
--
-- A cook session is derived and has no row, so the answer is keyed to the
-- batch's first covered meal: the `plan_entry` it opens with. A batch whose
-- first meal is later removed loses its answer with it, which is right — the
-- batch it described no longer exists.
--
-- Household-scoped like the rest: either member may answer, because the
-- question is about the pot, not a person. **No unique index on
-- `plan_entry_id`** (0011's doctrine): two offline answers must not 23505 on
-- upload. The app reads the most recently updated row.

create table batch_leftover (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  -- The batch's first covered meal.
  plan_entry_id uuid not null references plan_entry(id) on delete cascade,
  -- Portions, as the derived leftover counts them: fractional, never negative.
  kept          numeric not null default 0 constraint batch_leftover_kept_nonneg check (kept >= 0),
  binned        numeric not null default 0 constraint batch_leftover_binned_nonneg check (binned >= 0),
  eaten         numeric not null default 0 constraint batch_leftover_eaten_nonneg check (eaten >= 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

comment on table batch_leftover is
  'What became of a cook batch''s uneaten portions (exec plan 0054): kept, '
  'binned (waste) or eaten after all. Keyed to the batch''s first covered '
  'plan_entry, since a session is derived. The leftover itself is derived '
  'and never stored. No unique index: offline duplicates resolve on read, '
  'newest updated_at canonical.';

create index batch_leftover_entry_idx     on batch_leftover (plan_entry_id);
create index batch_leftover_household_idx on batch_leftover (household_id);

alter table batch_leftover enable row level security;

create policy batch_leftover_read on batch_leftover
  for select using (household_id = current_household_id());
create policy batch_leftover_write on batch_leftover
  for insert with check (household_id = current_household_id());
create policy batch_leftover_update on batch_leftover
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

grant select, insert, update on batch_leftover to authenticated;
grant all on batch_leftover to service_role;

alter publication powersync add table batch_leftover;
