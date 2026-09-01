-- 0014_density_admission.sql — the ADR-0008 density amendment (ADR-0009),
-- plus the USDA stub prefill that has never fired (roadmap step 8.5, exec
-- plan 0020 D4 + D7).
--
-- Four concerns:
--
-- 1. **`density_unlocked_units()`** — the density leg of ADR-0008 §2, lifted
--    out of `default_allowed_units()` into a function of its own. It is the
--    SQL mirror of `densityUnlockedUnits` in allowed_units.dart, and it is
--    now what BOTH the defaults and the two triggers below read: one stored
--    copy of "what a density makes sayable".
--
-- 2. **The amendment itself** (ADR-0009,
--    `docs/decisions/0009-density-unlocks-both-families.md`): a stored
--    density unlocks the other mass/volume family **whatever the default
--    unit's family**. 0012 gated the density leg on
--    `default_family in ('mass','volume')`, so a piece-default row with a
--    perfectly good density (mango, tomato, onion, avocado) admitted no
--    volume unit at all and "1 cup diced mango" failed `Pick a supported
--    unit` on import. Density is a property of the substance, not of how the
--    shop sells it. A count- or imprecise-default row has no "other" family,
--    so it unlocks BOTH families' workhorses, minus what the basis leg
--    already admits (the dedupe below does the subtraction).
--
--    Also fixed here, found while reading: the SQL imprecise leg emitted
--    `pinch,dash,to_taste` while the Dart mirror emits
--    `pinch,dash,handful,to_taste` — **`handful` was missing server-side**,
--    and the shared vectors never covered it. The two mirrors are brought to
--    parity and the vector file grows an imprecise-gated row so the drift
--    cannot recur silently.
--
--    Existing rows are backfilled **by UNION, never by re-materializing**.
--    `allowed_units` is user-owned after creation (0012's comment is
--    explicit, and step 8.5 is building the UI that makes editing it
--    possible) — recomputing the defaults over the whole table would
--    silently discard a household's own edits and the seed's curated
--    per-row overrides. So the backfill appends only the units this
--    amendment newly admits, and only where they are absent.
--
-- 3. **`ingredient_usda_prefill`** (D7) — an AFTER INSERT trigger on a
--    `status='stub'` ingredient: the plpgsql port of the TypeScript
--    `prefillStubFromUsda` (`functions/_shared/match_db.ts`), which has been
--    written, unit-tested and callerless since step 8. It must stay
--    server-side because `usda_food` never syncs to a device (ADR-0005), and
--    a trigger is the only place that sees a stub arriving through the
--    PowerSync upload queue — the surface that actually creates stubs.
--
--    Two hard constraints, because it runs INSIDE the client's upload
--    transaction: it must be cheap (one indexed trigram probe against
--    `usda_match_trgm`, 0002) and it must NEVER fail the upload. The body is
--    wrapped in an exception block that swallows and logs; a stub whose
--    prefill fails is simply an un-enriched stub, which is exactly what it
--    was before this migration. The row STAYS `status='stub'` — a trigram
--    guess is never promoted into a macro total without a human (plan 0020
--    D5, and the TS function's own contract).
--
--    The TypeScript original is deleted in the same change: the doctrine
--    `match_db.ts` already applied to `createImportStub` and
--    `writeCorrectionAlias` — a contract with no production caller is
--    deleted rather than left as a second, drifting way to write the row.
--
-- 4. **`ingredient_density_unlocks_units`** — an AFTER UPDATE trigger that
--    unions the density leg into `allowed_units` whenever a density ARRIVES
--    on an existing row. Without it the prefill above would be half-honest
--    (it lands a density onto a list materialized before that density
--    existed, so the unlocked family stays locked), and the same hole is
--    open for a template reseed or a cloud operator's backfill — the
--    tech-debt row "a density arriving server-side does not extend
--    allowed_units", which named this trigger as one of its two acceptable
--    fixes. UNION only, never re-materialize, for the same user-ownership
--    reason as the backfill.
--
-- Reset-safe: every statement is CREATE OR REPLACE / DROP IF EXISTS /
-- guarded UPDATE, so `supabase db reset` re-runs it cleanly.

-- ---------------------------------------------------------------------------
-- 1. The density leg, on its own.
-- ---------------------------------------------------------------------------

-- SQL mirror of `densityUnlockedUnits` (allowed_units.dart) as amended by
-- ADR-0009. Returns the kitchen workhorses a stored density makes sayable
-- for a row with this default unit — the client demotes them below the
-- measures in chip order (ADR-0008 §Consequences).
--
--   mass default        → the volume workhorses (the 0012 rule, unchanged)
--   volume default      → g (+ kg at cup/lb scale) (the 0012 rule, unchanged)
--   count/imprecise     → BOTH, because there is no "other" family (ADR-0009)
--
-- A pure function of its argument; STABLE rather than IMMUTABLE only to match
-- `default_allowed_units()`'s volatility, which `supabase db lint` checks.
create or replace function density_unlocked_units(p_default_unit text)
returns text[]
language plpgsql
stable
as $$
declare
  -- Cup/lb-scale defaults justify the big metric sibling; spoons and grams
  -- don't ("no litres of yeast" applies to kilograms too). No count or
  -- imprecise default is big, so the `kg` arm below is unreachable for them
  -- today — it is written out anyway so the two mirrors read the same.
  big boolean := p_default_unit in ('cup', 'lb', 'l', 'kg');
begin
  return case
    when p_default_unit in ('g', 'kg', 'mg', 'oz', 'lb')
      then array['tsp', 'tbsp', 'cup', 'ml']
    when p_default_unit in ('ml', 'l', 'tsp', 'tbsp', 'fl_oz', 'cup')
      then case when big then array['g', 'kg'] else array['g'] end
    else
      -- Count and imprecise defaults: no "other" family, so both.
      array['tsp', 'tbsp', 'cup', 'ml']
        || case when big then array['g', 'kg'] else array['g'] end
  end;
end;
$$;

comment on function density_unlocked_units(text) is
  'ADR-0008 §2 as amended by ADR-0009: the kitchen units a stored density '
  'makes sayable for this default unit, whatever its family. SQL mirror of '
  'densityUnlockedUnits in allowed_units.dart — change one, change both; '
  'supabase/tests/unit_admission.sql and allowed_units_test.dart pin the '
  'same vectors.';

-- ---------------------------------------------------------------------------
-- 2. The amended defaults: 0012's body with the density leg delegated (and
--    ungated), and `handful` restored to the imprecise leg.
-- ---------------------------------------------------------------------------

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

  -- Density leg (ADR-0009): a stored density unlocks the other mass/volume
  -- family whatever the default unit's family — density is a property of the
  -- substance, not of how the shop sells it. Count/imprecise defaults have
  -- no "other" family, so they get both; the dedupe below subtracts whatever
  -- the basis leg already admitted. 0012 gated this on
  -- `default_family in ('mass','volume')`, which is the bug ADR-0009 fixes.
  if p_density_g_per_ml is not null then
    units := units || density_unlocked_units(p_default_unit);
  end if;

  -- Imprecise leg: category-gated (plus imprecise-default ingredients).
  -- `handful` restored: the Dart mirror has always emitted it (plan 0020 D4).
  if default_family = 'imprecise'
     or p_category in ('spices & seasoning', 'fats & oils') then
    units := units || array['pinch','dash','handful','to_taste'];
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

