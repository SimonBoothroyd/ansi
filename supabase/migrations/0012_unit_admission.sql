-- 0012_unit_admission.sql — ADR-0008: units are admitted per ingredient via
-- basis mapping (roadmap step 7.8, exec plan 0013).
--
-- Three concerns:
--
-- 1. **`ingredient_measure.basis_amount`** — measures become basis-aware. A
--    measure maps one real-world thing onto an amount **in the ingredient's
--    basis unit** (`ingredient.macros_basis`: g or ml) — "can (400 ml) =
--    400 ml" of a per-ml ingredient, not a smuggled gram weight. The column
--    is a RENAME-by-new-column of `grams`: every existing row belongs to a
--    per-g ingredient (`macros_basis = 'g'` everywhere pre-0012), so the
--    values carry over unchanged; `grams` is then dropped (dev data is
--    ephemeral through the roadmap — no dual-write compatibility machinery).
--    The measure row does NOT store its own basis: the basis is the
--    ingredient's single fact, read via the join, so the two can never
--    disagree.
--
-- 2. **`ingredient.allowed_units`** — the per-ingredient allowed-unit list
--    becomes an EXPLICIT stored attribute (jsonb array of units.dart ids),
--    materialized at creation from the ADR-0008 defaults and editable by the
--    flesh-out form (step 8). Explicit beats derived-and-implicit: rows are
--    cheap, and the entry surface must be predictable. Stored as a SET —
--    display order is the client's ordering rule (default unit fronted, its
--    family in kitchen order, other-family demoted, imprecise last).
--
--    `default_allowed_units()` below is the SQL mirror of the app's derived
--    rule (`defaultAllowedUnitSet` in
--    app/lib/features/ingredients/domain/allowed_units.dart — change one,
--    change both; each side's tests pin the same vectors):
--
--      * the default unit's family, trimmed to KITCHEN MAGNITUDES near the
--        default ("no litres of yeast"; `mg`/`fl_oz` only ever as the
--        default itself);
--      * the basis family (macros_basis: /g → weights, /ml → volumes) —
--        entry in the canonical dimension is always honest;
--      * a density unlocks the other mass/volume family (kitchen units
--        only — the client demotes them below the measures);
--      * imprecise units (`pinch`/`dash`/`to_taste`) are CATEGORY-GATED:
--        'spices & seasoning' and 'fats & oils' (the vocab's actual
--        category values — it has no 'condiment' category), plus any
--        imprecise-default ingredient. No more universal pinch-of-anything.
--
--    A BEFORE INSERT trigger materializes the list when a writer supplies
--    none (the app's create-stub path, the seed) — "materialized at
--    ingredient creation" without every writer knowing the rule. Existing
--    rows are backfilled below. The stored list is never silently
--    recomputed on update: after creation it is user-owned (the flesh-out
--    form; the app extends it explicitly when a density is added).
--
-- 3. **`ensure_onboarded()`** — fifth revision (0007→0008→0009→0010→0011→
--    this): the ingredient clone leg carries `allowed_units`, and both
--    measure-clone legs carry `basis_amount`. Everything else is 0011's
--    body verbatim.

-- ---------------------------------------------------------------------------
-- 1. Basis-aware measure amounts.
-- ---------------------------------------------------------------------------

alter table ingredient_measure add column basis_amount numeric;

update ingredient_measure set basis_amount = grams;

alter table ingredient_measure
  alter column basis_amount set not null,
  add constraint measure_basis_amount_positive check (basis_amount > 0),
  drop column grams;

comment on column ingredient_measure.basis_amount is
  'Amount of ONE of this measure in the ingredient''s basis unit '
  '(ingredient.macros_basis: g or ml). Was `grams` before 0012 — every '
  'pre-0012 row is per-g, so values carried over unchanged.';

-- ---------------------------------------------------------------------------
-- 2. Explicit per-ingredient allowed units.
-- ---------------------------------------------------------------------------

alter table ingredient add column allowed_units jsonb;

comment on column ingredient.allowed_units is
  'Explicit allowed-unit list (jsonb array of units.dart ids), ADR-0008. '
  'Materialized at creation from default_allowed_units() when the writer '
  'supplies none; edited by the flesh-out form (step 8). A stored set, not '
  'an ordering — the client orders it (default fronted, kitchen order, '
  'other family demoted, imprecise last). Null only transiently (legacy '
  'rows pre-backfill); the client falls back to deriving the same defaults.';

-- The SQL mirror of the app's ADR-0008 derived defaults. A pure function of
-- its arguments; declared STABLE (not IMMUTABLE) because `to_jsonb` is
-- itself stable, and `supabase db lint` rightly flags the mismatch.
create or replace function default_allowed_units(
  p_default_unit text,
  p_macros_basis text,
  p_density_g_per_ml numeric,
  p_category text
) returns jsonb
language plpgsql
stable
as $$
declare
  -- Kitchen-magnitude mates per default unit (the ADR trim). Mirrors
  -- _kitchenMates in allowed_units.dart.
  mates text[];
  units text[];
  basis_family text;    -- 'mass' | 'volume'
  default_family text;  -- 'mass' | 'volume' | 'count' | 'imprecise'
  big boolean;          -- default is cup/lb-scale or larger → kg/l join in
  u text;
begin
  mates := case p_default_unit
    when 'tsp'    then array['tsp','tbsp']
    when 'tbsp'   then array['tbsp','tsp','cup','ml']
    when 'cup'    then array['cup','tbsp','ml','l']
    when 'ml'     then array['ml','l','tsp','tbsp','cup']
    when 'l'      then array['l','ml','cup']
    when 'fl_oz'  then array['fl_oz','tbsp','cup','ml']
    when 'g'      then array['g','kg']
    when 'kg'     then array['kg','g']
    when 'mg'     then array['mg','g']
    when 'oz'     then array['oz','lb','g']
    when 'lb'     then array['lb','oz','g','kg']
    when 'piece'  then array['piece']
    else array[p_default_unit]  -- imprecise defaults join the tail below
  end;

  default_family := case
    when p_default_unit in ('g','kg','mg','oz','lb') then 'mass'
    when p_default_unit in ('ml','l','tsp','tbsp','fl_oz','cup') then 'volume'
    when p_default_unit = 'piece' then 'count'
    else 'imprecise'
  end;
  -- Imprecise defaults contribute nothing up front; they live in the tail.
  if default_family = 'imprecise' then
    mates := array[]::text[];
  end if;

  basis_family := case when p_macros_basis = 'ml' then 'volume' else 'mass' end;

  -- Cup/lb-scale defaults justify the big metric sibling (kg / l); spoons
  -- and grams don't ("no litres of yeast" applies to kilograms too).
  big := p_default_unit in ('cup', 'lb', 'l', 'kg');

  units := mates;

  -- Basis leg: the canonical dimension is always sayable (ADR-0008 §1).
  if basis_family <> default_family then
    units := units || case when basis_family = 'mass'
      then case when big then array['g','kg'] else array['g'] end
      else case when big then array['ml','l'] else array['ml'] end
    end;
  end if;

  -- Density leg: a stored density unlocks the other mass/volume family
  -- (kitchen workhorses only; the client demotes them below the measures).
  if p_density_g_per_ml is not null
     and default_family in ('mass', 'volume') then
    units := units || case when default_family = 'mass'
      then array['tsp','tbsp','cup','ml']
      else case when big then array['g','kg'] else array['g'] end
    end;
  end if;

  -- Imprecise leg: category-gated (plus imprecise-default ingredients).
  if default_family = 'imprecise'
     or p_category in ('spices & seasoning', 'fats & oils') then
    units := units || array['pinch','dash','to_taste'];
  end if;

  -- Dedupe, order-preserving, into a jsonb array.
  declare
    seen text[] := array[]::text[];
  begin
    foreach u in array units loop
      if not (u = any(seen)) then
        seen := seen || u;
      end if;
    end loop;
    return to_jsonb(seen);
  end;
end;
$$;

-- Materialize at creation: writers that don't know the rule (the app's
-- create-stub path, the seed inserts) get the ADR defaults stamped on the
-- way in. A writer that supplies an explicit list wins.
create or replace function ingredient_default_allowed_units()
returns trigger
language plpgsql
as $$
begin
  if new.allowed_units is null then
    new.allowed_units := default_allowed_units(
      new.default_unit, new.macros_basis, new.density_g_per_ml, new.category);
  end if;
  return new;
end;
$$;

create trigger ingredient_allowed_units_default
  before insert on ingredient
  for each row execute function ingredient_default_allowed_units();

-- Backfill the whole existing vocab (every household — dev data heals to
-- the ADR defaults; the template's curated overrides arrive with the seed).
update ingredient
set allowed_units = default_allowed_units(
  default_unit, macros_basis, density_g_per_ml, category)
where allowed_units is null;

-- ---------------------------------------------------------------------------
-- 3. ensure_onboarded() — 0011's body with:
--   * the ingredient clone leg carrying `allowed_units` through;
--   * both measure-clone legs (backfill + create path) carrying
--     `basis_amount` instead of the dropped `grams`.
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
          source, match_text, allowed_units)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, macros_basis, status, source, match_text, allowed_units
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
