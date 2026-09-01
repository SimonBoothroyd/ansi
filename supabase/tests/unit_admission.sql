-- pgTAP: the ADR-0008 unit-admission schema (migration 0012) as amended by
-- ADR-0009 (migration 0014), plus 0014's two ingredient triggers.
--
-- `default_allowed_units()` / `density_unlocked_units()` are the SQL mirrors
-- of the app's derived defaults (`defaultAllowedUnitSet` /
-- `densityUnlockedUnits` in allowed_units.dart) — the vectors here are the
-- SAME shapes the Dart tests pin, so a drift between the two mirrors fails a
-- suite on whichever side moved. The vectors deliberately include the two
-- shapes that were NOT covered before 0014 and hid real bugs: a
-- piece-default row WITH a density (ADR-0009) and an imprecise-gated row
-- (the missing `handful`).
--
-- Also pins: the BEFORE INSERT trigger that materializes the list, that an
-- explicit list is never overridden, that the 0014 backfill/seed refresh
-- UNIONED rather than re-materialized (curated removals survive, curated
-- additions survive), that the retired seed-level produce patch's admissions
-- now fall out of the rule (plan 0020 D4 — this assertion IS the safety net
-- that replaced the patch), the density→allowed_units union trigger, the
-- USDA stub prefill trigger (0014's insert leg AND 0015's rename leg), the
-- basis_amount rename + positivity check, and that `grams` is gone.
--
-- Run by `supabase test db`.

begin;
select plan(45);

-- ---------------------------------------------------------------------------
-- default_allowed_units() vectors (mirror allowed_units_test.dart).
-- ---------------------------------------------------------------------------

-- The yeast shape: tsp default, per-g basis, no density, ungated category →
-- spoons + the basis base. No litres, no ml, no universal pinch.
select is(
  default_allowed_units('tsp', 'g', null, 'baking'),
  '["tsp", "tbsp", "g"]'::jsonb,
  'tsp default /g: spoons + g (the yeast shape)'
);

-- The flour shape: cup default, per-g basis, density → the cup's kitchen
-- mates, g AND kg (cup-scale justifies the big sibling).
select is(
  default_allowed_units('cup', 'g', 0.59, 'baking'),
  '["cup", "tbsp", "ml", "l", "g", "kg"]'::jsonb,
  'cup default /g with density: kitchen volume + g/kg (the flour shape)'
);

-- The olive-oil shape: tbsp default, per-g basis, density, oil category →
-- tbsp mates + g + the imprecise tail (category-gated). `handful` is in the
-- tail: the 0012 SQL omitted it while allowed_units.dart always emitted it,
-- and no vector covered an imprecise-gated row. 0014 pins the parity.
select is(
  default_allowed_units('tbsp', 'g', 0.91, 'fats & oils'),
  '["tbsp", "tsp", "cup", "ml", "g", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'tbsp default /g oil: mates + g + gated imprecise incl. handful (the olive-oil shape)'
);

-- The egg shape: count default, per-g basis, NO density → piece + g, nothing
-- else. A density is what makes a volume computable; without one the count
-- row still says nothing about cups.
select is(
  default_allowed_units('piece', 'g', null, 'produce'),
  '["piece", "g"]'::jsonb,
  'count default /g without density: piece + basis base only (the egg shape)'
);

-- The MANGO shape (ADR-0009, the amendment): count default, per-g basis,
-- WITH a density → the volume workhorses unlock even though the default
-- unit is a piece. "1 cup diced mango" is an ordinary recipe line; density
-- is a property of the substance, not of how the shop sells it. Under 0012
-- this returned ["piece", "g"] and every cup-measured produce import failed
-- `Pick a supported unit`.
select is(
  default_allowed_units('piece', 'g', 0.63, 'produce'),
  '["piece", "g", "tsp", "tbsp", "cup", "ml"]'::jsonb,
  'count default /g WITH density: volume workhorses unlock (the mango shape)'
);

-- The same amendment from the per-ml side: a count-default liquid-ish row
-- unlocks the MASS workhorses, and the basis leg's ml is not duplicated.
select is(
  default_allowed_units('piece', 'ml', 1.0, 'dairy'),
  '["piece", "ml", "tsp", "tbsp", "cup", "g"]'::jsonb,
  'count default /ml with density: mass unlocks, basis ml not duplicated'
);

