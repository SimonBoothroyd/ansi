-- pgTAP: a plan slot takes a meal eaten out (0045) — the third arm of the
-- entry XOR.
--
-- The check is what makes the three-way promise total: no client — this app, a
-- future one, or a hand-edited row — can put a meal on the week that has
-- nothing to eat, or two things to eat. Every derivation branches on the kind,
-- so a row naming none of the three (or two of them) would be a silent hole in
-- the cook plan, the week's macros and the shopping list at once.
--
-- Also pinned here: a blank label is not a label, per-portion macros belong to
-- the label side only, and an entry eaten out states no amount of its own.
-- Run by `supabase test db`.

begin;
select plan(12);

insert into household (id, name) values
 ('cccccccc-cccc-cccc-cccc-cccccccccccc','House C');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('cccccccc-0000-0000-0000-000000000301','cccccccc-cccc-cccc-cccc-cccccccccccc','Protein bar','g','protein bar');

insert into recipe (id, household_id, title) values
 ('cccccccc-0000-0000-0000-000000000101','cccccccc-cccc-cccc-cccc-cccccccccccc','Slow-Cooker Beef Ragù');

insert into week_plan (id, household_id, week_start_date) values
 ('cccccccc-0000-0000-0000-000000000201','cccccccc-cccc-cccc-cccc-cccccccccccc','2026-08-31');

-- ---------------------------------------------------------------------------
-- The three-way XOR.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot, label, macros)
     values ('cccccccc-0000-0000-0000-000000000501',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Lunch',
             'Office lunch',
             '{"kcal":620,"protein":42,"carb":55,"fat":24}'::jsonb) $$,
  'a meal eaten out is an entry naming its own words, with its figures'
);

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot, label)
     values ('cccccccc-0000-0000-0000-000000000502',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 2, 'Lunch',
             'Office lunch') $$,
  'macros are optional — an unstated meal still fills its slot'
);

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id)
     values ('cccccccc-0000-0000-0000-000000000503',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Dinner',
             'cccccccc-0000-0000-0000-000000000101') $$,
  'a recipe meal is untouched by the third arm'
);

select lives_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, quantity, unit)
     values ('cccccccc-0000-0000-0000-000000000504',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Snack',
             'cccccccc-0000-0000-0000-000000000301', 170, 'g') $$,
  'an ingredient meal is untouched by the third arm'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot)
     values ('cccccccc-0000-0000-0000-000000000505',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Lunch') $$,
  '23514', null,
  'a meal naming none of the three is still refused'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        recipe_id, label)
     values ('cccccccc-0000-0000-0000-000000000506',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Lunch',
             'cccccccc-0000-0000-0000-000000000101', 'Office lunch') $$,
  '23514', null,
  'a recipe AND a label is two answers to one question'
);

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot,
        ingredient_id, label)
     values ('cccccccc-0000-0000-0000-000000000507',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Lunch',
             'cccccccc-0000-0000-0000-000000000301', 'Office lunch') $$,
  '23514', null,
  'an ingredient AND a label is refused too'
);

-- An UPDATE cannot walk a live row out of the XOR either.
select throws_ok(
  $$ update plan_entry set label = null
       where id = 'cccccccc-0000-0000-0000-000000000501' $$,
  '23514', null,
  'clearing the label off a meal eaten out leaves it nothing to eat'
);

-- ---------------------------------------------------------------------------
-- A label is words, not whitespace.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into plan_entry
       (id, household_id, week_plan_id, day_of_week, meal_slot, label)
     values ('cccccccc-0000-0000-0000-000000000508',
             'cccccccc-cccc-cccc-cccc-cccccccccccc',
             'cccccccc-0000-0000-0000-000000000201', 1, 'Lunch', '   ') $$,
  '23514', null,
  'a blank label names nothing and is refused'
);

-- ---------------------------------------------------------------------------
-- The figures belong to the label side.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ update plan_entry
       set macros = '{"kcal":620,"protein":42,"carb":55,"fat":24}'::jsonb
       where id = 'cccccccc-0000-0000-0000-000000000503' $$,
  '23514', null,
  'a recipe meal has no per-portion macros of its own — its lines do'
);

select throws_ok(
  $$ update plan_entry
       set macros = '{"kcal":620,"protein":42,"carb":55,"fat":24}'::jsonb
       where id = 'cccccccc-0000-0000-0000-000000000504' $$,
  '23514', null,
  'an ingredient meal has none either — its vocabulary row does'
);

-- ---------------------------------------------------------------------------
-- Nothing is bought or cooked, so nothing is measured.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ update plan_entry set quantity = 1, unit = 'piece'
       where id = 'cccccccc-0000-0000-0000-000000000501' $$,
  '23514', null,
  'a meal eaten out carries no amount — the amount columns are the '
  'ingredient side''s'
);

select * from finish();
rollback;
