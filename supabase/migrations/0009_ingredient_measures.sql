-- 0009_ingredient_measures.sql — named ingredient measures (roadmap step 7.6).
--
-- Count foods need MEASURES, not densities: a liquid density can't describe a
-- potato, and only a handful of vocab rows carry one. An `ingredient_measure`
-- names a real-world unit of an ingredient and pins its mass — "potato, large
-- = 299 g", "can (400 ml) = 400 g", "clove = 5 g" — so count-quantified lines
-- can join mass totals honestly (invariant 3: the bridge is a stored, sourced
-- weight, never an invented number).
--
-- Measures are PER-HOUSEHOLD rows (synced, user-editable), not global
-- reference data: households disagree about what "1 portion" is, and import
-- (step 8) will create them from labels. Template measures clone with the
-- vocab at onboarding (ensure_onboarded below).
--
-- Line items and manual shopping contributions reference a measure via a
-- nullable `measure_id` FK — NOT a namespaced unit string — keeping the unit
-- catalog closed and the column self-documenting. A measure-quantified row
-- stores `unit = 'piece'` alongside the FK: if the measure row is ever
-- missing (deleted, not yet synced), the line degrades to an honest count
-- ("2 piece") instead of fabricating grams.

create table ingredient_measure (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  ingredient_id uuid not null references ingredient(id) on delete cascade,
  label         text not null,        -- "potato, large", "can (400 ml)", "clove"
  grams         numeric not null check (grams > 0),
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz           -- soft-delete tombstone (spec §3)
);

-- Foreign-key lookup indexes.
create index measure_ingredient_idx on ingredient_measure (ingredient_id);
create index measure_household_idx  on ingredient_measure (household_id);

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (same shape as 0002..0006).
alter table ingredient_measure enable row level security;

create policy measure_read on ingredient_measure
  for select using (household_id = current_household_id());
create policy measure_write on ingredient_measure
  for insert with check (household_id = current_household_id());
create policy measure_update on ingredient_measure
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Table privileges mirror the policies (no DELETE — soft delete). service_role
-- (edge functions, seed) bypasses RLS.
grant select, insert, update on ingredient_measure to authenticated;
grant all on ingredient_measure to service_role;

-- Sync the measures down with the household's vocab (docker/powersync.yaml +
-- the cloud streams file gain the matching rule in this change).
alter publication powersync add table ingredient_measure;

-- A recipe line / manual top-up quantified in a measure ("2 × potato, large").
-- Nullable: null means the row is quantified in a plain units.dart unit.
alter table recipe_line_item
  add column measure_id uuid references ingredient_measure(id);
alter table shopping_list_contribution
  add column measure_id uuid references ingredient_measure(id);

create index line_item_measure_idx
  on recipe_line_item (measure_id);
create index shopping_list_contribution_measure_idx
  on shopping_list_contribution (measure_id);

-- ---------------------------------------------------------------------------
-- ensure_onboarded() — 0008's advisory-locked template clone, extended so
-- template measures clone with the vocab. Body identical to 0008 except the
-- final `with` chain gains a measure-clone leg (keyed on the same
-- match_text map as aliases; measures of excluded `manual` ingredients drop
-- out of the join naturally).
-- ---------------------------------------------------------------------------
create or replace function ensure_onboarded()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid       uuid := auth.uid();
  hh        uuid;
  member_no int;
  src       uuid;
begin
  if uid is null then
    raise exception 'ensure_onboarded() requires an authenticated caller';
  end if;

  -- Serialise concurrent onboards (two users racing for the last seat, or one
  -- user's two devices onboarding at once). Transaction-scoped: released
  -- automatically at commit/rollback, re-entrant within this transaction.
  perform pg_advisory_xact_lock(hashtext('ensure_onboarded'));

  -- Already onboarded? Ordered like current_household_id(), so every path
  -- resolves the same membership.
  select household_id into hh
  from household_member
  where auth_user_id = uid and deleted_at is null
  order by created_at
  limit 1;
  if hh is not null then
    return hh;
  end if;

  -- Join an existing household that still has room (v1 = two people).
  -- Template households are never joinable: they exist only to be cloned
  -- from, and must stay pristine and member-less (see 0008 — memberless is
  -- also what keeps their rows out of RLS reads and sync buckets).
  select h.id into hh
  from household h
  where h.deleted_at is null
    and not h.is_template
    and (
      select count(*) from household_member m
      where m.household_id = h.id and m.deleted_at is null
    ) < 2
  order by h.created_at
  limit 1;

  -- …otherwise create a fresh one and clone the starter vocab from the
  -- template household (the seeded "Home" locally; cloud seeds its own).
  -- Only curated template content is copied: `source = 'manual'` ingredients
  -- and `'import_correction'` aliases are a household's private typed-in
  -- data and never leave it. No template → clean no-op (empty vocab).
  if hh is null then
    insert into household (name) values ('Home') returning id into hh;

    select id into src
    from household
    where is_template and deleted_at is null
    order by created_at
    limit 1;

    if src is not null then
      with cloned as (
        insert into ingredient (household_id, canonical_name, category,
          default_unit, density_g_per_ml, macros, status, source, match_text)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, status, source, match_text
        from ingredient
        where household_id = src and deleted_at is null
          and source is distinct from 'manual'
        returning id, match_text
      ),
      -- Aliases follow their ingredient by matching canonical match_text
      -- within the clone (source→clone id map keyed on the unique
      -- match_text). Aliases of excluded (manual) ingredients drop out of the
      -- join naturally; import corrections are excluded explicitly.
      alias_clone as (
        insert into ingredient_alias (household_id, ingredient_id, alias_text,
          match_text, source)
        select hh, c.id, a.alias_text, a.match_text, a.source
        from ingredient_alias a
        join ingredient si on si.id = a.ingredient_id and si.household_id = src
        join cloned c on c.match_text = si.match_text
        where a.deleted_at is null
          and a.source <> 'import_correction'
      )
      -- Measures follow their ingredient by the same match_text map, so the
      -- starter "potato, large = 299 g" vocabulary arrives with the vocab.
      insert into ingredient_measure (household_id, ingredient_id, label,
        grams, sort_order)
      select hh, c.id, im.label, im.grams, im.sort_order
      from ingredient_measure im
      join ingredient si on si.id = im.ingredient_id and si.household_id = src
      join cloned c on c.match_text = si.match_text
      where im.deleted_at is null;
    end if;
  end if;

  select count(*) into member_no
  from household_member
  where household_id = hh and deleted_at is null;

  insert into household_member (household_id, display_name, auth_user_id, sort_order)
  values (
    hh,
    coalesce(
      auth.jwt() -> 'user_metadata' ->> 'full_name',
      split_part(auth.jwt() ->> 'email', '@', 1),
      'Member'
    ),
    uid,
    member_no
  );

  return hh;
end;
$$;

-- CREATE OR REPLACE preserves the existing grant (0007/0008):
-- ensure_onboarded → authenticated only.
