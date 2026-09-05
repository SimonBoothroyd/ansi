-- 0032_tsp_mates_cup.sql — the volume ladder is symmetric (ADR-0012, exec
-- plan 0036 Front B).
--
-- `tsp` mates `tbsp`; `tbsp` mates `cup`; `cup` did not mate `tsp`. So a
-- cup-default row like `Granulated Sugar` could be written in litres and not
-- in teaspoons, while the density sentence directly under its chip row
-- offered `tsp` as one of four spoons. ADR-0008's kitchen trim is about units
-- too BIG for a row ("no litres of yeast"); `tsp` is the smallest unit in the
-- family, so nothing defended the gap.
--
-- Two things happen here, and the second is the careful one.
--
-- 1. **`default_allowed_units()`** is re-created from 0024's body with one
--    array changed: the `cup` branch of the mates leg gains `'tsp'`. Nothing
--    else moves — `tsp`'s own mates stay `{tsp, tbsp}` (the trim in the other
--    direction), the density cross leg already named `tsp`, and no other
--    default unit's list changes. This is the SQL mirror of `_kitchenMates`
--    in `app/lib/features/ingredients/domain/allowed_units.dart`; the shared
--    vectors in `supabase/tests/unit_admission.sql` pin the two together.
--
--    `density_unlocked_units()` is DERIVED from this function (0024 §3), so it
--    picks the change up by construction and is not re-stated.
--
-- 2. **A widening backfill with a fence.** `allowed_units` is materialized at
--    insert and thereafter the household's own (ADR-0008 §4), so a rule change
--    reaches no existing row on its own. ADR-0009 rule 3 forbids a backfill
--    from REMOVING anything; ADR-0012 states the other half of the same
--    principle — a backfill may not OVERWRITE a stated fact either. So:
--
--        `tsp` is added only to a row whose stored list still EQUALS the old
--        derived default for that row.
--
--    A household that curated its list — a `stopOfferingPiece` removal, a
--    toggled chip in the flesh-out form, a seed curation override — is left
--    exactly as it is, and gains `tsp` the next time a human saves the row.
--    This is a stricter fence than 0024's (which asked only that the shape be
--    right and the riding sibling present); the rule change here is small
--    enough that "pristine or nothing" is affordable, and it is the honest
--    reading of "never overwrite what the household said".
--
--    **The old default is computed, not remembered.** The only textual change
--    to `default_allowed_units()` is `'tsp'` in the `cup` branch, and for a
--    `cup` default no other leg of that function can emit `tsp` — the basis
--    leg emits `g`/`kg` or `ml`/`l`, the density cross leg for a volume
--    default emits `g`/`kg`, and the imprecise tail emits words. So for a
--    cup-default row:
--
--        old_default(row) = new_default(row) minus {'tsp'}
--
--    and for every other row the two are identical, which is why this
--    migration only ever looks at cup-default rows. Comparing SORTED DISTINCT
--    arrays makes the check a set comparison: `allowed_units` is a set (0012),
--    and its stored order is nobody's contract.
--
-- Row-preserving throughout (docs/cloud-setup.md §2c): one guarded UPDATE that
-- only ever appends, over every household including the template and including
-- soft-deleted rows, so an undelete does not resurrect a pre-0032 list.
-- Idempotent — a row that names `tsp` no longer matches — and reset-safe, so
-- `supabase db reset` re-runs it cleanly.

-- ---------------------------------------------------------------------------
-- 1. default_allowed_units(): 0024's body, with cup mating tsp.
-- ---------------------------------------------------------------------------
--
-- Emission order is: the default's own leg → the basis leg → the density's
-- cross leg → the imprecise tail (own word first, then the gated words in
-- pinch/dash/handful/to_taste order). A stored list is a SET (0012); the
-- client orders it for display. The pgTAP vectors pin this emission order only
-- because `is()` compares jsonb arrays verbatim.
--
-- STABLE (not IMMUTABLE) because `to_jsonb` is itself stable and
-- `supabase db lint` checks the mismatch (0012).
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
  units text[] := array[]::text[];
  basis_family text;    -- 'mass' | 'volume'
  default_family text;  -- 'mass' | 'volume' | 'count' | 'imprecise'
  big boolean;          -- default is cup/lb-scale or larger → kg/l join in
  has_density boolean := p_density_g_per_ml is not null;
  -- Dart matches the category trimmed and case-folded (impreciseUnitsFor).
  category text := lower(btrim(p_category));
  u text;
