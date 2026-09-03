-- 0021_admission_mirror.sql — the SQL admission mirror catches up with
-- allowed_units.dart (plan 0020 D4c + J3; exec plan 0023 lane C; retires the
-- tech-debt row "The SQL admission mirror is now two rules behind the app").
--
-- Three rule changes, one signature change, one narrow additive backfill.
-- Row-preserving throughout (docs/cloud-setup.md §2c): nothing is dropped,
-- nothing is re-materialized, and nothing is REMOVED from any stored list —
-- ADR-0009 rule 3 (union, never remove) governs every server write here. The
-- app already refuses what a stale list names (`allowedUnitsFor` subtracts
-- the density-derived units while the number is missing), so a list that is
-- too generous costs nothing at a picker or on a line; a list that is too
-- narrow is the only real cost, and (4) below pays exactly that.
--
-- The Dart rule (`defaultAllowedUnitSet` / `densityUnlockedUnits` /
-- `kImpreciseCategoryGates` in app/lib/features/ingredients/domain/
-- allowed_units.dart) is the source of truth; this file is its mirror.
-- Change one, change both — `supabase/tests/unit_admission.sql` and
-- `allowed_units_test.dart` pin the same vectors, case for case.
--
-- 1. **The mates leg is basis-strict (plan 0020 D4c).** 0012/0014 treated the
--    DEFAULT unit's family as an admission source of its own: a tsp-default
--    per-100 g row with no density materialized `tsp, tbsp` — units no number
--    on the row could convert, so a macro total could never read them. The
--    default unit's kitchen mates are now admitted only when that family IS
--    the basis family, or a density bridges it. Count and imprecise defaults
--    are untouched: they sit outside the mass⇄volume duality, so there is no
--    bridge for them to be missing. (The yeast shape: `tsp` /g, no density →
--    `["g"]`; give it a density and the spoons come back.)
--
-- 2. **`density_unlocked_units(p_default_unit, p_macros_basis)`** — a
--    signature change, not a body edit. What a density buys a row is now
--    DERIVED rather than listed: the whole rule read with the density on,
--    minus the whole rule read with it off — exactly the difference
--    `densityUnlockedUnits` takes. Under (1) that difference depends on the
--    macros BASIS as well as the default unit: for flour (cup default,
--    per-100 g) the density is the only thing admitting `cup, tbsp, ml, l`,
--    so those are what it unlocks — where 0014's one-argument leg returned
--    the cross family alone (`g, kg`, already admitted by the basis leg), and
--    a density landing SERVER-side (the USDA prefill, a reseed, an operator
--    backfill) left the row's OWN default unit out of its list until an
--    app-side edit re-materialized it.
--
--    Every caller moves to the new signature: the AFTER UPDATE trigger
--    function `ingredient_density_extends_allowed_units` (0014 §4) is
--    re-created below (the trigger `ingredient_density_unlocks_units` binds
--    to it by name and needs no change); the one-argument function is DROPPED
--    so no caller can keep reading the stale rule by accident. 0014 §3's
--    backfill was a one-shot statement in an immutable migration and does not
--    run again.
--
-- 3. **The imprecise gate is per WORD (plan 0020 J3).** 0014 admitted all
--    four words to one category set (`spices & seasoning`, `fats & oils`), so
--    a server-materialized list could name `dash` on kale where the app
--    offers only `handful`. The Dart map gates each word — pinch / dash /
--    to_taste for the spice, seasoning and oil classes; handful for produce
--    and seasoning ("that is how cooks actually talk", owner ruling). The
--    category is trimmed and case-folded before matching, as in Dart.
--
-- 4. **Backfill: additive, and confined to the one shape the old rules
--    actually left broken.** The tracker row names it: a row whose density
--    landed server-side while its stored list lacked the row's OWN default
--    unit — the shape a D4b `clearDensity` leaves (cup default, per-100 g,
--    list stripped to `[g, kg]`) once a later rename re-probe (0015) lands a
--    density and 0014's leg unions only `g, kg`. Such a row has a density, a
--    mass/volume default, and a list that does not name that default: no
--    curation and no honest edit produces that combination, so it is the
--    bug's signature and nothing else's. Those rows, and only those, are
--    unioned with what the density now unlocks. Nothing is removed; a curated
--    removal (pasta's `tsp, tbsp`, olive oil's `pinch`) is untouched because
--    those rows still name their own default. A blanket "union the new leg
--    into every density-carrying row" was considered and rejected: it would
--    re-admit exactly those curated removals, which ADR-0009's D4b note and
--    the seed both treat as the household's own.
--
-- J3b's printed-word admission is app-side only and stays so: a printed word
-- is a property of the LINE being reviewed, not of the stored row, so there
-- is nothing for a materializer to write.
--
-- Reset-safe: every statement is CREATE OR REPLACE / DROP IF EXISTS / a
-- guarded UPDATE, so `supabase db reset` re-runs it cleanly.

