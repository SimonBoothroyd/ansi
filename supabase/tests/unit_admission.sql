-- pgTAP: the ADR-0008 unit-admission schema (migration 0012).
--
-- `default_allowed_units()` is the SQL mirror of the app's derived defaults
-- (`defaultAllowedUnitSet` in allowed_units.dart) — the vectors here are the
-- SAME shapes the Dart tests pin, so a drift between the two mirrors fails a
-- suite on whichever side moved. Also pins: the BEFORE INSERT trigger that
-- materializes the list, that an explicit list is never overridden, the
-- basis_amount rename + positivity check, and that `grams` is gone.
--
-- Run by `supabase test db`.

begin;
select plan(14);

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
-- tbsp mates + g + the imprecise tail (category-gated).
select is(
  default_allowed_units('tbsp', 'g', 0.91, 'fats & oils'),
  '["tbsp", "tsp", "cup", "ml", "g", "pinch", "dash", "to_taste"]'::jsonb,
  'tbsp default /g oil: mates + g + gated imprecise (the olive-oil shape)'
);

-- The egg shape: count default, per-g basis → piece + g, nothing else.
select is(
  default_allowed_units('piece', 'g', null, 'produce'),
  '["piece", "g"]'::jsonb,
  'count default /g: piece + basis base only (the egg shape)'
);

-- The salt shape: seasoning category gates the imprecise units in.
select is(
  default_allowed_units('tsp', 'g', null, 'spices & seasoning'),
  '["tsp", "tbsp", "g", "pinch", "dash", "to_taste"]'::jsonb,
  'seasoning category admits pinch/dash/to_taste (the salt shape)'
);

-- An imprecise default keeps its whole tail + the basis base.
select is(
  default_allowed_units('pinch', 'g', null, 'spices & seasoning'),
  '["g", "pinch", "dash", "to_taste"]'::jsonb,
  'an imprecise default yields basis base + the imprecise tail'
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