begin
  default_family := case
    when p_default_unit in ('g','kg','mg','oz','lb') then 'mass'
    when p_default_unit in ('ml','l','tsp','tbsp','fl_oz','cup','pt','qt')
      then 'volume'
    when p_default_unit = 'piece' then 'count'
    else 'imprecise'
  end;

  basis_family := case when p_macros_basis = 'ml' then 'volume' else 'mass' end;

  -- Cup/lb-scale defaults justify the big metric sibling (kg / l); spoons
  -- and grams don't ("no litres of yeast" applies to kilograms too). The US
  -- pair is cup- and litre-scale, so both pass (D2b) — mirrors _isBig in
  -- allowed_units.dart.
  big := p_default_unit in ('cup', 'lb', 'l', 'kg', 'pt', 'qt');

  -- The default unit's own leg.
  --
  -- **D4c.** For a mass/volume default, its kitchen-magnitude mates (the
  -- ADR-0008 trim — mirrors _kitchenMates in allowed_units.dart) are NOT an
  -- admission source of their own: they ride on the basis family (which
  -- needs nothing) or on the density (the only honest bridge to the other
  -- family). A count default is `piece`; an imprecise default joins the
  -- tail below.
  --
  -- **D2b.** Quart rides with litre, pint rides with cup: every list below
  -- that names `l` names `qt`, every list that names `cup` names `pt`.
  --
  -- **ADR-0012.** `cup` names `tsp`, so the volume ladder is symmetric in
  -- both directions: tsp↔tbsp↔cup.
  if default_family in ('mass', 'volume') then
    if has_density or default_family = basis_family then
      units := case p_default_unit
        when 'tsp'    then array['tsp','tbsp']
        when 'tbsp'   then array['tbsp','tsp','cup','ml','pt']
        when 'cup'    then array['cup','tsp','tbsp','ml','l','pt','qt']
        when 'ml'     then array['ml','l','tsp','tbsp','cup','pt','qt']
        when 'l'      then array['l','ml','cup','pt','qt']
        when 'fl_oz'  then array['fl_oz','tbsp','cup','ml','pt']
        when 'qt'     then array['qt','pt','cup','l','ml']
        when 'pt'     then array['pt','cup','qt','ml']
        when 'g'      then array['g','kg']
        when 'kg'     then array['kg','g']
        when 'mg'     then array['mg','g']
        when 'oz'     then array['oz','lb','g']
        when 'lb'     then array['lb','oz','g','kg']
      end;
    end if;
  elsif default_family = 'count' then
    units := array['piece'];
  end if;

  -- Basis leg: the canonical dimension is always sayable (ADR-0008 §1). The
  -- metric base and its big sibling only — the US pair rides on the mates
  -- and cross legs, never on the basis.
  if basis_family <> default_family then
    units := units || case when basis_family = 'mass'
      then case when big then array['g','kg'] else array['g'] end
      else case when big then array['ml','l'] else array['ml'] end
    end;
  end if;

  -- Density leg (ADR-0009): a stored density unlocks the other mass/volume
  -- family's kitchen workhorses whatever the default unit's family — density
  -- is a property of the substance, not of how the shop sells it. A count or
  -- imprecise default has no "other" family, so it bridges to BOTH, the big
  -- metric sibling staying behind the same `big` gate (mirrors
  -- _densityCrossLeg in allowed_units.dart). The volume workhorses name
  -- `cup`, so they name `pt` (D2b); they never named `l`, so no `qt`. The
  -- dedupe below subtracts whatever the legs above already admitted.
  if has_density then
    units := units || case default_family
      when 'mass'   then array['tsp','tbsp','cup','pt','ml']
      when 'volume' then case when big then array['g','kg'] else array['g'] end
      else array['tsp','tbsp','cup','pt','ml']
             || case when big then array['g','kg'] else array['g'] end
    end;
  end if;

  -- Imprecise leg (J3): an imprecise default always keeps its own word, and
  -- each word is gated by category on its own — mirrors kImpreciseCategoryGates
  -- in allowed_units.dart. Keys are the vocab's ACTUAL category values; it has
  -- no 'condiment' and no 'greens' category, so `produce` is what `handful`
  -- is gated on. A null or empty category earns nothing.
  if default_family = 'imprecise' then
    units := units || p_default_unit;
  end if;
  if category in ('spices & seasoning', 'fats & oils') then
    units := units || array['pinch'];
  end if;
  if category in ('spices & seasoning', 'fats & oils') then
    units := units || array['dash'];
  end if;
  if category in ('produce', 'spices & seasoning') then
    units := units || array['handful'];
  end if;
  if category in ('spices & seasoning', 'fats & oils') then
    units := units || array['to_taste'];
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

comment on function default_allowed_units(text, text, numeric, text) is
  'ADR-0008 derived allowed-unit defaults, as amended by ADR-0009 and plan '
  '0020 D4c/J3 (0021): basis-strict mates, density-unlocked cross family, '
  'per-word category-gated imprecise tail; plan 0025 D2b (0024): quart rides '
  'with litre, pint rides with cup; ADR-0012 (0032): cup mates tsp, so the '
  'volume ladder is symmetric. SQL mirror of defaultAllowedUnitSet in '
  'allowed_units.dart — change one, change both; unit_admission.sql and '
  'allowed_units_test.dart pin the same vectors.';

-- ---------------------------------------------------------------------------
-- 2. The widening backfill — pristine rows only.
-- ---------------------------------------------------------------------------
--
-- Only cup-default rows can gain anything (see the header). For each of them:
-- the recomputed defaults must admit `tsp` (a per-g cup row with no density
-- admits no volume unit at all, exactly as it admits no cup), and the stored
-- list must still equal those defaults minus `tsp` — which IS the old rule's
-- answer for that row. Anything else has been edited, and is left alone.
do $$
declare
  widened int;
begin
  with candidate as (
    select i.id,
           (select array_agg(distinct s.u order by s.u)
              from jsonb_array_elements_text(i.allowed_units) as s(u))
             as stored,
           (select array_agg(distinct f.u order by f.u)
              from jsonb_array_elements_text(d.units) as f(u)
             where f.u <> 'tsp')
             as old_default,
           d.units as fresh
      from ingredient i
      cross join lateral (
        select default_allowed_units(i.default_unit, i.macros_basis,
                                     i.density_g_per_ml, i.category) as units
      ) d
     where i.allowed_units is not null
       and i.default_unit = 'cup'
       and not (i.allowed_units ? 'tsp')
  ),
  widened_rows as (
    update ingredient i
       set allowed_units = i.allowed_units || '["tsp"]'::jsonb,
           updated_at    = now()
      from candidate c
     where c.id = i.id
       and c.fresh ? 'tsp'
       and c.stored = c.old_default
    returning i.id
  )
  select count(*) into widened from widened_rows;
  raise notice '0032_tsp_mates_cup: % pristine cup-default row(s) gained tsp',
    widened;
end;
$$;