-- ---------------------------------------------------------------------------
-- 1 + 3. The rule itself, basis-strict and per-word gated.
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
    when p_default_unit in ('ml','l','tsp','tbsp','fl_oz','cup') then 'volume'
    when p_default_unit = 'piece' then 'count'
    else 'imprecise'
  end;

  basis_family := case when p_macros_basis = 'ml' then 'volume' else 'mass' end;

  -- Cup/lb-scale defaults justify the big metric sibling (kg / l); spoons
  -- and grams don't ("no litres of yeast" applies to kilograms too).
  big := p_default_unit in ('cup', 'lb', 'l', 'kg');

  -- The default unit's own leg.
  --
  -- **D4c.** For a mass/volume default, its kitchen-magnitude mates (the
  -- ADR-0008 trim — mirrors _kitchenMates in allowed_units.dart) are NOT an
  -- admission source of their own: they ride on the basis family (which
  -- needs nothing) or on the density (the only honest bridge to the other
  -- family). A count default is `piece`; an imprecise default joins the
  -- tail below.
  if default_family in ('mass', 'volume') then
    if has_density or default_family = basis_family then
      units := case p_default_unit
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
      end;
    end if;
  elsif default_family = 'count' then
    units := array['piece'];
  end if;

  -- Basis leg: the canonical dimension is always sayable (ADR-0008 §1).
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
  -- _densityCrossLeg in allowed_units.dart). The dedupe below subtracts
  -- whatever the legs above already admitted.
  if has_density then
    units := units || case default_family
      when 'mass'   then array['tsp','tbsp','cup','ml']
      when 'volume' then case when big then array['g','kg'] else array['g'] end
      else array['tsp','tbsp','cup','ml']
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
    units := units || 'pinch';
  end if;
  if category in ('spices & seasoning', 'fats & oils') then
    units := units || 'dash';
  end if;
  if category in ('produce', 'spices & seasoning') then
    units := units || 'handful';
  end if;
  if category in ('spices & seasoning', 'fats & oils') then
    units := units || 'to_taste';
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
  'per-word category-gated imprecise tail. SQL mirror of defaultAllowedUnitSet '
  'in allowed_units.dart — change one, change both; unit_admission.sql and '
  'allowed_units_test.dart pin the same vectors.';

-- ---------------------------------------------------------------------------
-- 2. What a density buys a row: derived, not listed.
-- ---------------------------------------------------------------------------

-- The one-argument leg is retired outright rather than left as an overload:
-- it encodes the pre-D4c rule, and a caller resolving to it by accident would
-- silently union the wrong set. Its only caller is re-created below.
drop function if exists density_unlocked_units(text);

-- SQL mirror of `densityUnlockedUnits` (allowed_units.dart, plan 0020 D4c):
-- the whole rule read with a density on, minus the whole rule read with it
-- off. The category is irrelevant to the difference (the imprecise tail is
-- the same either way), so it is passed as null on both sides; the
-- placeholder density is any non-null number.
--
--   Mango  (piece /g)   → tsp, tbsp, cup, ml
--   Flour  (cup /g)     → cup, tbsp, ml, l  — the row's own default included,
--                         since D4c the volume family is the density's to give
--   Milk   (ml /ml)     → g
--   Oats   (g /g)       → tsp, tbsp, cup, ml
--
-- Read by the AFTER UPDATE trigger below (a density arriving) and by 0021's
-- backfill; the app's `setDensity` unions the same set client-side.
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
  'default_allowed_units(with density) minus default_allowed_units(without). '
  'SQL mirror of densityUnlockedUnits in allowed_units.dart — change one, '
  'change both; unit_admission.sql and allowed_units_test.dart pin the same '
  'vectors.';

-- The 0014 §4 trigger function, re-created on the new signature. UNION only,
-- never re-materialize (ADR-0009 rule 3): a household's own list is extended
-- with what the arriving density unlocks and nothing else is touched. The
-- trigger `ingredient_density_unlocks_units` (0014) binds to this function
-- by name and is unchanged.
create or replace function ingredient_density_extends_allowed_units()
returns trigger
language plpgsql
as $$
declare
  additions jsonb;
begin
  select coalesce(jsonb_agg(du.unit order by du.ord), '[]'::jsonb)
    into additions
    from unnest(density_unlocked_units(new.default_unit, new.macros_basis))
         with ordinality as du(unit, ord)
   where not (new.allowed_units ? du.unit);

  if additions <> '[]'::jsonb then
    -- Deliberately does NOT touch density_g_per_ml, so the `of` clause on the
    -- trigger keeps this from re-entering.
    update ingredient
       set allowed_units = allowed_units || additions,
           updated_at    = now()
     where id = new.id;
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The narrow additive backfill.
-- ---------------------------------------------------------------------------
--
-- Rows that carry a density and a mass/volume default, and whose stored list
-- does not name that default unit: the shape 0014's one-argument leg left
-- behind when a density arrived server-side on a D4b-stripped row (see the
-- header). Each is unioned with what its density now unlocks — its own
-- default's kitchen mates included — and nothing is removed. Soft-deleted
-- rows are included so an undelete does not resurrect the broken list.
-- Idempotent: a row that names its default no longer matches.
--
-- Counted and reported rather than silent, so a `db push` log says how many
-- rows the old rule had actually wronged.
do $$
declare
  fixed int;
begin
  with repaired as (
    update ingredient i
       set allowed_units = i.allowed_units || (
             select coalesce(jsonb_agg(du.unit order by du.ord), '[]'::jsonb)
               from unnest(density_unlocked_units(i.default_unit, i.macros_basis))
                    with ordinality as du(unit, ord)
              where not (i.allowed_units ? du.unit)),
           updated_at = now()
     where i.density_g_per_ml is not null
       and i.allowed_units is not null
       and i.default_unit in ('g','kg','mg','oz','lb',
                              'ml','l','tsp','tbsp','fl_oz','cup')
       and not (i.allowed_units ? i.default_unit)
    returning i.id
  )
  select count(*) into fixed from repaired;
  raise notice '0021_admission_mirror: % row(s) regained their own default unit', fixed;
end;
$$;