-- ---------------------------------------------------------------------------
-- 3. Backfill by UNION — never by re-materializing.
-- ---------------------------------------------------------------------------
--
-- Every household, not just the template: the bug this fixes bites any row
-- that carries a density, wherever it was created. Soft-deleted rows are
-- included too, so an undelete does not resurrect the old locked list.
--
-- Only the units ADR-0009 newly admits are appended, and only where absent.
-- A re-materialize (`set allowed_units = default_allowed_units(...)`) would
-- be shorter and WRONG: it would discard the seed's curated per-row
-- overrides (liquid smoke `tsp`, hot sauce `to_taste`) and every edit the
-- step-8.5 flesh-out form is about to make possible. Same reason the
-- `handful` parity fix is deliberately NOT backfilled: it changes what the
-- defaults would compute today, not what an existing list is allowed to say.
update ingredient i
set allowed_units = i.allowed_units || coalesce(
  (select jsonb_agg(du.unit)
     from unnest(density_unlocked_units(i.default_unit)) as du(unit)
    where not (i.allowed_units ? du.unit)),
  '[]'::jsonb)
where i.density_g_per_ml is not null
  and i.allowed_units is not null
  and exists (
    select 1 from unnest(density_unlocked_units(i.default_unit)) as du(unit)
    where not (i.allowed_units ? du.unit)
  );

-- ---------------------------------------------------------------------------
-- 4. A density arriving on an existing row extends its allowed units.
-- ---------------------------------------------------------------------------
--
-- The insert path is already covered (0012's BEFORE INSERT materialization
-- calls default_allowed_units() with the density in hand). This closes the
-- update path: the USDA prefill below, a template reseed, a cloud operator's
-- density backfill, and the app's own `setDensity` write (which unions the
-- same set client-side, so this is an idempotent no-op there).
--
-- UNION only. A row whose owner deliberately REMOVED a density-unlocked unit
-- and later edits the density gets it back — the same consequence the in-app
-- density write already has, and the honest one: the unit is sayable again.
create or replace function ingredient_density_extends_allowed_units()
returns trigger
language plpgsql
as $$
declare
  additions jsonb;
begin
  select coalesce(jsonb_agg(du.unit), '[]'::jsonb) into additions
    from unnest(density_unlocked_units(new.default_unit)) as du(unit)
   where not (new.allowed_units ? du.unit);

  if additions <> '[]'::jsonb then
    -- Deliberately does NOT touch density_g_per_ml, so the `of` clause on the
    -- trigger below keeps this from re-entering.
    update ingredient
       set allowed_units = allowed_units || additions,
           updated_at    = now()
     where id = new.id;
  end if;
  return null;
end;
$$;

