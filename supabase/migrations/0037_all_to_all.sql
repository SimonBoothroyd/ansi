-- 0037_all_to_all.sql — the kitchen trim is gone (ADR-0014).
--
-- The admission rule used to name, per default unit, the "kitchen magnitude"
-- mates it was allowed to keep company with. Two ADRs in five days fixed one
-- asymmetry each inside that list — `cup` refusing `tsp`, `oz` refusing `kg` —
-- which is what a wrong abstraction looks like from the inside. The owner's
-- ruling replaces it:
--
--   the whole basis family, always; the whole OTHER mass/volume family once a
--   density bridges them; `piece` on a count row; the imprecise words the
--   category earns. Anything a household will never say, it turns off per row
--   in the flesh-out form.
--
-- Three things happen here, and the third is the careful one.
--
-- 1. **`mg` leaves the catalog.** A milligram is how a supplement's label
--    reads, not how a kitchen weighs, and a unit nobody may pick has no
--    business being a family member the rule then has to except. `unit_family()`
--    and `default_allowed_units()` stop knowing the id, and the STORED data is
--    carried across rather than stranded: every quantity in `mg` becomes the
--    same quantity in `g` (× 0.001), every `mg` default unit becomes `g`, and
--    `"mg"` is stripped from every `allowed_units` list. The seed contains no
--    `mg` at all, so this is entirely for household data.
--
-- 2. **`fl oz` stops being special.** It was excepted alongside `mg` as
--    "label-reading granularity"; it is a kitchen unit in a British kitchen,
--    and it now joins the volume family in every list like the others. No
--    statement is needed for that beyond the new function body — it is simply
--    not excepted any more.
--
-- 3. **A widening backfill with a fence.** `allowed_units` is materialized at
--    insert and thereafter the household's own (ADR-0008 §4), so a rule change
--    reaches no existing row on its own. ADR-0009 rule 3 forbids a backfill
--    from REMOVING anything; ADR-0012 stated the other half of the same
--    principle — a backfill may not OVERWRITE a stated fact either. So, as in
--    0032 and 0035:
--
--        a row gains the units the new rule adds only while its stored list
--        still EQUALS what the old rule derived for that row.
--
--    A household that curated its list — a `stopOfferingPiece` removal, a
--    toggled chip in the flesh-out form, a seed curation override — is left
--    exactly as it is, and gains the rest the next time a human saves the row.
--
--    **The old default is computed, not remembered.** The change is far too
--    broad to characterise as "the new answer minus one unit" the way 0032 and
--    0035 could, so the old rule is carried here as a temporary function,
--    `default_allowed_units_pre_0037()` — 0035's body verbatim — used for the
--    equality test and dropped at the end of this migration. The new rule is a
--    SUPERSET of it for every row (each old leg was a subset of the family the
--    new rule admits whole), which is what makes the union below a widening
--    and never a rewrite. Comparing SORTED DISTINCT arrays makes the check a
--    set comparison: `allowed_units` is a set (0012), and its stored order is
--    nobody's contract.
--
--    The `mg` strip in (1) is NOT under the fence. A unit that no longer
--    exists is not a curation, so it comes out of every list, curated or not.
--    It runs first, which leaves a former `mg`-default row storing `["g"]`
--    against a fresh default of `["g","kg","oz","lb"]`: it fails the equality
--    test and is not widened, which is the conservative half of the fence
--    doing its job on a row this migration has already had to speak for.
--
-- Row-preserving throughout (docs/cloud-setup.md §2c): guarded UPDATEs over
-- every household including the template and including soft-deleted rows, so
-- an undelete does not resurrect a pre-0037 list or a `mg` quantity.
-- Idempotent — a converted row no longer matches, a widened row no longer
-- matches — and reset-safe, so `supabase db reset` re-runs it cleanly.

-- ---------------------------------------------------------------------------
-- 1. unit_family(): the catalogue without `mg`.
-- ---------------------------------------------------------------------------

create or replace function unit_family(p_unit text) returns text
language sql
immutable
as $$
  select case
    when p_unit in ('g', 'kg', 'oz', 'lb') then 'mass'
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
  'app/lib/core/units/units.dart — change one, change both; the vectors are '
  'pinned in supabase/tests/nested_recipes.sql.';

