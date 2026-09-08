-- 0039_piece_weight.sql — a piece weight is a row fact, and it is what
-- admits `piece` (ADR-0015, superseding ADR-0010).
--
-- WHAT CHANGED. ADR-0010 made `piece` a hand-curated entry in the explicit
-- `allowed_units` list: a row with a better word for its unit (a clove, an
-- avocado, a medium potato) had `piece` removed by the curation pass, and a
-- measure-less count row kept it. That was one decision per row, recorded in
-- `supabase/seed/curation_overrides.jsonl` and re-decided by hand for every
-- new ingredient. The owner's ruling (2026-09-08) replaces it with a fact the
-- row can actually state:
--
--   a PIECE WEIGHT is a row fact exactly like a density. `piece_basis_amount`
--   says what ONE of this ingredient weighs, in the row's macros basis unit
--   (g for a per-100 g row, ml for a per-100 ml one), and `piece` is admitted
--   iff the row's default unit IS `piece` AND that number is stored.
--
-- So `piece` stops being a taste question and becomes an honesty question,
-- the same one the density gate asks: a `piece` you cannot weigh cannot be
-- converted, totalled or shopped, so it is not offered. `piece_source` says
-- where the number came from — `manual`, `seed:typical`, or `borrowed from
-- <measure label>` when a curated size measure was copied onto the row.
--
-- `piece` is NEVER derived for any other default unit, whatever a stored list
-- happens to say; the app strips it at read on such rows, exactly as it
-- strips density-locked units.
--
-- COUNTS AS IS RETIRED. `ingredient.default_measure_id` (0023) answered a
-- narrower version of the same question — "what does a bare count MEAN?" —
-- through a measure id. The app stops reading and writing it. The column, its
-- own-measure trigger and `ingredient_default_measure_backfill()` all STAY:
-- data is production and durable (docs/cloud-setup.md §2c), so the column is
-- commented as retired and kept for one release rather than dropped. Its
-- values are what this migration's backfill reads.
--
-- SYNC. Both sync-rule files are `select * from ingredient`, so the two new
-- columns ride across with no rule change; the client schema
-- (`app/lib/core/sync/schema.dart`) gains them, without which PowerSync drops
-- them on the way into the local view. RLS needs nothing — the columns ride
-- `ingredient`'s existing row policies, and `authenticated` already holds
-- update on the table.
--
-- Row-preserving throughout (docs/cloud-setup.md §2c): additive columns plus
-- two guarded UPDATEs that only ever FILL — never remove, never overwrite.
-- Idempotent (a filled row no longer matches; a list that says `piece` no
-- longer matches) and reset-safe, so `supabase db reset` re-runs it cleanly.

-- ---------------------------------------------------------------------------
-- 1. The two columns.
-- ---------------------------------------------------------------------------
alter table ingredient add column if not exists piece_basis_amount numeric;
alter table ingredient add column if not exists piece_source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ingredient_piece_basis_amount_positive'
      and conrelid = 'ingredient'::regclass
  ) then
    alter table ingredient
      add constraint ingredient_piece_basis_amount_positive
      check (piece_basis_amount is null or piece_basis_amount > 0);
  end if;
end;
$$;

comment on column ingredient.piece_basis_amount is
  'What ONE of this ingredient weighs, in the row''s macros basis unit (g for '
  'a per-100 g row, ml for a per-100 ml one). A stated row FACT like a '
  'density (ADR-0015): `piece` is admitted iff default_unit = ''piece'' AND '
  'this is not null. Null on a piece-default row is a STRANDED default the '
  'flesh-out form asks for; null anywhere else is simply nothing to say.';

