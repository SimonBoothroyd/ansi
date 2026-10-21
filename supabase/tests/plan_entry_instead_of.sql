-- pgTAP: plan_entry.instead_of (0056, exec plan 0054 phase 2).
--
-- A substitute names the planned meal it replaced; it may not name itself,
-- and a hard delete of the planned meal takes its substitutes with it.
-- Run by `supabase test db`.

begin;
select plan(4);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ragù');
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-10-19');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',2,'Dinner','aaaaaaaa-0000-0000-0000-000000000004');

select is(
  (select instead_of from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000008'),
  null,
  'a planned meal replaces nothing'
);

select lives_ok(
  $$ insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, label, instead_of)
     values ('aaaaaaaa-0000-0000-0000-000000000009','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000007',2,'Dinner','Pizza with work',
             'aaaaaaaa-0000-0000-0000-000000000008') $$,
  'a meal eaten out can stand in for a planned one'
);

select throws_ok(
  $$ update plan_entry set instead_of = id
     where id = 'aaaaaaaa-0000-0000-0000-000000000009' $$,
  '23514',
  null,
  'a meal cannot replace itself'
);

delete from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000008';
select is(
  (select count(*)::int from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000009'),
  0,
  'a hard delete of the planned meal takes its substitute with it'
);

select * from finish();
rollback;
