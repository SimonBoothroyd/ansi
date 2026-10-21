-- pgTAP: batch_leftover (0057, exec plan 0054 phase 3).
--
-- An answer counts portions, never a negative one, and goes with the meal it
-- is keyed to. Run by `supabase test db`.

begin;
select plan(3);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Curry');
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-10-19');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',0,'Dinner','aaaaaaaa-0000-0000-0000-000000000004');

select lives_ok(
  $$ insert into batch_leftover (id, household_id, plan_entry_id, kept, binned)
     values ('aaaaaaaa-0000-0000-0000-000000000009','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000008',0.75,1) $$,
  'an answer in portions, fractions and all'
);

select throws_ok(
  $$ update batch_leftover set binned = -1
     where id = 'aaaaaaaa-0000-0000-0000-000000000009' $$,
  '23514',
  null,
  'a negative portion is refused'
);

delete from plan_entry where id = 'aaaaaaaa-0000-0000-0000-000000000008';
select is(
  (select count(*)::int from batch_leftover),
  0,
  'the answer goes with the meal it is keyed to'
);

select * from finish();
rollback;
