-- 0061_cooking.sql — a cooking is remembered, not re-derived (exec plan 0062).
--
-- A `cooking` is one pot, born at the first tick on any of its meals or the
-- first pick from it, with a fixed id. Meals link to it through
-- `plan_entry.cooking`. `made` is fixed at the first tick (null = the live sum
-- of its linked meals). A `cooking_change` row is one correction (a stepper
-- commit, Freeze or Froze it); Undo soft-deletes it. A table, not a column: a
-- PowerSync PATCH sends a whole value, so one phone would erase the other.
--
-- **The previous release** never reads these. `leftover`, `leftover_of`,
-- `from_leftover` and `batch_leftover` stay, read-only for the new app, until
-- a later release drops them (moving `from_leftover`'s key would wedge an old
-- build's queue). The conversion at the foot copies them over once.
-- No unique index beyond the ids (0011's doctrine): two phones birth one
-- cooking under one id, so the upload is idempotent.

create table cooking (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  -- Exactly one of a recipe or the household's own words.
  recipe_id     uuid references recipe(id),
  label         text
                constraint cooking_label_nonblank check (label is null or btrim(label) <> ''),
  -- Portions made: fixed at the first tick; null while it is the live sum.
  made          numeric
                constraint cooking_made_nonneg check (made is null or made >= 0),
  -- For food said by hand (added, or carried over from `leftover`): where it
  -- went and the day it was cooked. Null on a cooking dated by its ticks.
  place         text
                constraint cooking_place check (place is null or place in ('fridge', 'freezer')),
  since         date,
  gone_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  constraint cooking_recipe_xor_label
    check (num_nonnulls(recipe_id, label) = 1),
  constraint cooking_place_with_since
    check ((place is null) = (since is null)),
  -- Words have no meals to date them: they are always said by hand.
  constraint cooking_label_said
    check (label is null or since is not null)
);

comment on table cooking is
  'One cooked pot (exec plan 0062): born at the first tick on a meal of its '
  'group, or the first pick from it; its id never changes. Meals link to it '
  'through plan_entry.cooking. What is left = made + its cooking_change rows '
  '- what its linked meals take; derived on read.';
comment on column cooking.made is
  'Portions made, fixed at the first tick. Null while still the live sum of '
  'its linked meals'' portions.';
comment on column cooking.place is
  'fridge or freezer, for food said by hand (with since). Null on a cooking '
  'dated by its ticks: its cook day is the earliest ticked day.';
comment on column cooking.since is
  'The day food said by hand was cooked; its dates count from it.';
comment on column cooking.gone_at is
  'When it was said to have gone off (Remove gone off): final, a later untick '
  'does not bring it back. Null while it is still there.';

create index cooking_household_idx on cooking (household_id);

alter table cooking enable row level security;

create policy cooking_read on cooking
  for select using (household_id = current_household_id());
create policy cooking_write on cooking
  for insert with check (household_id = current_household_id());
create policy cooking_update on cooking
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

grant select, insert, update on cooking to authenticated;
grant all on cooking to service_role;

alter publication powersync add table cooking;

create table cooking_change (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  cooking_id    uuid not null references cooking(id) on delete cascade,
  -- Portions added (or, negative, taken) on each shelf.
  fridge        numeric not null default 0,
  freezer       numeric not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

comment on table cooking_change is
  'One correction to a cooking (exec plan 0062): a stepper commit writes the '
  'difference, Freeze or Froze it writes (-n fridge, +n freezer). Undo sets '
  'deleted_at. Two phones correcting offline both apply.';

create index cooking_change_cooking_idx   on cooking_change (cooking_id);
create index cooking_change_household_idx on cooking_change (household_id);

alter table cooking_change enable row level security;

create policy cooking_change_read on cooking_change
  for select using (household_id = current_household_id());
create policy cooking_change_write on cooking_change
  for insert with check (household_id = current_household_id());
create policy cooking_change_update on cooking_change
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

grant select, insert, update on cooking_change to authenticated;
grant all on cooking_change to service_role;

alter publication powersync add table cooking_change;

alter table plan_entry
  add column cooking uuid references cooking(id) on delete set null,
  add constraint plan_entry_cooking_is_a_recipe
    check (cooking is null or recipe_id is not null);

comment on column plan_entry.cooking is
  'The cooking (pot) this recipe meal is cooked in or eaten from (exec plan '
  '0062). Null before its group''s first tick or pick: such meals group by '
  'shelf life within their week. A cooking is bought in the week of its '
  'earliest linked meal; a linked meal in any other week buys nothing.';

create index plan_entry_cooking_idx on plan_entry (cooking)
  where cooking is not null;

-- ---------------------------------------------------------------------------
-- The conversion from 0060, as a function so it can be proven on rows the
-- tests seed. It only adds: a cooking already there and a meal already linked
-- are left as they are, so a second call changes nothing.
-- ---------------------------------------------------------------------------

create function cooking_from_leftover()
returns void
language sql
set search_path = public
as $$
  -- Each stored leftover becomes a cooking with the same id, its count as
  -- said and its place and date: food said by hand.
  insert into cooking (id, household_id, recipe_id, label, made, place, since,
                       gone_at, created_at, updated_at, deleted_at)
  select id, household_id, recipe_id, label, portions, place, since,
         gone_at, created_at, updated_at, deleted_at
  from leftover
  on conflict (id) do nothing;

  -- A batch some meal was planned from (`leftover_of`) that no live row
  -- names: a cooking whose id is that batch's meal, still the live sum.
  insert into cooking (id, household_id, recipe_id)
  select distinct x.id, x.household_id, x.recipe_id
  from plan_entry x
  where x.recipe_id is not null
    and exists (select 1 from plan_entry p where p.leftover_of = x.id)
    and not exists (
      select 1 from leftover lo where lo.batch = x.id and lo.deleted_at is null
    )
  on conflict (id) do nothing;

  -- A meal planned from a stored row eats from that row's cooking.
  update plan_entry set cooking = from_leftover
  where from_leftover is not null and cooking is null;

  -- A meal planned from a batch eats from the newest live row naming that
  -- batch, else from the batch's own cooking.
  update plan_entry pe set cooking = coalesce(
    (select lo.id from leftover lo
     where lo.batch = pe.leftover_of and lo.deleted_at is null
     order by lo.updated_at desc, lo.id desc limit 1),
    pe.leftover_of)
  where pe.leftover_of is not null and pe.cooking is null;
$$;

comment on function cooking_from_leftover() is
  'Copies 0060''s leftover rows and leftover_of/from_leftover pointers into '
  'cooking and plan_entry.cooking (exec plan 0062). Only adds; safe to run '
  'again. Dropped with the old tables.';

revoke all on function cooking_from_leftover() from public, anon, authenticated;

select cooking_from_leftover();
