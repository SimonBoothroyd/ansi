-- 0024_quart_pint.sql — pint and quart join the unit catalogue (exec plan
-- 0025 item 2, owner rulings D2a + D2b).
--
-- "We should support quart." The catalogue is one Dart file
-- (app/lib/core/units/units.dart) mirrored in nine places; this migration is
-- its SQL leg. Two new ids, both US customary and exact by definition of the
-- US gallon like every other volume entry there: `pt` (473.176473 ml) and
-- `qt` (946.352946 ml). D2a ruled the pair rather than quart alone — same
-- shape, same exactness, and pint is the other unit American stock and cream
-- lines are printed in.
--
-- Three functions are re-created with the new ids and one additive backfill
-- follows. Row-preserving throughout (docs/cloud-setup.md §2c): nothing is
-- dropped, nothing is re-materialized, nothing is REMOVED from any stored
-- list — ADR-0009 rule 3 (union, never remove) governs every server write
-- here, exactly as it did 0014's and 0021's.
--
-- 1. **`unit_family()`** (0017) learns the two ids as `volume`, so the yield
--    CHECKs on `recipe` keep agreeing with the Dart `UnitFamily` table.
--
-- 2. **`default_allowed_units()`** (0021's body) gains the D2b admission rule,
--    stated in one sentence: **quart rides with litre, pint rides with cup.**
--    Wherever a default unit's kitchen-mates list already names `l` it now
--    names `qt`; wherever it names `cup` it names `pt`. The two pairs are the
--    same magnitude in the other customary system, so a broth that may be
--    said in cups and litres may be said in pints and quarts — and the rule
--    reaches every broth/stock/milk row through the same `big` gate it
--    already passes (`qt` is litre-scale and `pt` cup-scale, so both join
--    that gate). As defaults, `qt` mates `{qt, pt, cup, l, ml}` and `pt`
--    mates `{pt, cup, qt, ml}`. The density cross leg (ADR-0009) lists the
--    kitchen volumes a density unlocks: it names `cup`, so it gains `pt`; it
--    never named `l`, so it does not gain `qt` ("no litres of yeast" still
--    holds for a kilo of oats).
--
-- 3. **`density_unlocked_units()`** is re-created unchanged in body: it is
--    derived from (2), so it picks the new ids up by construction. It is
--    re-stated here only so its comment records the rule change.
--
-- 4. **Backfill: additive, guarded, every household.** A stored list is the
--    household's own (ADR-0008 §4), so the new ids are UNIONED in where the
--    rule now derives them — never re-materialized — following 0014 §3 row
--    for row: every household including the template, soft-deleted rows
--    included so an undelete does not resurrect a pre-quart list. Two guards
--    keep a household's edits intact: the recomputed defaults for the row
--    must admit the unit (so the shape is right — a per-g cup row with no
--    density admits nothing new, exactly as it admits no cup), AND the
--    stored list must still name the sibling it rides with — `l` for `qt`,
--    `cup` for `pt`. That second guard is D2b read against the list rather
--    than the rule: a household that removed litres from a row has said
--    "not at that magnitude", and a quart must not sneak back in under a
--    different name. A curated entry (liquid smoke's `tsp`, olive oil's
--    missing `pinch`) is untouched because nothing is removed.
--
--    The template household's seed re-materializes its lists at every
--    `db reset` (seed_curation.sql), so a fresh database gets the new ids
--    from the rule and this backfill finds nothing to do there; on the cloud
--    database it is the only thing that carries existing rows across.
--
-- Reset-safe: every statement is CREATE OR REPLACE / a guarded UPDATE, so
-- `supabase db reset` re-runs it cleanly.

-- ---------------------------------------------------------------------------
-- 1. unit_family(): the two ids are volume.
-- ---------------------------------------------------------------------------

create or replace function unit_family(p_unit text) returns text
language sql
immutable
as $$
  select case
    when p_unit in ('g', 'kg', 'mg', 'oz', 'lb') then 'mass'
    when p_unit in ('ml', 'l', 'tsp', 'tbsp', 'fl_oz', 'cup', 'pt', 'qt')
      then 'volume'
    when p_unit = 'piece' then 'count'
    when p_unit in ('pinch', 'dash', 'handful', 'to_taste') then 'imprecise'
    else null
  end;
$$;

comment on function unit_family(text) is
  'The unit family (mass|volume|count|imprecise) of a units.dart Unit id, or '
  'NULL when the id is unknown. SQL mirror of UnitFamily in '
  'app/lib/core/units/units.dart (pt/qt since 0024) — change one, change '
  'both; the vectors are pinned in supabase/tests/nested_recipes.sql.';

-- ---------------------------------------------------------------------------
-- 2. default_allowed_units(): 0021's body, with quart riding with litre and
--    pint riding with cup.
-- ---------------------------------------------------------------------------
--
-- Emission order is: the default's own leg → the basis leg → the density's
-- cross leg → the imprecise tail (own word first, then the gated words in
-- pinch/dash/handful/to_taste order). A stored list is a SET (0012); the
-- client orders it for display. The pgTAP vectors pin this emission order
-- only because `is()` compares jsonb arrays verbatim.
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
  if default_family in ('mass', 'volume') then
    if has_density or default_family = basis_family then
      units := case p_default_unit
        when 'tsp'    then array['tsp','tbsp']
        when 'tbsp'   then array['tbsp','tsp','cup','ml','pt']
        when 'cup'    then array['cup','tbsp','ml','l','pt','qt']
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
  'with litre, pint rides with cup. SQL mirror of defaultAllowedUnitSet in '
  'allowed_units.dart — change one, change both; unit_admission.sql and '
  'allowed_units_test.dart pin the same vectors.';

-- ---------------------------------------------------------------------------
-- 3. density_unlocked_units(): derived from (2), so unchanged in body.
-- ---------------------------------------------------------------------------
--
-- Re-stated so the comment records that the difference now carries the US
-- pair wherever the rule does: a cup /g flour gains `cup, tbsp, ml, l, pt,
-- qt` from its density; a g /g row gains `tsp, tbsp, cup, pt, ml`. The AFTER
-- UPDATE trigger function `ingredient_density_extends_allowed_units` (0021)
-- reads this and needs no change.
create or replace function density_unlocked_units(
  p_default_unit text,
  p_macros_basis text
) returns text[]
language sql
stable
as $$
  select coalesce(array_agg(w.unit order by w.ord), array[]::text[])
    from jsonb_array_elements_text(
           default_allowed_units(p_default_unit, p_macros_basis,
                                 1::numeric, null::text))
         with ordinality as w(unit, ord)
   where not (
     default_allowed_units(p_default_unit, p_macros_basis,
                           null::numeric, null::text) ? w.unit);
$$;

comment on function density_unlocked_units(text, text) is
  'ADR-0008 §2 as amended by ADR-0009 and plan 0020 D4c (0021): the units a '
  'stored density makes sayable for this default unit AND basis — derived as '
  'default_allowed_units(with density) minus default_allowed_units(without), '
  'so the plan 0025 D2b pair (0024) rides along wherever the rule admits it. '
  'SQL mirror of densityUnlockedUnits in allowed_units.dart — change one, '
  'change both; unit_admission.sql and allowed_units_test.dart pin the same '
  'vectors.';

-- ---------------------------------------------------------------------------
-- 4. The additive backfill.
-- ---------------------------------------------------------------------------
--
-- For every row with a stored list: `qt` is unioned in when the recomputed
-- defaults admit it AND the list already names `l`; `pt` likewise when the
-- list already names `cup`. Nothing is removed. Idempotent: a row that names
-- both no longer matches. Counted and reported, as 0021's was, so a
-- `db push` log says how many rows gained a unit.
do $$
declare
  extended int;
begin
  with additions as (
    select i.id,
           (select coalesce(jsonb_agg(n.unit order by n.ord), '[]'::jsonb)
              from jsonb_array_elements_text(
                     default_allowed_units(i.default_unit, i.macros_basis,
                                           i.density_g_per_ml, i.category))
                   with ordinality as n(unit, ord)
             where (   (n.unit = 'qt' and i.allowed_units ? 'l')
                    or (n.unit = 'pt' and i.allowed_units ? 'cup'))
               and not (i.allowed_units ? n.unit)) as units
      from ingredient i
     where i.allowed_units is not null
  ),
  extended_rows as (
    update ingredient i
       set allowed_units = i.allowed_units || a.units,
           updated_at    = now()
      from additions a
     where a.id = i.id
       and a.units <> '[]'::jsonb
    returning i.id
  )
  select count(*) into extended from extended_rows;
  raise notice '0024_quart_pint: % row(s) gained pt and/or qt', extended;
end;
$$;
