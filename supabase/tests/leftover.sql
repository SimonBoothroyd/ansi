-- pgTAP: leftover and plan_entry.from_leftover (0060, exec plan 0060 phase 1).
--
-- A fridge or freezer row is a recipe or words, never both, counts portions
-- never below zero, and outlives the batch it replaced. A meal from it is a
-- recipe meal naming one leftover, never two, and stands as a plain recipe
-- meal if the row is hard-deleted. Run by `supabase test db`.

begin;
select plan(13);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Chili');
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-10-25');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',1,'Dinner','aaaaaaaa-0000-0000-0000-000000000004');

select lives_ok(
  $$ insert into leftover (id, household_id, place, recipe_id, portions, since, batch)
     values ('aaaaaaaa-0000-0000-0000-000000000010','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'freezer','aaaaaaaa-0000-0000-0000-000000000004',1.75,'2026-10-27',
             'aaaaaaaa-0000-0000-0000-000000000008') $$,
  'a batch frozen, in fractional portions'
);

select lives_ok(
  $$ insert into leftover (id, household_id, place, label, portions, since)
     values ('aaaaaaaa-0000-0000-0000-000000000011','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'fridge','Mum''s lasagne',2,'2026-10-28') $$,
  'a row in the household''s own words'
);

select throws_ok(
  $$ insert into leftover (household_id, place, recipe_id, label, portions, since)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','fridge',
             'aaaaaaaa-0000-0000-0000-000000000004','Chili',1,'2026-10-28') $$,
  '23514',
  null,
  'a recipe and words at once is refused'
);

select throws_ok(
  $$ insert into leftover (household_id, place, portions, since)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','fridge',1,'2026-10-28') $$,
  '23514',
  null,
  'a row naming nothing is refused'
);

select throws_ok(
  $$ insert into leftover (household_id, place, label, portions, since)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','fridge','  ',1,'2026-10-28') $$,
  '23514',
  null,
  'blank words name nothing'
);

select throws_ok(
  $$ insert into leftover (household_id, place, label, portions, since)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','pantry','Rice',1,'2026-10-28') $$,
  '23514',
  null,
  'only the fridge or the freezer'
);

select throws_ok(
  $$ update leftover set portions = -0.25
     where id = 'aaaaaaaa-0000-0000-0000-000000000011' $$,
  '23514',
  null,
  'a negative portion is refused'
);

select lives_ok(
  $$ insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id, from_leftover)
     values ('aaaaaaaa-0000-0000-0000-000000000009','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000007',4,'Dinner',
             'aaaaaaaa-0000-0000-0000-000000000004',
             'aaaaaaaa-0000-0000-0000-000000000010') $$,
  'a recipe meal can be eaten from the freezer'
);

select throws_ok(
  $$ insert into plan_entry (household_id, week_plan_id, day_of_week, meal_slot, label, from_leftover)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',
             4,'Lunch','Office lunch','aaaaaaaa-0000-0000-0000-000000000010') $$,
  '23514',
  null,
  'a meal eaten out is not from a leftover'
);

select throws_ok(
  $$ update plan_entry set leftover_of = 'aaaaaaaa-0000-0000-0000-000000000008'
     where id = 'aaaaaaaa-0000-0000-0000-000000000009' $$,
  '23514',
  null,
  'a meal names a batch or a stored row, never both'
);

delete from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000009';
delete from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000008';
select is(
  (select batch from leftover where id = 'aaaaaaaa-0000-0000-0000-000000000010'),
  null,
  'a hard delete of the batch leaves the row as one added by hand'
);

insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id, from_leftover) values
 ('aaaaaaaa-0000-0000-0000-00000000000a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',5,'Dinner','aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000010');
delete from leftover where id = 'aaaaaaaa-0000-0000-0000-000000000010';
select is(
  (select from_leftover from plan_entry where id = 'aaaaaaaa-0000-0000-0000-00000000000a'),
  null,
  'a hard delete of the row leaves the meal as a plain recipe meal'
);

select is(
  (select count(*)::int from pg_publication_tables
   where pubname = 'powersync' and tablename = 'leftover'),
  1,
  'the table is published to PowerSync'
);

select * from finish();
rollback;
