-- pgTAP: plan_entry.leftover_of (0059, exec plan 0059 phase 1).
--
-- A meal eaten from a leftover names the batch it came from: a recipe meal
-- only, never itself, and a hard delete of the batch's meal leaves it as a
-- plain recipe meal. Run by `supabase test db`.

begin;
select plan(5);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Chickpea Curry');
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-10-25');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',1,'Dinner','aaaaaaaa-0000-0000-0000-000000000004');

select is(
  (select leftover_of from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000008'),
  null,
  'a cooked meal comes from no leftover'
);

select lives_ok(
  $$ insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id, leftover_of)
     values ('aaaaaaaa-0000-0000-0000-000000000009','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000007',3,'Lunch',
             'aaaaaaaa-0000-0000-0000-000000000004',
             'aaaaaaaa-0000-0000-0000-000000000008') $$,
  'a recipe meal can be eaten from a batch'
);

select throws_ok(
  $$ insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, label, leftover_of)
     values ('aaaaaaaa-0000-0000-0000-00000000000a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000007',3,'Lunch','Office lunch',
             'aaaaaaaa-0000-0000-0000-000000000008') $$,
  '23514',
  null,
  'a meal eaten out is not a leftover of anything'
);

select throws_ok(
  $$ update plan_entry set leftover_of = id
     where id = 'aaaaaaaa-0000-0000-0000-000000000009' $$,
  '23514',
  null,
  'a meal cannot be its own leftover'
);

delete from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000008';
select is(
  (select leftover_of from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000009'),
  null,
  'a hard delete of the batch leaves the meal as a plain recipe meal'
);

select * from finish();
rollback;
