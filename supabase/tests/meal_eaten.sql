-- pgTAP: meal_eaten (0055, exec plan 0054 phase 1).
--
-- A member ticks only their own meals. Reads are household-wide, so Ada sees
-- Jun's tick; every write — insert, untick, a moved member_id — is narrowed
-- to current_member_id(), so Ada can neither tick for Jun nor untick him.
-- Run by `supabase test db`.

begin;
select plan(9);

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111','authenticated','authenticated','ada@x.com'),
 ('00000000-0000-0000-0000-000000000000','b2222222-2222-2222-2222-222222222222','authenticated','authenticated','jun@x.com');
insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into household_member (id, household_id, display_name, auth_user_id) values
 ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ada','a1111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Jun','b2222222-2222-2222-2222-222222222222');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ragù');
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-10-19');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id, eaters) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',2,'Dinner','aaaaaaaa-0000-0000-0000-000000000004',
  '["aaaaaaaa-0000-0000-0000-000000000001","aaaaaaaa-0000-0000-0000-000000000002"]');
-- Jun's tick, written as Jun's phone would have.
insert into meal_eaten (id, household_id, plan_entry_id, member_id, eaten_at) values
 ('aaaaaaaa-0000-0000-0000-0000000000e2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-0000-0000-0000-000000000002','2026-10-21T19:40:00Z');

-- As Ada.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  current_member_id(),
  'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
  'current_member_id() resolves Ada''s own membership'
);

select lives_ok(
  $$ insert into meal_eaten (id, household_id, plan_entry_id, member_id, eaten_at)
     values ('aaaaaaaa-0000-0000-0000-0000000000e1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-0000-0000-0000-000000000001',
             '2026-10-21T19:42:00Z') $$,
  'Ada ticks her own meal'
);

select throws_ok(
  $$ insert into meal_eaten (household_id, plan_entry_id, member_id, eaten_at)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000008',
             'aaaaaaaa-0000-0000-0000-000000000002','2026-10-21T19:42:00Z') $$,
  '42501',
  'new row violates row-level security policy for table "meal_eaten"',
  'Ada cannot tick a meal for Jun'
);

select is(
  (select count(*)::int from meal_eaten),
  2,
  'Ada sees both ticks — her own and Jun''s'
);

-- Untick Jun: RLS filters the row out of the update, so nothing changes.
update meal_eaten set deleted_at = now(), updated_at = now()
  where id = 'aaaaaaaa-0000-0000-0000-0000000000e2';

select lives_ok(
  $$ update meal_eaten set eaten_at = '2026-10-21T18:30:00Z', updated_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-0000000000e1' $$,
  'Ada changes the time on her own tick'
);

select throws_ok(
  $$ update meal_eaten set member_id = 'aaaaaaaa-0000-0000-0000-000000000002'
     where id = 'aaaaaaaa-0000-0000-0000-0000000000e1' $$,
  '42501',
  'new row violates row-level security policy for table "meal_eaten"',
  'Ada cannot hand her tick to Jun'
);

select lives_ok(
  $$ update meal_eaten set deleted_at = now(), updated_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-0000000000e1' $$,
  'Ada unticks her own meal'
);

reset role;

select is(
  (select deleted_at is null from meal_eaten
    where id = 'aaaaaaaa-0000-0000-0000-0000000000e2'),
  true,
  'Ada''s untick of Jun''s row matched nothing — his tick stands'
);

select is(
  (select eaten_at from meal_eaten
    where id = 'aaaaaaaa-0000-0000-0000-0000000000e1'),
  '2026-10-21T18:30:00Z'::timestamptz,
  'the changed time is kept'
);

select * from finish();
rollback;
