-- pgTAP: a plan slot takes an ingredient, not only a recipe (0033, exec plan
-- 0038 front B, decision B-D1).
--
-- The point of the check is that no client — this app, a future one, or a
-- hand-edited row — can put a meal on the week that has nothing to eat, or two
-- things to eat. Every derivation branches on `recipe_id IS NULL`, so a row
-- with neither target (or both) would be a silent hole in the cook plan, the
-- week's macros and the shopping list at once.
--
-- Also pinned here: the amount columns belong to the ingredient side only, they
-- are a both-or-neither pair, and a measure means nothing without a number.
-- Run by `supabase test db`.

begin;
select plan(11);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000301','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Protein bar','g','protein bar');

insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000401','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000301','bar',60);

insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Slow-Cooker Beef Ragù');

insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-08-31');

-- ---------------------------------------------------------------------------
-- The XOR (B-D1).
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id)
     values ('aaaaaaaa-0000-0000-0000-000000000501',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Dinner',
             'aaaaaaaa-0000-0000-0000-000000000101') $$,
  'a recipe meal is still an ordinary entry'
);

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, quantity, unit, measure_id)
     values ('aaaaaaaa-0000-0000-0000-000000000502',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000301', 1, 'piece',
             'aaaaaaaa-0000-0000-0000-000000000401') $$,
  'an ingredient meal states an amount in a measure — "1 bar"'
);

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, quantity, unit)
     values ('aaaaaaaa-0000-0000-0000-000000000503',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000301', 170, 'g') $$,
  'an ingredient meal states an amount in a unit — "170 g"'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot)
     values ('aaaaaaaa-0000-0000-0000-000000000504',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack') $$,
  '23514', null,
  'a meal with NEITHER a recipe nor an ingredient is refused'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        recipe_id, ingredient_id)
     values ('aaaaaaaa-0000-0000-0000-000000000505',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000301') $$,
  '23514', null,
  'a meal with BOTH is refused — one question, one answer'
);

-- An UPDATE cannot walk a live row out of the XOR either (the check is on the
-- row, not on the insert path).
select throws_ok(
  $$ update plan_entry set recipe_id = null
       where id = 'aaaaaaaa-0000-0000-0000-000000000501' $$,
  '23514', null,
  'clearing the recipe off a recipe meal is refused'
);

-- ---------------------------------------------------------------------------
-- The amount columns (B-D1).
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ update plan_entry set quantity = 2, unit = 'piece'
       where id = 'aaaaaaaa-0000-0000-0000-000000000501' $$,
  '23514', null,
  'a recipe meal carries no amount of its own — portions is its amount'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, quantity)
     values ('aaaaaaaa-0000-0000-0000-000000000506',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000301', 1) $$,
  '23514', null,
  'a number with no unit is half a fact, and is refused'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, unit)
     values ('aaaaaaaa-0000-0000-0000-000000000507',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000301', 'g') $$,
  '23514', null,
  'a unit with no number is the other half, and is refused'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, measure_id)
     values ('aaaaaaaa-0000-0000-0000-000000000508',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000301',
             'aaaaaaaa-0000-0000-0000-000000000401') $$,
  '23514', null,
  'a measure with nothing to count is refused'
);

-- An amount is optional on the ingredient side: an entry that states none is
-- honest about it downstream (contributes nothing, and says so) rather than
-- being blocked here.
select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot, ingredient_id)
     values ('aaaaaaaa-0000-0000-0000-000000000509',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201', 1, 'Snack',
             'aaaaaaaa-0000-0000-0000-000000000301') $$,
  'an ingredient meal with no amount is allowed — the derivations say so'
);

select * from finish();
rollback;
