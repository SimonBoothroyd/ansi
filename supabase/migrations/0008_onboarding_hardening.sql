-- 0008_onboarding_hardening.sql — race-safe onboarding + template vocab clone.
--
-- Hardens the step-7 server half (0007_sync.sql) after a security review.
-- Three confirmed issues, one migration:
--
--   1. RACE — `ensure_onboarded()` had no locking. Two concurrent onboards
--      could both count one member and both take the last seat (a three-member
--      "two-person" household), or one user's two devices could land in two
--      different households. The function now serialises every onboard on a
--      transaction-scoped advisory lock.
--
--   2. NON-DETERMINISM — `current_household_id()` (0001) and the membership
--      lookup inside `add_household_claim` (0007) both picked a membership
--      with a bare `limit 1` and no `order by`; nothing guaranteed the two
--      resolved the *same* membership. Both now order by `created_at`, so the
--      oldest live membership always wins, consistently, everywhere.
--
--   3. CLONE PRIVACY + EMPTY CLOUD — the vocab clone copied from the
--      "richest" household, which (a) leaked another household's private
--      typed-in data (`source = 'manual'` ingredients, `'import_correction'`
--      aliases) into every new household, and (b) had nothing to clone on an
--      empty cloud DB (tracked tech debt). Replaced with a template model:
--      `household.is_template` marks a curated, member-less vocab template
--      (the seeded dev "Home"; cloud seeds its own). `ensure_onboarded`
--      clones ONLY from a template — excluding manual rows and import
--      corrections — and cleanly no-ops (empty vocab) when no template
--      exists. Template households are never joinable, so they stay pristine.
--
-- Template exposure check (reviewed): a template household has no members, so
--   * RLS never exposes it — every policy resolves through
--     `current_household_id()`, which only ever returns a household the
--     caller is a member of;
--   * the PowerSync bucket (docker/powersync.yaml) is parameterised on the
--     JWT `household_id` claim, which `add_household_claim` only injects for
--     actual members — template rows are replicated into the service but
--     never land in any device's bucket.

-- ---------------------------------------------------------------------------
-- Template flag. The seeded dev household ("Home", also flagged in seed.sql
-- for fresh resets) becomes the template on already-migrated databases.
-- ---------------------------------------------------------------------------
alter table household
  add column if not exists is_template boolean not null default false;

update household set is_template = true
where id = '00000000-0000-0000-0000-0000000000aa';

-- A member may rename or soft-delete their own household, but must never be
-- able to flip is_template — a self-marked "template" household would become
-- the clone source for future onboarders (data poisoning / privacy leak).
-- Tighten the 0001 table-level UPDATE grant to the client-editable columns.
revoke update on household from authenticated;
grant update (name, updated_at, deleted_at) on household to authenticated;

-- ---------------------------------------------------------------------------
-- current_household_id() — deterministic membership resolution (0001 + order).
-- ---------------------------------------------------------------------------
create or replace function current_household_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select household_id
  from household_member
  where auth_user_id = auth.uid()
    and deleted_at is null
  order by created_at
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- ensure_onboarded() — advisory lock + template-only clone (0007 + hardening).
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
  -- from, and must stay pristine and member-less (see header — memberless is
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
      )
      -- Aliases follow their ingredient by matching canonical match_text
      -- within the clone (source→clone id map keyed on the unique
      -- match_text). Aliases of excluded (manual) ingredients drop out of the
      -- join naturally; import corrections are excluded explicitly.
      insert into ingredient_alias (household_id, ingredient_id, alias_text,
        match_text, source)
      select hh, c.id, a.alias_text, a.match_text, a.source
      from ingredient_alias a
      join ingredient si on si.id = a.ingredient_id and si.household_id = src
      join cloned c on c.match_text = si.match_text
      where a.deleted_at is null
        and a.source <> 'import_correction';
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

-- ---------------------------------------------------------------------------
-- add_household_claim() — deterministic membership resolution (0007 + order).
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
  order by created_at
  limit 1;

  if hh is not null then
    claims := jsonb_set(claims, '{household_id}', to_jsonb(hh::text));
    event := jsonb_set(event, '{claims}', claims);
  end if;

  return event;
end;
$$;

-- CREATE OR REPLACE preserves the existing grants on all three functions
-- (0001/0007): ensure_onboarded → authenticated only; add_household_claim →
-- supabase_auth_admin only; current_household_id keeps its defaults.
