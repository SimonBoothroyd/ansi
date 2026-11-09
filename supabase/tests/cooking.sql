-- pgTAP: cooking, cooking_change and plan_entry.cooking (0061, exec plan
-- 0062), and the conversion from 0060's leftover rows and pointers.
--
-- A cooking is a recipe or words, never both; words are always food said by
-- hand (a place and a date). Made is never negative. A change row belongs to
-- one cooking. A meal links to a cooking only as a recipe meal. The
-- conversion copies each `leftover` row to a cooking of the same id, links
-- every meal that pointed at a row or a batch, and only adds. Run by
-- `supabase test db`.

begin;
select plan(22);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Chili');
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-11-02');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',1,'Dinner','aaaaaaaa-0000-0000-0000-000000000004');

-- The tables.

select lives_ok(
  $$ insert into cooking (id, household_id, recipe_id)
     values ('aaaaaaaa-0000-0000-0000-0000000000c1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000004') $$,
  'a cooking of a recipe, still the live sum'
);

select lives_ok(
  $$ update cooking set made = 3.75
     where id = 'aaaaaaaa-0000-0000-0000-0000000000c1' $$,
  'made is fixed at the first tick, in fractional portions'
);

select throws_ok(
  $$ update cooking set made = -1
     where id = 'aaaaaaaa-0000-0000-0000-0000000000c1' $$,
  '23514', null, 'made is never negative'
);

select lives_ok(
  $$ insert into cooking (household_id, label, made, place, since)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Mum''s lasagne',2,'freezer','2026-11-01') $$,
  'food in the household''s own words, said by hand'
);

select throws_ok(
  $$ insert into cooking (household_id, label, made)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Rice',1) $$,
  '23514', null, 'words with no place or date are refused'
);

select throws_ok(
  $$ insert into cooking (household_id, recipe_id, label)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000004','Chili') $$,
  '23514', null, 'a recipe and words at once is refused'
);

select throws_ok(
  $$ insert into cooking (household_id, recipe_id, place)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000004','fridge') $$,
  '23514', null, 'a place without a date is refused'
);

select throws_ok(
  $$ insert into cooking (household_id, recipe_id, place, since)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000004','pantry','2026-11-01') $$,
  '23514', null, 'only the fridge or the freezer'
);

select lives_ok(
  $$ insert into cooking_change (household_id, cooking_id, fridge, freezer)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000000c1',-2,2) $$,
  'a freeze: two out of the fridge and into the freezer'
);

insert into cooking_change (id, household_id, cooking_id, freezer)
values ('aaaaaaaa-0000-0000-0000-0000000000d1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000000c1',1);
select is(
  (select fridge from cooking_change where id = 'aaaaaaaa-0000-0000-0000-0000000000d1'),
  0::numeric,
  'a shelf a change does not name moves by nothing'
);

select lives_ok(
  $$ update plan_entry set cooking = 'aaaaaaaa-0000-0000-0000-0000000000c1'
     where id = 'aaaaaaaa-0000-0000-0000-000000000008' $$,
  'a recipe meal links to a cooking'
);

select throws_ok(
  $$ insert into plan_entry (household_id, week_plan_id, day_of_week, meal_slot, label, cooking)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',
             4,'Lunch','Office lunch','aaaaaaaa-0000-0000-0000-0000000000c1') $$,
  '23514', null, 'a meal eaten out is not cooked in a pot'
);

select is(
  (select count(*)::int from pg_publication_tables
   where pubname = 'powersync' and tablename in ('cooking', 'cooking_change')),
  2,
  'both tables are published to PowerSync'
);

-- The conversion. A batch on Mon (b1) with a row naming it (lo1, corrected
-- and frozen), a meal planned from that batch (p1) and one from the row (p2);
-- a second batch (b2) nobody stored a row for, with a meal from it (p3); and
-- a row added by hand in words (lo2), gone.

insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-0000000000b1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',0,'Dinner','aaaaaaaa-0000-0000-0000-000000000004'),
 ('aaaaaaaa-0000-0000-0000-0000000000b2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',2,'Lunch','aaaaaaaa-0000-0000-0000-000000000004');
insert into leftover (id, household_id, place, recipe_id, label, portions, since, batch, gone_at, updated_at) values
 ('aaaaaaaa-0000-0000-0000-0000000000a1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','freezer','aaaaaaaa-0000-0000-0000-000000000004',null,2.5,'2026-11-02','aaaaaaaa-0000-0000-0000-0000000000b1',null,'2026-11-03T20:00:00Z'),
 ('aaaaaaaa-0000-0000-0000-0000000000a0','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','fridge','aaaaaaaa-0000-0000-0000-000000000004',null,4,'2026-11-02','aaaaaaaa-0000-0000-0000-0000000000b1',null,'2026-11-02T20:00:00Z'),
 ('aaaaaaaa-0000-0000-0000-0000000000a2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','fridge',null,'Soup',1,'2026-11-01',null,'2026-11-04T09:00:00Z','2026-11-04T09:00:00Z');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id, leftover_of, from_leftover) values
 ('aaaaaaaa-0000-0000-0000-0000000000f1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',3,'Lunch','aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-0000000000b1',null),
 ('aaaaaaaa-0000-0000-0000-0000000000f2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',4,'Lunch','aaaaaaaa-0000-0000-0000-000000000004',null,'aaaaaaaa-0000-0000-0000-0000000000a1'),
 ('aaaaaaaa-0000-0000-0000-0000000000f3','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',5,'Lunch','aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-0000000000b2',null);

select lives_ok($$ select cooking_from_leftover() $$, 'the conversion runs');

select results_eq(
  $$ select id::text, made, place, since::text, gone_at is not null
     from cooking where id in ('aaaaaaaa-0000-0000-0000-0000000000a1',
                               'aaaaaaaa-0000-0000-0000-0000000000a2')
     order by id $$,
  $$ values ('aaaaaaaa-0000-0000-0000-0000000000a1', 2.5::numeric, 'freezer', '2026-11-02', false),
            ('aaaaaaaa-0000-0000-0000-0000000000a2', 1::numeric, 'fridge', '2026-11-01', true) $$,
  'each stored row is a cooking of the same id: its count, place, date and gone'
);

select is(
  (select label from cooking where id = 'aaaaaaaa-0000-0000-0000-0000000000a2'),
  'Soup',
  'a row in words keeps its words'
);

select is(
  (select cooking::text from plan_entry where id = 'aaaaaaaa-0000-0000-0000-0000000000f2'),
  'aaaaaaaa-0000-0000-0000-0000000000a1',
  'a meal from a stored row eats from its cooking'
);

select is(
  (select cooking::text from plan_entry where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  'aaaaaaaa-0000-0000-0000-0000000000a1',
  'a meal from a batch eats from the newest row naming the batch'
);

select results_eq(
  $$ select c.made, c.place, p.cooking::text
     from plan_entry p join cooking c on c.id = p.cooking
     where p.id = 'aaaaaaaa-0000-0000-0000-0000000000f3' $$,
  $$ values (null::numeric, null::text, 'aaaaaaaa-0000-0000-0000-0000000000b2') $$,
  'a meal from a batch no row names eats from a cooking with the batch''s id, still the live sum'
);

select is(
  (select count(*)::int from cooking where id = 'aaaaaaaa-0000-0000-0000-0000000000b1'),
  0,
  'a batch a row names gets no cooking of its own'
);

select is(
  (select cooking from plan_entry where id = 'aaaaaaaa-0000-0000-0000-0000000000b1'),
  null,
  'the batch''s own meals are left for the app to group'
);

-- Only adds: run again, after the household changed a converted cooking.
update cooking set made = 1 where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';
select cooking_from_leftover();
select is(
  (select made from cooking where id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
  1::numeric,
  'a second run leaves what is there'
);

select * from finish();
rollback;