-- ---------------------------------------------------------------------------
-- 2. The old rule, kept just long enough to fence the backfill.
-- ---------------------------------------------------------------------------
--
-- 0035's body verbatim, including its dead `mg` branch — this is what the
-- stored lists were derived from, and an edited copy would not be. Dropped at
-- the bottom of this file.
create function default_allowed_units_pre_0037(
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
  basis_family text;
  default_family text;
  big boolean;
  has_density boolean := p_density_g_per_ml is not null;
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
  big := p_default_unit in ('cup', 'lb', 'l', 'kg', 'pt', 'qt');

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
        when 'g'      then array['g','kg','oz','lb']
        when 'kg'     then array['kg','g','oz','lb']
        when 'mg'     then array['mg','g']
        when 'oz'     then array['oz','lb','g','kg']
        when 'lb'     then array['lb','oz','g','kg']
      end;
    end if;
  elsif default_family = 'count' then
    units := array['piece'];
  end if;

  if basis_family <> default_family then
    units := units || case when basis_family = 'mass'
      then case when big then array['g','kg'] else array['g'] end
      else case when big then array['ml','l'] else array['ml'] end
    end;
  end if;

  if has_density then
    units := units || case default_family
      when 'mass'   then array['tsp','tbsp','cup','pt','ml']
      when 'volume' then case when big then array['g','kg'] else array['g'] end
      else array['tsp','tbsp','cup','pt','ml']
             || case when big then array['g','kg'] else array['g'] end
    end;
  end if;

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

-- ---------------------------------------------------------------------------
-- 3. default_allowed_units(): the whole rule, four legs.
-- ---------------------------------------------------------------------------
--
-- Emission order is: `piece` for a count default → the basis family → the
-- other family when a density bridges it → the imprecise tail (own word
-- first, then the gated words in pinch/dash/handful/to_taste order). A stored
-- list is a SET (0012); the client orders it for display (`_kitchenOrder` in
-- allowed_units.dart, which fronts the row's own default). The pgTAP vectors
-- pin this emission order only because `is()` compares jsonb arrays verbatim;
-- the generated block compares membership.
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
  mass constant text[] := array['g','kg','oz','lb'];
  volume constant text[] :=
    array['tsp','tbsp','fl_oz','cup','ml','l','pt','qt'];
  units text[] := array[]::text[];
  basis text[];         -- the basis family, admitted whole and unconditionally
  other text[];         -- the other one, admitted whole behind the density
  -- Dart matches the category trimmed and case-folded (impreciseUnitsFor).
  category text := lower(btrim(p_category));
  u text;
begin
  if p_macros_basis = 'ml' then
    basis := volume;
    other := mass;
  else
    basis := mass;
    other := volume;
  end if;

  -- A count default says `piece` — there is nothing clearer to call one of
  -- these (ADR-0010). Whether a row that HAS something clearer keeps offering
  -- it is a curated fact on the row, never a rule.
  if p_default_unit = 'piece' then
    units := array['piece'];
  end if;

  -- The basis family (ADR-0008 §1): the canonical dimension is always
  -- sayable, whole. A row's own default unit needs no leg of its own — it is
  -- in here, or in the density-gated family below, which is exactly what
  -- unitSayableAsDefault refuses to store without a number.
  units := units || basis;

  -- The other family (ADR-0009), whole, once a density bridges the two.
  -- Density is a property of the substance, not of how the shop sells it, so
  -- this fires for a count or imprecise default too ("1 cup diced mango").
  if p_density_g_per_ml is not null then
    units := units || other;
  end if;

  -- Imprecise leg (J3): an imprecise default always keeps its own word, and
  -- each word is gated by category on its own — mirrors kImpreciseCategoryGates
  -- in allowed_units.dart. Keys are the vocab's ACTUAL category values; it has
  -- no 'condiment' and no 'greens' category, so `produce` is what `handful`
  -- is gated on. A null or empty category earns nothing. The flesh-out form
  -- offers every word as a chip regardless; this is only what arrives picked.
  if p_default_unit in ('pinch', 'dash', 'handful', 'to_taste') then
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
  'The derived allowed-unit defaults: ADR-0008''s model as amended by '
  'ADR-0009 (a density unlocks the other family whatever the default unit), '
  'ADR-0010 (piece is a count row''s fallback) and ADR-0014 (all to all — a '
  'family is admitted WHOLE, the kitchen trim is gone, and the household '
  'prunes per row). SQL mirror of defaultAllowedUnitSet in allowed_units.dart '
  '— change one, change both; unit_admission.sql and allowed_units_test.dart '
  'pin the same vectors.';

comment on function density_unlocked_units(text, text) is
  'ADR-0008 §2 as amended by ADR-0009 and ADR-0014: the units a stored '
  'density makes sayable for this default unit AND basis — the whole other '
  'mass/volume family — derived as default_allowed_units(with density) minus '
  'default_allowed_units(without), so it follows the rule by construction. '
  'SQL mirror of densityUnlockedUnits in allowed_units.dart — change one, '
  'change both; unit_admission.sql and allowed_units_test.dart pin the same '
  'vectors.';

-- ---------------------------------------------------------------------------
-- 4. `mg` leaves the stored data, not just the catalogue.
-- ---------------------------------------------------------------------------
--
-- Every table that stores a units.dart id: the four amount-carrying ones
-- (`recipe_line_item`, `plan_entry`, `shopping_list_contribution`) plus
-- `shopping_list_entry.unit`, which is a display preference with no amount
-- beside it, plus `recipe`'s two yield denominations. A quantity is rescaled
-- with its unit so the fact it states does not change; `updated_at` is bumped
-- so the row syncs. Soft-deleted rows are included deliberately — an undelete
-- must not bring an id the catalogue no longer knows back to life.
do $$
declare
  n_lines int;
  n_plan int;
  n_contrib int;
  n_entry int;
  n_yield int;
  n_default int;
  n_lists int;
begin
  update recipe_line_item
     set quantity = quantity * 0.001, unit = 'g', updated_at = now()
   where unit = 'mg';
  get diagnostics n_lines = row_count;

  update plan_entry
     set quantity = quantity * 0.001, unit = 'g', updated_at = now()
   where unit = 'mg';
  get diagnostics n_plan = row_count;

  update shopping_list_contribution
     set quantity = quantity * 0.001, unit = 'g', updated_at = now()
   where unit = 'mg';
  get diagnostics n_contrib = row_count;

  update shopping_list_entry
     set unit = 'g', updated_at = now()
   where unit = 'mg';
  get diagnostics n_entry = row_count;

  -- The two yield denominations must stay in DIFFERENT families
  -- (recipe_yield_2_other_family, 0017). Converting mass→mass cannot break
  -- that: a pair that would collide was already two mass units.
  update recipe
     set yield_qty = case when yield_unit = 'mg'
                          then yield_qty * 0.001 else yield_qty end,
         yield_unit = case when yield_unit = 'mg' then 'g' else yield_unit end,
         yield_qty_2 = case when yield_unit_2 = 'mg'
                            then yield_qty_2 * 0.001 else yield_qty_2 end,
         yield_unit_2 = case when yield_unit_2 = 'mg'
                             then 'g' else yield_unit_2 end,
         updated_at = now()
   where yield_unit = 'mg' or yield_unit_2 = 'mg';
  get diagnostics n_yield = row_count;

  update ingredient
     set default_unit = 'g', updated_at = now()
   where default_unit = 'mg';
  get diagnostics n_default = row_count;

  -- Not under the fence below: a unit that no longer exists is not a
  -- curation, so it comes out of every list, curated or pristine.
  update ingredient i
     set allowed_units = (
           select coalesce(jsonb_agg(e.u order by e.ord), '[]'::jsonb)
             from jsonb_array_elements_text(i.allowed_units)
                  with ordinality as e(u, ord)
            where e.u <> 'mg'),
         updated_at = now()
   where i.allowed_units ? 'mg';
  get diagnostics n_lists = row_count;

  raise notice
    '0037_all_to_all: mg → g on % recipe line(s), % plan entr(ies), '
    '% contribution(s), % shopping entr(ies), % recipe yield(s), '
    '% ingredient default(s); stripped from % allowed_units list(s)',
    n_lines, n_plan, n_contrib, n_entry, n_yield, n_default, n_lists;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The widening backfill — pristine rows only.
-- ---------------------------------------------------------------------------
--
-- For each row with a stored list: what the NEW rule derives, minus what the
-- row already stores, is what it stands to gain; it gains it only if the
-- stored list is still exactly what the OLD rule derived. Anything else has
-- been edited, and this migration has nothing to say back to a stated fact.
do $$
declare
  widened int;
begin
  with candidate as (
    select i.id,
           (select coalesce(jsonb_agg(f.u order by f.ord), '[]'::jsonb)
              from jsonb_array_elements_text(d.units)
                   with ordinality as f(u, ord)
             where not (i.allowed_units ? f.u))
             as added,
           (select array_agg(distinct s.u order by s.u)
              from jsonb_array_elements_text(i.allowed_units) as s(u))
             as stored,
           (select array_agg(distinct o.u order by o.u)
              from jsonb_array_elements_text(o_units.units) as o(u))
             as old_default
      from ingredient i
      cross join lateral (
        select default_allowed_units(i.default_unit, i.macros_basis,
                                     i.density_g_per_ml, i.category) as units
      ) d
      cross join lateral (
        select default_allowed_units_pre_0037(i.default_unit, i.macros_basis,
                                              i.density_g_per_ml,
                                              i.category) as units
      ) o_units
     where i.allowed_units is not null
  ),
  widened_rows as (
    update ingredient i
       set allowed_units = i.allowed_units || c.added,
           updated_at    = now()
      from candidate c
     where c.id = i.id
       and c.added <> '[]'::jsonb
       and c.stored = c.old_default
    returning i.id
  )
  select count(*) into widened from widened_rows;
  raise notice
    '0037_all_to_all: % pristine row(s) widened to the whole family',
    widened;
end;
$$;

drop function default_allowed_units_pre_0037(text, text, numeric, text);