comment on column ingredient.piece_source is
  'Where the piece weight came from: ''manual'', ''seed:typical'', or '
  '''borrowed from <measure label>'' when a curated size measure was copied '
  'onto the row. Provenance only — nothing derives behaviour from it.';

comment on column ingredient.default_measure_id is
  'RETIRED 2026-09-08 (ADR-0015): superseded by ingredient.piece_basis_amount, '
  'which states the same fact as a NUMBER on the row instead of a pointer to a '
  'measure. The app no longer reads or writes it. Kept for one release — data '
  'is durable (docs/cloud-setup.md §2c) and 0039''s backfill reads these values '
  'to seed the piece weights — along with its own-measure trigger and '
  'ingredient_default_measure_backfill().';

-- ---------------------------------------------------------------------------
-- 2. default_allowed_units(): the piece leg becomes a fact about the row.
-- ---------------------------------------------------------------------------
--
-- 0037's body verbatim but for one leg and one argument: `piece` is emitted
-- for a count default only when the row can say what one weighs. Everything
-- else — the basis family whole, the other family behind a density, the
-- imprecise words the category earns — is unchanged (ADR-0014).
--
-- The 4-argument overload is DROPPED at the end of this section rather than
-- left beside the new one: one rule, one function, and a caller resolving to
-- the old arity by accident would silently put `piece` back on an unweighed
-- row.
--
-- STABLE (not IMMUTABLE) because `to_jsonb` is itself stable and
-- `supabase db lint` checks the mismatch (0012).
create or replace function default_allowed_units(
  p_default_unit text,
  p_macros_basis text,
  p_density_g_per_ml numeric,
  p_category text,
  p_piece_basis_amount numeric
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

  -- A count default says `piece` once the row says what one WEIGHS
  -- (ADR-0015). Without that number a `piece` cannot be converted, totalled
  -- or shopped, so it is not offered — the same honesty gate the density
  -- keeps for the other family. No other default unit ever admits `piece`.
  if p_default_unit = 'piece' and p_piece_basis_amount is not null then
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

comment on function default_allowed_units(text, text, numeric, text, numeric) is
  'The derived allowed-unit defaults: ADR-0008''s model as amended by '
  'ADR-0009 (a density unlocks the other family whatever the default unit), '
  'ADR-0014 (all to all — a family is admitted WHOLE, the kitchen trim is '
  'gone, and the household prunes per row) and ADR-0015 (a piece weight is a '
  'row fact: `piece` is admitted iff the default unit is `piece` AND the row '
  'says what one weighs — this supersedes ADR-0010''s hand-curated removals). '
  'SQL mirror of defaultAllowedUnitSet in allowed_units.dart — change one, '
  'change both; unit_admission.sql and allowed_units_test.dart pin the same '
  'vectors.';

-- density_unlocked_units() is DERIVED from the function above (0021 §2), so
-- its body is unchanged in substance and only grows the new argument. The
-- piece leg is irrelevant to the DIFFERENCE — a density does not buy or
-- remove a `piece` — so null is passed on both sides, exactly as the category
-- already is.
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
                                 1::numeric, null::text, null::numeric))
         with ordinality as w(unit, ord)
   where not (
     default_allowed_units(p_default_unit, p_macros_basis,
                           null::numeric, null::text, null::numeric) ? w.unit);
$$;

comment on function density_unlocked_units(text, text) is
  'ADR-0008 §2 as amended by ADR-0009 and ADR-0014: the units a stored '
  'density makes sayable for this default unit AND basis — the whole other '
  'mass/volume family — derived as default_allowed_units(with density) minus '
  'default_allowed_units(without), so it follows the rule by construction. '
  'The piece argument is null on both sides: a density neither buys nor takes '
  'away a `piece` (ADR-0015). SQL mirror of densityUnlockedUnits in '
  'allowed_units.dart — change one, change both; unit_admission.sql and '
  'allowed_units_test.dart pin the same vectors.';

-- The BEFORE INSERT materialization (0012) now hands the rule the row's own
-- piece weight, so a row created WITH one arrives admitting `piece` and a row
-- created without one does not.
create or replace function ingredient_default_allowed_units()
returns trigger
language plpgsql
as $$
begin
  if new.allowed_units is null then
    new.allowed_units := default_allowed_units(
      new.default_unit, new.macros_basis, new.density_g_per_ml, new.category,
      new.piece_basis_amount);
  end if;
  return new;
end;
$$;

-- One rule, one function. Every caller above now resolves to the 5-argument
-- form; the generated seed (`seed_curation.sql`) and the pgTAP suites pass
-- five arguments too.
drop function if exists default_allowed_units(text, text, numeric, text);

-- ---------------------------------------------------------------------------
-- 3. Backfill: a piece weight is COPIED from the curated size, never guessed.
-- ---------------------------------------------------------------------------
--
-- Every household, including the template and including soft-deleted rows, so
-- an undelete does not resurrect an unweighed piece. The source is the row's
-- own live `default_measure_id` measure — a stated fact about this row, which
-- 0023's curation put there deliberately — and the copy records where it came
-- from in `piece_source`.
--
-- A piece-default row with NO default measure stays null on purpose. That is
-- a STRANDED default: the app shows the row as needing a weight and the
-- flesh-out form asks for one. Inventing a number here would be exactly the
-- guess ADR-0010 refused, wearing a migration's hat.
do $$
declare
  filled int;
begin
  update ingredient i
     set piece_basis_amount = m.basis_amount,
         piece_source       = 'borrowed from ' || m.label,
         updated_at         = now()
    from ingredient_measure m
   where m.id = i.default_measure_id
     and m.deleted_at is null
     and i.default_unit = 'piece'
     and i.piece_basis_amount is null;
  get diagnostics filled = row_count;
  raise notice
    '0039_piece_weight: % row(s) took a piece weight from their default measure',
    filled;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. …and a weighed piece-default row gains `piece`. UNION only.
-- ---------------------------------------------------------------------------
--
-- ADR-0009 rule 3: a backfill may add to a household's list, never remove
-- from it. So `piece` is unioned onto every row the new rule admits it for,
-- and it is taken off NOTHING — a stored list that still says `piece` on a
-- gram-default or unweighed row keeps saying it, and the app strips it at
-- read the same way it strips density-locked units. Idempotent: a list that
-- already says `piece` does not match.
do $$
declare
  unlocked int;
begin
  update ingredient i
     set allowed_units = i.allowed_units || '["piece"]'::jsonb,
         updated_at    = now()
   where i.default_unit = 'piece'
     and i.piece_basis_amount is not null
     and i.allowed_units is not null
     and not (i.allowed_units ? 'piece');
  get diagnostics unlocked = row_count;
  raise notice
    '0039_piece_weight: % weighed piece-default row(s) gained `piece`',
    unlocked;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A piece weight ARRIVING on an existing row admits `piece`.
-- ---------------------------------------------------------------------------
--
-- The mirror of 0014 §4's `ingredient_density_unlocks_units`: the insert path
-- is covered by the materialization above, and this closes the update path —
-- a template reseed, an operator backfill, or the flesh-out form saving a
-- weight for the first time. UNION only, for the same reason as §4; an
-- app-side CLEAR strips `piece` client-side exactly as clearing a density
-- strips what it granted (ADR-0009's removal leg), which is a user act, not a
-- backfill.
create or replace function ingredient_piece_weight_extends_allowed_units()
returns trigger
language plpgsql
as $$
begin
  -- Deliberately does NOT touch piece_basis_amount, so the `of` clause on the
  -- trigger below keeps this from re-entering.
  update ingredient
     set allowed_units = allowed_units || '["piece"]'::jsonb,
         updated_at    = now()
   where id = new.id and not (allowed_units ? 'piece');
  return null;
end;
$$;

comment on function ingredient_piece_weight_extends_allowed_units() is
  'AFTER UPDATE union of `piece` into allowed_units when a piece weight lands '
  'on a piece-default row (ADR-0015). The mirror of '
  'ingredient_density_extends_allowed_units: union only, never '
  're-materialize — the list is the household''s (ADR-0008 §4).';

drop trigger if exists ingredient_piece_weight_unlocks_piece on ingredient;
create trigger ingredient_piece_weight_unlocks_piece
  after update of piece_basis_amount on ingredient
  for each row
  when (new.piece_basis_amount is not null
        and new.piece_basis_amount is distinct from old.piece_basis_amount
        and new.default_unit = 'piece'
        and new.allowed_units is not null
        and not (new.allowed_units ? 'piece'))
  execute function ingredient_piece_weight_extends_allowed_units();

-- ---------------------------------------------------------------------------
-- 6. ensure_onboarded() — 0038's body with the clone carrying the piece
--    weight and its provenance.
-- ---------------------------------------------------------------------------
--
-- The ingredient clone lists its columns explicitly, so a new column reaches
-- a fresh household only when both lists name it (the lesson 0038 paid for
-- with `source_label`). `piece_basis_amount` is a plain number in the row's
-- own basis unit, so unlike `default_measure_id` it needs no re-keying pass:
-- it copies straight across with the row. Nothing else in the function moves
-- — the retired default-measure legs are left exactly as 0038 wrote them, so
-- a household onboarding today still receives the old column's value too for
-- as long as it is kept.
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

          -- The retired default follows its measure, by label (0023). Kept
          -- while the column is (ADR-0015): nothing reads it any more.
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
          source, source_label, source_score, match_text, allowed_units,
          piece_basis_amount, piece_source)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, macros_basis, status, source, source_label, source_score,
          match_text, allowed_units, piece_basis_amount, piece_source
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

      -- …and the RETIRED default count measure follows its measure, BY LABEL
      -- (0023, seam D1). It cannot ride the ingredient clone above: the
      -- template's id names a TEMPLATE measure, which the own-measure trigger
      -- rightly refuses, and the new household's measures do not exist until
      -- the statement above has run. Kept while the column is (ADR-0015) —
      -- the piece weight the app actually reads rode across with the row.
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
