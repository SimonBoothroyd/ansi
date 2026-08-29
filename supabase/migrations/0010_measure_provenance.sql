-- 0010_measure_provenance.sql — measure weight provenance + onboarding
-- backfill (step 7.6 follow-up).
--
-- Three concerns, all on `ingredient_measure`:
--
-- 1. **`source`** — where a gram weight comes from, so "1 potato, medium =
--    213 g" is auditable (invariant 3: the count↔mass bridge is a stored,
--    SOURCED weight):
--      * `usda_fdc:<fdc_id> (<portion>)`             — pipeline-derived from a
--        USDA FDC food_portion row of the ingredient's own linked food;
--      * `usda_fdc:<fdc_id> (<portion>) — borrowed`  — a variety whose own FDC
--        food lacks usable portions, borrowing a representative food's
--        portion (explicit borrow map in the seed pipeline);
--      * `seed:typical`                              — curated hand row where
--        FDC genuinely has nothing (kept deliberately rare);
--      * `manual`                                    — user-authored (the 7.7
--        measure editor writes this);
--      * null                                        — rows predating this
--        column.
--
-- 2. **Live-label uniqueness** — `(ingredient_id, label)` unique among
--    non-deleted rows, which makes the measures seed idempotent
--    (`on conflict do nothing`) and blocks accidental duplicate labels from
--    any writer. Partial (live rows only) so a soft-deleted label can be
--    re-created, and a tombstone never blocks sync.
--
-- 3. **Backfill for already-onboarded households** — 0009 extended the clone
--    leg of `ensure_onboarded()`, so households onboarded BEFORE it never
--    received measures (the early-exit path returns before any cloning).
--    The function below heals them: on the already-onboarded path, a
--    household with zero LIVE measures gets the template's measures cloned
--    in (same match_text join, same manual-ingredient exclusion as the
--    onboarding clone). The session controller re-runs the RPC on every
--    sign-in, so existing households heal on their next sign-in — and the
--    same leg doubles as the refresh path after an operator soft-deletes a
--    household's measures to roll out a reseeded template (cloud-setup §2).
--    Households that HAVE live measures are never touched (no dupes, no
--    clobbering user edits).

alter table ingredient_measure add column source text;

comment on column ingredient_measure.source is
  'Weight provenance: usda_fdc:<fdc_id> (<portion>) [— borrowed], '
  'seed:typical, or manual. Null on rows predating 0010.';

-- One live label per ingredient. Enables `on conflict do nothing` in the
-- measures seed (idempotent reseeds) and guards duplicate labels generally.
create unique index measure_live_label_uq
  on ingredient_measure (ingredient_id, label)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- ensure_onboarded() — 0009's body plus:
--   * the already-onboarded path backfills measures into a household that has
--     none (see header);
--   * the measure-clone legs carry `source` through;
--   * the clone leg pins `im.household_id = src` explicitly (0009 reached the
--     template's measures only via the ingredient join — correct, but the
--     direct filter is cheaper and belt-and-braces against a cross-household
--     row ever pointing at a template ingredient).
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
  -- The measure backfill below runs under the same lock, so two devices
  -- signing in at once can't double-clone.
  perform pg_advisory_xact_lock(hashtext('ensure_onboarded'));

  -- Already onboarded? Ordered like current_household_id(), so every path
  -- resolves the same membership.
  select household_id into hh
  from household_member
  where auth_user_id = uid and deleted_at is null
  order by created_at
  limit 1;
  if hh is not null then
    -- Heal a household that predates 0009 (or whose measures were cleared
    -- for a template reseed): zero live measures + a template → clone the
    -- template's measures in, joined by ingredient match_text, excluding
    -- measures of `manual` template ingredients exactly like the onboarding
    -- clone. A household with ANY live measure is left alone.
    if not exists (
      select 1 from ingredient_measure im
      where im.household_id = hh and im.deleted_at is null
    ) then
      select id into src
      from household
      where is_template and deleted_at is null
      order by created_at
      limit 1;

      if src is not null then
        insert into ingredient_measure (household_id, ingredient_id, label,
          grams, sort_order, source)
        select hh, di.id, im.label, im.grams, im.sort_order, im.source
        from ingredient_measure im
        join ingredient si on si.id = im.ingredient_id
          and si.household_id = src and si.deleted_at is null
          and si.source is distinct from 'manual'
        join ingredient di on di.household_id = hh
          and di.match_text = si.match_text and di.deleted_at is null
        where im.household_id = src and im.deleted_at is null;
      end if;
    end if;
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
      -- starter "potato, medium = 213 g" vocabulary arrives with the vocab —
      -- provenance (`source`) included.
      insert into ingredient_measure (household_id, ingredient_id, label,
        grams, sort_order, source)
      select hh, c.id, im.label, im.grams, im.sort_order, im.source
      from ingredient_measure im
      join ingredient si on si.id = im.ingredient_id and si.household_id = src
      join cloned c on c.match_text = si.match_text
      where im.household_id = src and im.deleted_at is null;
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
