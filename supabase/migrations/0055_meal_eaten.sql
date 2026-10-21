-- 0055_meal_eaten.sql — who said they ate a planned meal (exec plan 0054,
-- phase 1).
--
-- The Week has only ever known what was PLANNED. A `meal_eaten` row is one
-- member saying "I ate this", at a time they can correct: the tick's time
-- until they change it. An untick soft-deletes the row. Nothing about eating
-- edits the plan — `plan_entry.eaters`, `portions` and the batch stay what was
-- cooked and bought for, so the cook plan and the shop never move when a
-- meal is ticked.
--
-- **A member writes only their own rows.** Each phone ticks for the person
-- signed in on it and nobody else, and the server holds that line, not just
-- the UI: the write policies compare `member_id` with `current_member_id()`.
-- Reads stay household-wide, so the Week can show the partner's tick.
--
-- A separate table rather than a column on `plan_entry`: two phones ticking
-- the same meal would otherwise race on one jsonb, and the later upload would
-- erase the earlier tick.
--
-- **No unique index on (plan_entry_id, member_id)** — 0011's doctrine, as for
-- `recipe_measure` (0048): two offline ticks of the same meal on two devices
-- must not 23505 on upload, which drops the whole crud transaction. The app
-- merges duplicates on read, oldest row canonical.
--
-- The app has to know which member is signed in, and `auth_user_id` stays off
-- the wire (0007). So the access-token hook now also injects the caller's own
-- `member_id` claim, from the same membership `household_id` comes from: the
-- phone learns its own member and nobody else's account id.

-- ---------------------------------------------------------------------------
-- 1. current_member_id() — the caller's own membership, as RLS sees it.
-- ---------------------------------------------------------------------------

-- The same row current_household_id() (0008) resolves, so the two can never
-- name different memberships: oldest live membership first.
create or replace function current_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from household_member
  where auth_user_id = auth.uid()
    and deleted_at is null
  order by created_at
  limit 1;
$$;

comment on function current_member_id() is
  'The caller''s own household_member id: the oldest live membership, the '
  'same one current_household_id() resolves. Policies that narrow a write to '
  'the member themselves (meal_eaten) read it.';

-- ---------------------------------------------------------------------------
-- 2. The access-token hook gains `member_id` beside `household_id`.
-- ---------------------------------------------------------------------------

-- 0008's body, with the membership read once and both claims set from it.
-- CREATE OR REPLACE keeps 0007's grants: executable by supabase_auth_admin
-- only.
create or replace function add_household_claim(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  claims jsonb := event -> 'claims';
  hh     uuid;
  mem    uuid;
begin
  select household_id, id into hh, mem
  from household_member
  where auth_user_id = (event ->> 'user_id')::uuid and deleted_at is null
  order by created_at
  limit 1;

  if hh is not null then
    claims := jsonb_set(claims, '{household_id}', to_jsonb(hh::text));
    claims := jsonb_set(claims, '{member_id}', to_jsonb(mem::text));
    event := jsonb_set(event, '{claims}', claims);
  end if;

  return event;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The table.
-- ---------------------------------------------------------------------------

create table meal_eaten (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  -- The planned meal that was eaten. Cascades for a hard delete; a soft
  -- delete of the meal needs none, since every read joins
  -- `plan_entry.deleted_at is null` — so undoing a removal brings the ticks
  -- back with it.
  plan_entry_id uuid not null references plan_entry(id) on delete cascade,
  -- Who ate it. Only that member may write the row (policies below).
  member_id     uuid not null references household_member(id),
  -- When they ate it: the moment they ticked, until they say otherwise.
  eaten_at      timestamptz not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz           -- unticked
);

comment on table meal_eaten is
  'A member saying they ate a planned meal (exec plan 0054). Writable only by '
  'that member (current_member_id()); readable by the household. An untick '
  'sets deleted_at. Ticking never edits the plan. No unique index on '
  '(plan_entry_id, member_id): offline duplicates merge on read, oldest row '
  'canonical (0011''s doctrine).';

comment on column meal_eaten.eaten_at is
  'When the member ate the meal: the tick''s time unless they changed it.';

create index meal_eaten_entry_idx     on meal_eaten (plan_entry_id);
create index meal_eaten_household_idx on meal_eaten (household_id);

alter table meal_eaten enable row level security;

create policy meal_eaten_read on meal_eaten
  for select using (household_id = current_household_id());
create policy meal_eaten_write on meal_eaten
  for insert with check (
    household_id = current_household_id()
    and member_id = current_member_id()
  );
create policy meal_eaten_update on meal_eaten
  for update using (
    household_id = current_household_id()
    and member_id = current_member_id()
  )
  with check (
    household_id = current_household_id()
    and member_id = current_member_id()
  );

grant select, insert, update on meal_eaten to authenticated;
grant all on meal_eaten to service_role;

alter publication powersync add table meal_eaten;