-- The salt shape: seasoning category gates the imprecise units in.
select is(
  default_allowed_units('tsp', 'g', null, 'spices & seasoning'),
  '["tsp", "tbsp", "g", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'seasoning category admits pinch/dash/handful/to_taste (the salt shape)'
);

-- An imprecise default keeps its whole tail + the basis base.
select is(
  default_allowed_units('pinch', 'g', null, 'spices & seasoning'),
  '["g", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'an imprecise default yields basis base + the imprecise tail'
);

-- …and an imprecise default WITH a density unlocks both families too
-- (ADR-0009: no "other" family to pick, so both, minus the basis leg's).
select is(
  default_allowed_units('pinch', 'g', 0.45, 'spices & seasoning'),
  '["g", "tsp", "tbsp", "cup", "ml", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'imprecise default with density: both families unlock (ADR-0009)'
);

-- A per-ml liquid: volume default IS the basis family — no gram leg without
-- a density; with one, mass unlocks.
select is(
  default_allowed_units('cup', 'ml', null, 'dairy'),
  '["cup", "tbsp", "ml", "l"]'::jsonb,
  'cup default /ml without density: volume only'
);
select is(
  default_allowed_units('cup', 'ml', 1.03, 'dairy'),
  '["cup", "tbsp", "ml", "l", "g", "kg"]'::jsonb,
  'cup default /ml with density: g/kg unlock (demoted client-side)'
);

-- ---------------------------------------------------------------------------
-- density_unlocked_units() — the density leg alone (0014). Mirrors
-- `densityUnlockedUnits` in allowed_units.dart, and is what the backfill and
-- the density trigger both union in, so it gets its own vectors.
-- ---------------------------------------------------------------------------

select is(
  density_unlocked_units('g'), array['tsp','tbsp','cup','ml'],
  'a mass default unlocks the volume workhorses'
);
select is(
  density_unlocked_units('tbsp'), array['g'],
  'a spoon-scale volume default unlocks g only (no kilos of tbsp)'
);
select is(
  density_unlocked_units('cup'), array['g','kg'],
  'a cup-scale volume default also justifies kg'
);
select is(
  density_unlocked_units('piece'), array['tsp','tbsp','cup','ml','g'],
  'a count default unlocks BOTH families — there is no "other" one (ADR-0009)'
);
select is(
  density_unlocked_units('pinch'), array['tsp','tbsp','cup','ml','g'],
  'an imprecise default unlocks both families too (ADR-0009)'
);

-- ---------------------------------------------------------------------------
-- Materialization trigger (0012): null → the rule; explicit → verbatim.
-- ---------------------------------------------------------------------------

insert into household (id, name)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Test');

insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text)
values ('cccccccc-0000-0000-0000-000000000001',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Yeast', 'tsp', 'baking',
  'manual', 'trigger yeast');
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["tsp", "tbsp", "g"]'::jsonb,
  'inserting without allowed_units materializes the ADR defaults'
);

insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, allowed_units)
values ('cccccccc-0000-0000-0000-000000000002',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Explicit Row', 'tsp', 'baking',
  'manual', 'explicit row', '["cup"]'::jsonb);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000002'),
  '["cup"]'::jsonb,
  'an explicitly supplied allowed_units list is never overridden'
);

-- The migration backfill left no live vocab row without a list.
select is(
  (select count(*)::int from ingredient
     where allowed_units is null and deleted_at is null),
  0,
  'no live ingredient is left without an allowed_units list'
);

-- ---------------------------------------------------------------------------
-- 0014: a density ARRIVING on an existing row extends allowed_units — by
-- UNION, never by re-materializing (ingredient_density_unlocks_units).
-- ---------------------------------------------------------------------------

-- A hand-edited row: one unit the defaults would never give it ('to_taste'
-- on a baking row) and one the defaults WOULD have given it removed ('tbsp').
update ingredient set allowed_units = '["tsp", "to_taste"]'::jsonb
where id = 'cccccccc-0000-0000-0000-000000000001';

update ingredient set density_g_per_ml = 0.55
where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["tsp", "to_taste", "g"]'::jsonb,
  'a density arriving unions the density leg in and keeps the user''s own list'
);

