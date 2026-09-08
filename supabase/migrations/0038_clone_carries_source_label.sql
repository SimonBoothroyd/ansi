-- 0038_clone_carries_source_label.sql — a cloned row keeps the name of the
-- food that filled it.
--
-- The flesh-out form's provenance card names the USDA food a row was filled
-- from, off the row's own `source_label` (0027). On a household onboarded
-- from a rebuilt cloud it printed only the FDC id — the fallback for a row
-- with no label — because the label was lost twice on the way:
--
-- 1. **The seed never wrote it.** `seed_prefill.sql` stamped
--    `source = 'usda_fdc:<id>'` with the macros and density, and 0027's
--    one-time label fill ran as a migration — which on a `db reset` runs
--    against an EMPTY table, before the seeds. The generated seed now writes
--    `source_label` beside the stamp (gen_seed.ts), the same rule 0027's
--    trigger holds for rows the server matches on its own.
-- 2. **The clone dropped it.** `ensure_onboarded()` copies a template row into
--    a new household by an explicit column list, and 0027 added its two
--    columns without extending that list. So even a labelled template row
--    arrived in the household nameless.
--
-- Two things happen here.
--
-- 1. **`ensure_onboarded()`** is re-created from 0023's body with one change:
--    the ingredient clone carries `source_label` and `source_score`. Nothing
--    else in the function moves. `source_edited` is deliberately NOT copied —
--    a fresh clone's numbers are the source's, and the fence starts false.
-- 2. **A fill of the missing labels**, for every household including the
--    template and soft-deleted rows: a row stamped `usda_fdc:<id>` with no
--    `source_label` takes `usda_food.description` for that id. It fills only
--    nulls — a label a person has since re-chosen is theirs (0027's rule) —
--    and is idempotent. `source_score` is left null: a curated seed link was
--    never a search, and the card says nothing about fit when there is no
--    score to read.
--
-- Row-preserving throughout (docs/cloud-setup.md §2c): one guarded UPDATE
-- that only ever fills a null. Reset-safe: on a fresh database the seeds run
-- after this file and write the label themselves, so the fill finds nothing.

-- ---------------------------------------------------------------------------
-- 1. ensure_onboarded(): 0023's body, the clone carrying the label and score.
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
    -- Run-once measure backfill (0011): heal a household that predates 0009
    -- (or whose operator cleared the marker for a template reseed). Gated on
    -- the marker, NOT the live count — a household that deliberately deleted
    -- its measures stays deleted. A household that already has measures is
    -- stamped without cloning (it was backfilled by other means).
    if exists (
      select 1 from household
      where id = hh and backfilled_at is null
    ) then
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
            basis_amount, sort_order, source)
          select hh, di.id, im.label, im.basis_amount, im.sort_order, im.source
          from ingredient_measure im
          join ingredient si on si.id = im.ingredient_id
            and si.household_id = src and si.deleted_at is null
            and si.source is distinct from 'manual'
          join ingredient di on di.household_id = hh
            and di.match_text = si.match_text and di.deleted_at is null
          where im.household_id = src and im.deleted_at is null;

          -- The curated default follows its measure, by label (0023).
          update ingredient di
             set default_measure_id = dm.id,
                 updated_at = now()
            from ingredient si
            join ingredient_measure sm on sm.id = si.default_measure_id
            join ingredient_measure dm on dm.household_id = hh
             and dm.deleted_at is null
             and lower(btrim(dm.label)) = lower(btrim(sm.label))
           where si.household_id = src and si.deleted_at is null
             and si.source is distinct from 'manual'
             and di.household_id = hh and di.deleted_at is null
             and di.match_text = si.match_text
             and dm.ingredient_id = di.id
             and di.default_measure_id is null;
        end if;
      end if;
      update household set backfilled_at = now() where id = hh;
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
  -- `backfilled_at` is stamped at creation: the clone below IS the measure
  -- backfill, so the run-once gate must never fire again for this household.
  if hh is null then
    insert into household (name, backfilled_at) values ('Home', now())
    returning id into hh;

    select id into src
    from household
    where is_template and deleted_at is null
    order by created_at
    limit 1;

    if src is not null then
      with cloned as (
        insert into ingredient (household_id, canonical_name, category,
          default_unit, density_g_per_ml, macros, macros_basis, status,
          source, source_label, source_score, match_text, allowed_units)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, macros_basis, status, source, source_label, source_score,
          match_text, allowed_units
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
      -- provenance (`source`) included, amounts in the basis unit (0012).
      insert into ingredient_measure (household_id, ingredient_id, label,
        basis_amount, sort_order, source)
      select hh, c.id, im.label, im.basis_amount, im.sort_order, im.source
      from ingredient_measure im
      join ingredient si on si.id = im.ingredient_id and si.household_id = src
      join cloned c on c.match_text = si.match_text
      where im.household_id = src and im.deleted_at is null;

      -- …and the curated default count measure follows its measure, BY LABEL
      -- (0023, seam D1). It cannot ride the ingredient clone above: the
      -- template's id names a TEMPLATE measure, which the own-measure trigger
      -- rightly refuses, and the new household's measures do not exist until
      -- the statement above has run. A household starts on the curated
      -- answer and owns it from that moment (the "Counts as" row).
      update ingredient di
         set default_measure_id = dm.id,
             updated_at = now()
        from ingredient si
        join ingredient_measure sm on sm.id = si.default_measure_id
        join ingredient_measure dm on dm.household_id = hh
         and dm.deleted_at is null
         and lower(btrim(dm.label)) = lower(btrim(sm.label))
       where si.household_id = src and si.deleted_at is null
         and si.source is distinct from 'manual'
         and di.household_id = hh and di.deleted_at is null
         and di.match_text = si.match_text
         and dm.ingredient_id = di.id
         and di.default_measure_id is null;
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

-- ---------------------------------------------------------------------------
-- 2. Fill the missing labels from the reference, nulls only.
-- ---------------------------------------------------------------------------
do $$
declare
  filled int;
begin
  with filled_rows as (
    update ingredient i
       set source_label = f.description,
           updated_at   = now()
      from usda_food f
     -- The stamp may carry a suffix — `usda_fdc:171413 — borrowed (olive
     -- oil, salad or cooking)` is how the seed marks macros taken from a
     -- neighbouring food — so the id is read out of it, not matched whole.
     where substring(i.source from '^usda_fdc:(\d+)')::int = f.fdc_id
       and i.source_label is null
    returning i.id
  )
  select count(*) into filled from filled_rows;
  raise notice '0038_clone_carries_source_label: % row(s) took their food''s name',
    filled;
end;
$$;
