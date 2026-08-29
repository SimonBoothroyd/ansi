-- 0011_picker_uplift.sql — picker-uplift data model (roadmap step 7.7,
-- exec plan 0011).
--
-- Four concerns:
--
-- 1. **`recipe.favorite`** — the curated shortlist behind the recipe picker's
--    Favorites tab. A flag, not a table: favorites are household-shared (the
--    design board's tab is one list for the household), and the recipe row
--    already syncs. Writable through the existing recipe RLS policies.
--
-- 2. **`household.backfilled_at`** — a run-once gate for the template-measure
--    backfill. 0010's gate was "zero LIVE measures", which re-clones the
--    template set into any measure-less household — correct while nothing
--    could delete measures, but 7.7's measure editor ships deletion, and a
--    household that deliberately removed its last measure must NOT have it
--    resurrected at next sign-in. The marker makes the backfill exactly-once:
--    stamped when the backfill (or the onboarding clone, which does the same
--    job) runs, checked instead of the live count. Server-only: the client
--    never reads it (it rides the `select *` sync rule like `is_template`
--    does, and the client view simply doesn't declare it).
--    Operator note (docs/cloud-setup.md): rolling a reseeded template out to
--    an existing household now needs `backfilled_at = null` cleared alongside
--    the measure soft-delete.
--
-- 3. **Drop `measure_live_label_uq`** — 0010's live `(ingredient_id, label)`
--    unique index is the offline-dupe-fails-upload pattern this repo
--    deliberately rejected for shopping entries: two offline devices adding
--    the same label 23505 on upload and the connector drops the whole crud
--    transaction. Inert while only server-side paths wrote measures; 7.7's
--    editor makes it live. Doctrine (decision log, plan 0011): no unique
--    index — duplicate labels merge deterministically on READ (oldest row
--    canonical), an offline duplicate must never fail upload. The measures
--    seed switches from `on conflict do nothing` (which targeted this index)
--    to a `where not exists` guard, same idempotency.
--
-- 4. **`ingredient.macros_basis`** — macros are stored WITH the basis the
--    label read them in (per-100 g or per-100 ml). Liquid labels read per
--    100 ml and densities are sparse, so conversion-at-entry can't be the
--    design (plan 0011 notes): a line whose unit family matches the basis
--    computes directly; cross-basis bridges only via density; otherwise the
--    recipe's macros render honestly `incomplete`. USDA prefill rows are
--    per-100 g — the default covers every existing row.

alter table recipe add column favorite boolean not null default false;
comment on column recipe.favorite is
  'Household-shared curated shortlist — the recipe picker''s Favorites tab '
  '(step 7.7).';

alter table household add column backfilled_at timestamptz;
comment on column household.backfilled_at is
  'When the template-measure backfill (or the onboarding clone) ran for this '
  'household. Run-once gate (0011): null means "never backfilled" — the old '
  'zero-live-measures gate would resurrect deliberately deleted measures. '
  'Server-only; the client schema does not declare it.';

-- Households that already carry live measures were backfilled (or onboarded
-- post-0009): stamp them so the new gate never re-clones over user edits or
-- deletions. Measure-less non-template households stay null and heal exactly
-- once on their next sign-in, as before.
update household h
set backfilled_at = now()
where h.deleted_at is null
  and not h.is_template
  and exists (
    select 1 from ingredient_measure im
    where im.household_id = h.id and im.deleted_at is null
  );

drop index measure_live_label_uq;

alter table ingredient add column macros_basis text not null default 'g'
  check (macros_basis in ('g', 'ml'));
comment on column ingredient.macros_basis is
  'The per-100 basis `macros` was entered in: ''g'' (per 100 g — every USDA '
  'prefill row) or ''ml'' (per 100 ml, liquid labels). Stored, never '
  'converted at entry (0011).';

-- ---------------------------------------------------------------------------
-- ensure_onboarded() — 0010's body with:
--   * the already-onboarded backfill leg gated on `backfilled_at is null`
--     instead of zero live measures, stamping the marker after it runs (and
--     stamping without cloning when measures are already present — belt and
--     braces against a pre-migration race);
--   * the create path stamping `backfilled_at` at creation (the onboarding
--     clone IS the backfill for a fresh household);
--   * both ingredient clone legs carrying `macros_basis` through.
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
          source, match_text)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, macros_basis, status, source, match_text
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