-- Idempotent: re-stating the same density changes nothing, and an unrelated
-- update never touches the list.
update ingredient set density_g_per_ml = 0.55
where id = 'cccccccc-0000-0000-0000-000000000001';
update ingredient set canonical_name = 'Trigger Yeast II'
where id = 'cccccccc-0000-0000-0000-000000000001';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["tsp", "to_taste", "g"]'::jsonb,
  'an unchanged density and an unrelated edit both leave the list alone'
);

-- ---------------------------------------------------------------------------
-- 0014 / plan 0020 D4: the retired seed produce patch, as an assertion.
--
-- The template vocab used to carry cup/tbsp/ml on 49 piece-default produce
-- rows via an explicit `seed_curation.sql` patch, labelled "until ADR-0008 is
-- amended". ADR-0009 amended it, the patch is gone, and this is the safety
-- net that replaced it: the admissions must now fall out of the rule.
-- ---------------------------------------------------------------------------

select cmp_ok(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null and category = 'produce'
       and default_unit = 'piece' and density_g_per_ml is not null),
  '>', 40,
  'the template still has the piece-default produce rows this guards (~49)'
);
select is(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null and category = 'produce'
       and default_unit = 'piece' and density_g_per_ml is not null
       and not (allowed_units ? 'cup' and allowed_units ? 'tbsp'
                and allowed_units ? 'ml')),
  0,
  'every piece-default produce row with a density admits cup/tbsp/ml (D4)'
);

-- …and the curated per-row overrides the seed keeps (they are not
-- density-derived and have nowhere else to live) survived the refresh: the
-- backfill unions, it does not re-materialize.
select ok(
  (select allowed_units ? 'tsp' from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text = 'liquid smoke'),
  'a curated ADDITION survives (liquid smoke keeps tsp)'
);
select ok(
  (select not (allowed_units ? 'pinch') and not (allowed_units ? 'handful')
     from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text = 'olive oil'),
  'a curated REMOVAL survives (nobody pinches olive oil)'
);

-- ---------------------------------------------------------------------------
-- 0014 / plan 0020 D7: the USDA stub prefill trigger.
--
-- A private reference row so the vectors do not depend on which FDC foods
-- the seed happens to carry. `usda_food` is server-only (ADR-0005): the
-- trigger is SECURITY DEFINER precisely so an `authenticated` inserter — who
-- has no grant on the table at all — still gets the prefill.
-- ---------------------------------------------------------------------------

insert into usda_food (fdc_id, description, category, density_g_per_ml,
  macros, match_text)
values (999000001, 'Zzquux Test Reference Food', 'produce', 0.75,
  '{"kcal": 100, "protein": 2, "carb": 20, "fat": 1}'::jsonb,
  'zzquux test reference food');

insert into ingredient (id, household_id, canonical_name, default_unit,
  category, status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000003',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test Reference Food', 'g',
  'produce', 'stub', 'import_stub', 'zzquux test reference food');

