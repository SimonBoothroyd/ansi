-- 0060_leftover.sql — cooked food in the fridge or the freezer, as the
-- household says it is (exec plan 0060, phase 1).
--
-- A cooked batch's leftover is DERIVED (0057, 0059): its planned portions less
-- the ticks, less the meals planned from it. A `leftover` row is what the
-- household says instead, and it wins: a corrected count, a dish moved to the
-- freezer, or food the app never saw (a pot cooked unplanned, a batch frozen
-- without a word, food given to them).
--
-- A row is a recipe or the household's own words, never both. A row that came
-- from a derived batch names it by the batch's key in `batch` (its first
-- covered meal: the key `batch_leftover.plan_entry_id` and
-- `plan_entry.leftover_of` name), and then replaces that batch's derived row.
-- A row added by hand has no `batch`.
--
-- Nothing clears itself: a row is shown until `gone_at`. A meal planned from a
-- row names it in `plan_entry.from_leftover`, and is eaten, never cooked,
-- bought or costed again: the cook plan, the shop and the week's cost read
-- `from_leftover is null` beside `leftover_of is null`. The row's portions
-- fall by that meal's demand on read.
--
-- Household-scoped like the rest: either member may write it. **No unique
-- index on `batch`** (0011's doctrine): two phones storing the same batch
-- offline must not 23505 on upload. The app reads the newest `updated_at` per
-- batch.

create table leftover (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  place         text not null
                constraint leftover_place check (place in ('fridge', 'freezer')),
  -- Exactly one of a recipe or the household's own words.
  recipe_id     uuid references recipe(id),
  label         text
                constraint leftover_label_nonblank check (label is null or btrim(label) <> ''),
  -- Portions, as the derived leftover counts them: fractional, never negative.
  portions      numeric not null
                constraint leftover_portions_nonneg check (portions >= 0),
  -- The day it was cooked (fridge) or went into the freezer.
  since         date not null,
  -- The derived batch this row replaces: its first covered meal. A hard
  -- delete of that meal leaves the row as one added by hand.
  batch         uuid references plan_entry(id) on delete set null,
  gone_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  constraint leftover_recipe_xor_label
    check (num_nonnulls(recipe_id, label) = 1)
);

comment on table leftover is
  'Cooked food in the fridge or the freezer, as the household says it is '
  '(exec plan 0060). A row with a batch replaces that cooked batch''s '
  'derived leftover; one without was added by hand. Shown until gone_at. '
  'No unique index: offline duplicates resolve on read, newest updated_at '
  'per batch canonical.';
comment on column leftover.place is
  'fridge or freezer. A fridge row is good until since plus the recipe''s '
  'keeps_for_days; a freezer row until since plus freezer_days (null = no '
  'limit). A row in words has no date.';
comment on column leftover.portions is
  'Portions in it as said, before the meals planned from it '
  '(plan_entry.from_leftover), which come off on read.';
comment on column leftover.since is
  'The day it was cooked (fridge) or frozen (freezer).';
comment on column leftover.batch is
  'The cooked batch (its first covered meal) this row replaces, the key '
  'batch_leftover.plan_entry_id and plan_entry.leftover_of name. Null on a '
  'row added by hand.';
comment on column leftover.gone_at is
  'When it was said to be gone: eaten, binned or given away. Null while it '
  'is still there; nothing sets it but a person.';

create index leftover_household_idx on leftover (household_id);
create index leftover_batch_idx     on leftover (batch) where batch is not null;

alter table leftover enable row level security;

create policy leftover_read on leftover
  for select using (household_id = current_household_id());
create policy leftover_write on leftover
  for insert with check (household_id = current_household_id());
create policy leftover_update on leftover
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

grant select, insert, update on leftover to authenticated;
grant all on leftover to service_role;

alter publication powersync add table leftover;

-- A meal planned from a stored leftover. `leftover_of` stays, for a meal
-- planned from a derived batch before this table existed; a meal names one or
-- the other, never both.
alter table plan_entry
  add column from_leftover uuid references leftover(id) on delete set null,
  add constraint plan_entry_from_leftover_is_a_recipe
    check (from_leftover is null or recipe_id is not null),
  add constraint plan_entry_one_leftover
    check (num_nonnulls(leftover_of, from_leftover) <= 1);

comment on column plan_entry.from_leftover is
  'The fridge or freezer row (leftover) this recipe meal is eaten from. Null '
  'on every meal that is cooked, and on one that names leftover_of. A meal '
  'from a leftover is never cooked, bought or costed again (exec plan 0060).';

create index plan_entry_from_leftover_idx on plan_entry (from_leftover)
  where from_leftover is not null;
