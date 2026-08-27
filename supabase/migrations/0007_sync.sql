-- 0007_sync.sql — the sync layer's server half (roadmap step 7).
--
-- Steps 1–6 shipped offline-only; this migration lands what real sync needs on
-- the server: a way for a freshly signed-in user to get a household + member
-- (onboarding), and the JWT `household_id` claim the PowerSync sync rules read
-- (docker/powersync.yaml) to scope a device to its household. The client half
-- (connector, .connect(), auth gate) lives in app/lib/core/sync.
--
-- Onboarding is deliberately simple and destructive-friendly — dev data is
-- throwaway. v1 is a two-person household: a new user JOINS an existing
-- household with room, else CREATES one (cloning the starter vocab). No invite
-- flow yet (spec §8 open question).

-- Members carry a stable display order (the client already reads sort_order for
-- the eaters avatars; the server table never had the column — align them).
alter table household_member
  add column if not exists sort_order int not null default 0;

-- ---------------------------------------------------------------------------
-- Onboarding. Called by the app over RPC right after sign-in, before .connect().
-- SECURITY DEFINER so it can write household/household_member (which have no
-- client INSERT policy — onboarding is a privileged operation). Idempotent:
-- a user who already belongs to a live household is a no-op.
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

  -- Already onboarded?
  select household_id into hh
  from household_member
  where auth_user_id = uid and deleted_at is null
  limit 1;
  if hh is not null then
    return hh;
  end if;

  -- Join an existing household that still has room (v1 = two people)…
  select h.id into hh
  from household h
  where h.deleted_at is null
    and (
      select count(*) from household_member m
      where m.household_id = h.id and m.deleted_at is null
    ) < 2
  order by h.created_at
  limit 1;

  -- …otherwise create a fresh one and clone the starter vocab into it (from the
  -- richest existing household — the seeded "Home" locally; a no-op on a truly
  -- empty database, which is the documented cloud-cutover gap: cloud needs a
  -- vocab template to clone from).
  if hh is null then
    insert into household (name) values ('Home') returning id into hh;

    select household_id into src
    from ingredient
    where deleted_at is null
    group by household_id
    order by count(*) desc
    limit 1;

    if src is not null then
      with cloned as (
        insert into ingredient (household_id, canonical_name, category,
          default_unit, density_g_per_ml, macros, status, source, match_text)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, status, source, match_text
        from ingredient
        where household_id = src and deleted_at is null
        returning id, match_text
      )
      -- Aliases follow their ingredient by matching canonical match_text within
      -- the clone (source→clone id map keyed on the unique match_text).
      insert into ingredient_alias (household_id, ingredient_id, alias_text,
        match_text, source)
      select hh, c.id, a.alias_text, a.match_text, a.source
      from ingredient_alias a
      join ingredient si on si.id = a.ingredient_id and si.household_id = src
      join cloned c on c.match_text = si.match_text
      where a.deleted_at is null;
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

revoke execute on function ensure_onboarded() from public, anon;
grant execute on function ensure_onboarded() to authenticated;

-- ---------------------------------------------------------------------------
-- Custom access-token hook: inject the caller's household_id into the JWT so
-- PowerSync sync rules can scope buckets with `request.jwt() ->> 'household_id'`
-- (docker/powersync.yaml). Registered in supabase/config.toml. Runs as
-- supabase_auth_admin, so it needs its own read path to household_member.
-- ---------------------------------------------------------------------------
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
begin
  select household_id into hh
  from household_member
  where auth_user_id = (event ->> 'user_id')::uuid and deleted_at is null
  limit 1;

  if hh is not null then
    claims := jsonb_set(claims, '{household_id}', to_jsonb(hh::text));
    event := jsonb_set(event, '{claims}', claims);
  end if;

  return event;
end;
$$;

-- The hook is invoked by GoTrue as supabase_auth_admin; lock it to that role.
grant usage on schema public to supabase_auth_admin;
grant execute on function add_household_claim(jsonb) to supabase_auth_admin;
revoke execute on function add_household_claim(jsonb) from public, anon, authenticated;