drop trigger if exists ingredient_density_unlocks_units on ingredient;
create trigger ingredient_density_unlocks_units
  after update of density_g_per_ml on ingredient
  for each row
  when (new.density_g_per_ml is not null
        and new.density_g_per_ml is distinct from old.density_g_per_ml
        and new.allowed_units is not null)
  execute function ingredient_density_extends_allowed_units();

-- ---------------------------------------------------------------------------
-- 5. The USDA stub prefill (D7) — the plpgsql port of prefillStubFromUsda.
-- ---------------------------------------------------------------------------
--
-- SECURITY DEFINER because it must be: `usda_food` is granted to NO client
-- role (0002 — the grant-layer enforcement of ADR-0005), so the inserting
-- `authenticated` session cannot read it. Definer rights let the trigger
-- read the reference set without ever exposing it; nothing about the
-- reference set leaves this function except the two values it copies onto
-- the caller's own row.
--
-- search_path is pinned (SECURITY DEFINER hygiene, as ensure_onboarded does)
-- and includes `extensions` so `%`/`similarity()` resolve wherever pg_trgm
-- happens to live (locally `public`; Supabase cloud can place it in
-- `extensions`).
create or replace function ingredient_prefill_from_usda()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  -- Minimum trigram score to accept a background prefill. Was
  -- USDA_PREFILL_MIN in match_db.ts; this is now its only home.
  min_score constant numeric := 0.5;
  hit record;
begin
  -- NEVER fail the inserting transaction. This runs inside the client's
  -- PowerSync upload: a stub that cannot be enriched is still a perfectly
  -- good stub, but an upload that rolls back is a sync failure the user
  -- cannot act on. Any error at all is swallowed and logged.
  begin
    -- One indexed probe: `%` uses usda_match_trgm (0002), similarity()
    -- supplies the score. The sort is total (score, then fdc_id) so ties in
    -- trigram space resolve the same way on every run and every plan.
    select f.fdc_id, f.density_g_per_ml, f.macros,
           similarity(f.match_text, new.match_text) as score
      into hit
      from usda_food f
     where f.match_text % new.match_text
     order by score desc, f.fdc_id asc
     limit 1;

    if hit.fdc_id is null or hit.score < min_score then
      return null;                       -- no confident hit
    end if;
    if hit.density_g_per_ml is null and hit.macros is null then
      return null;                       -- nothing to copy; don't churn source
    end if;

    -- The row STAYS 'stub': the prefill only means the flesh-out form opens
    -- pre-populated. Promotion to 'complete' is a human confirm (plan 0020
    -- D5) — a trigram guess must never walk into a macro total on its own.
    -- The density landing here fires ingredient_density_unlocks_units above,
    -- which extends allowed_units accordingly.
    update ingredient
       set density_g_per_ml = coalesce(hit.density_g_per_ml, density_g_per_ml),
           macros           = coalesce(hit.macros, macros),
           source           = 'usda_fdc:' || hit.fdc_id::text,
           updated_at       = now()
     where id = new.id and status = 'stub' and deleted_at is null;
  exception
    when others then
      raise warning
        'ingredient_prefill_from_usda: skipped for % [%] %',
        new.id, sqlstate, sqlerrm;
  end;
  return null;
end;
$$;

comment on function ingredient_prefill_from_usda() is
  'AFTER INSERT prefill of a stub ingredient from the server-only usda_food '
  'reference (ADR-0005; plan 0020 D7). Port of the deleted TypeScript '
  'prefillStubFromUsda. Runs inside the client upload transaction: one '
  'indexed trigram probe, and every error swallowed so the upload can never '
  'fail because of it. The row stays status=''stub''.';

-- Fires for a BARE stub only — one with nothing to lose. The WHEN clause is
-- the cheap gate (no function call, no probe) and it is deliberately
-- narrower than "every stub insert":
--
--   * `source in ('manual','import_stub')` (or null) is what the two client
--     stub writers actually stamp — the picker's add-new
--     (ingredient_repository_impl.createStub) and import's commit
--     (import_repository_impl) — i.e. exactly the rows D7 is about.
--   * It therefore EXCLUDES `source='seed'`, which keeps two things true:
--     the template clone inside ensure_onboarded() does not pay a trigram
--     probe per cloned stub inside its advisory-locked transaction, and the
--     seed pipeline's audited "honestly left density-less" tail is not
--     quietly overwritten by a trigram guess.
--   * It also excludes a barcode draft (`source='off:<barcode>'`, step 8.5
--     lane B): the update below rewrites `source` wholesale, and Open Food
--     Facts provenance must not be replaced by a USDA id.
--   * The null density/macros guard says "nothing to lose" out loud: a row
--     that already carries values has nothing to gain from a guess.
drop trigger if exists ingredient_usda_prefill on ingredient;
create trigger ingredient_usda_prefill
  after insert on ingredient
  for each row
  when (new.status = 'stub'
        and new.deleted_at is null
        and new.density_g_per_ml is null
        and new.macros is null
        and (new.source is null
             or new.source in ('manual', 'import_stub')))
  execute function ingredient_prefill_from_usda();