select is(
  (select density_g_per_ml from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  0.75::numeric,
  'an import stub is USDA-prefilled with the density on insert'
);
select is(
  (select macros ->> 'kcal' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  '100',
  'the prefill copies the macros too'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  'usda_fdc:999000001',
  'the prefill records the FDC provenance'
);
select is(
  (select status from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  'stub',
  'the prefilled row STAYS a stub — completion is a human confirm (D5)'
);
-- The density landed by the prefill also flows through the density trigger,
-- so the row's allowed_units are honest about what it can now say.
select ok(
  (select allowed_units ? 'tsp' and allowed_units ? 'cup' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  'the prefilled density unlocks the volume workhorses in the same insert'
);

-- A weak hit (0.44 similarity against 'zzquux test reference food' — above
-- pg_trgm's 0.3 match threshold, below the 0.5 prefill floor) is left alone.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000004',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test', 'g',
  'stub', 'import_stub', 'zzquux test');
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000004'),
  'import_stub',
  'a weak trigram hit does not prefill (below the 0.5 floor)'
);

-- A seeded/curated row is NOT prefilled: the seed pipeline audits its own
-- density tail, and the template clone inside ensure_onboarded() must not
-- pay a trigram probe per cloned stub.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000005',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test Reference Food', 'g',
  'stub', 'seed', 'zzquux test reference food');
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000005'),
  'seed',
  'a seed-sourced stub is left alone by the prefill'
);
select ok(
  (select density_g_per_ml is null from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000005'),
  'a seed-sourced stub keeps its honestly-absent density'
);

-- A `complete` row is never touched, whatever it matches.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text, macros)
values ('cccccccc-0000-0000-0000-000000000006',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test Reference Food', 'g',
  'complete', 'manual', 'zzquux test reference food',
  '{"kcal": 7}'::jsonb);
select is(
  (select macros ->> 'kcal' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000006'),
  '7',
  'a complete row is never prefilled over'
);

-- THE contract that matters: the prefill runs inside the client's upload
-- transaction, so it must never fail it. Break the reference set outright
-- and the insert must still land, un-enriched. (DDL is transactional; the
-- rename rolls back with everything else.)
alter table usda_food rename to usda_food_hidden_by_test;
select lives_ok(
  $$ insert into ingredient (id, household_id, canonical_name, default_unit,
       status, source, match_text)
     values ('cccccccc-0000-0000-0000-000000000007',
       'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Broken', 'g',
       'stub', 'import_stub', 'zzquux test reference food') $$,
  'a stub insert survives a prefill that throws (swallow-and-log)'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000007'),
  'import_stub',
  'the surviving row is simply un-enriched'
);
alter table usda_food_hidden_by_test rename to usda_food;

-- ---------------------------------------------------------------------------
-- 0015 / plan 0020 D7: the same prefill on a RENAME.
--
-- 0014's trigger was AFTER INSERT only; 0015 recreates it as AFTER INSERT OR
-- UPDATE OF canonical_name, because D7 (c) is explicitly about renames ("you
-- fix 'curry leafs' → 'Curry leaves, fresh' and want the lookup re-run") and
-- the flesh-out form says so on screen. The WHEN guards are unchanged, which
-- is what keeps the update leg from touching a row someone has filled in.
-- ---------------------------------------------------------------------------

-- A bare stub under a name the trigram misses: nothing to copy on insert.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000008',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Qqfoo Mystery Item', 'g',
  'stub', 'manual', 'qqfoo mystery item');
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  'manual',
  'the misnamed stub arrives un-enriched (nothing matched on insert)'
);

-- The rename the user makes on the flesh-out form: name and match_text
-- written together (D6), which is the statement 0015's trigger catches.
update ingredient
   set canonical_name = 'Zzquux Test Reference Food',
       match_text = 'zzquux test reference food'
 where id = 'cccccccc-0000-0000-0000-000000000008';
select is(
  (select density_g_per_ml from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  0.75::numeric,
  'a rename on a BARE stub re-runs the probe and can fill it (0015)'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  'usda_fdc:999000001',
  'the re-run records the FDC provenance'
);
select is(
  (select status from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  'stub',
  'a renamed-and-prefilled row is STILL a stub (D5 holds on the new leg)'
);

-- The guard that matters most on the update leg: a row someone has already
-- filled in is never re-probed, so a rename cannot clobber real numbers.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text, macros)
values ('cccccccc-0000-0000-0000-000000000009',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Qqfoo Fleshed Out', 'g',
  'stub', 'manual', 'qqfoo fleshed out', '{"kcal": 7}'::jsonb);
update ingredient
   set canonical_name = 'Zzquux Test Reference Food',
       match_text = 'zzquux test reference food'
 where id = 'cccccccc-0000-0000-0000-000000000009';
select is(
  (select macros ->> 'kcal' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000009'),
  '7',
  'renaming a fleshed-out stub is a no-op — its macros survive'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000009'),
  'manual',
  'and its provenance is not rewritten to a USDA id'
);

-- ---------------------------------------------------------------------------
-- Basis-aware measures (0012): grams is gone; basis_amount is guarded.
-- ---------------------------------------------------------------------------

select has_column('ingredient_measure', 'basis_amount',
  'ingredient_measure carries basis_amount');
select hasnt_column('ingredient_measure', 'grams',
  'the old grams column is dropped (renamed via new column)');

select throws_ok(
  $$ insert into ingredient_measure (household_id, ingredient_id, label,
       basis_amount)
     values ('cccccccc-cccc-cccc-cccc-cccccccccccc',
       'cccccccc-0000-0000-0000-000000000001', 'bad glug', 0) $$,
  '23514',
  null,
  'basis_amount rejects non-positive amounts (0012 check)'
);

select * from finish();
rollback;
