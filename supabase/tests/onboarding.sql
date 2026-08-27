-- pgTAP: step-7 onboarding + the household_id access-token hook (migration 0007).
--
-- ensure_onboarded() is what the app calls after sign-in: it must be idempotent,
-- put the first two users into one household (v1 = two people), and give a third
-- user a fresh household with the starter vocab cloned in. add_household_claim()
-- must inject the caller's household_id into the JWT for the sync rules.
--
-- Runs against the seeded local DB (the "Home" household 0000…aa holds the 291-
-- row starter vocab and its aliases). Run by `supabase test db`.

begin;
select plan(9);

-- Isolate from any pre-existing memberships (a live dev session may have onboarded
-- users into the seeded Home). All rolled back at the end. This makes the
-- join-vs-create logic deterministic: Home starts with zero members again, so the
-- first two users join it and the third (Home full) gets a fresh household.
delete from household_member;

-- Three authenticated users; no user_metadata, so display_name falls back to the
-- email local-part (the dev email/password path).
insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111','authenticated','authenticated','ada@x.com'),
 ('00000000-0000-0000-0000-000000000000','b2222222-2222-2222-2222-222222222222','authenticated','authenticated','jun@x.com'),
 ('00000000-0000-0000-0000-000000000000','c3333333-3333-3333-3333-333333333333','authenticated','authenticated','carol@x.com');

set local role authenticated;

-- User A joins the seeded Home household…
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated","email":"ada@x.com"}';
select is(
  ensure_onboarded(),
  '00000000-0000-0000-0000-0000000000aa'::uuid,
  'A joins the seeded Home household'
);
-- …and calling again is a no-op (idempotent).
select is(
  ensure_onboarded(),
  '00000000-0000-0000-0000-0000000000aa'::uuid,
  'ensure_onboarded() is idempotent'
);
select is(
  (select display_name from household_member where auth_user_id = 'a1111111-1111-1111-1111-111111111111'),
  'ada',
  'display_name falls back to the email local-part'
);

-- User B fills the second seat of the same household.
set local request.jwt.claims = '{"sub":"b2222222-2222-2222-2222-222222222222","role":"authenticated","email":"jun@x.com"}';
select is(
  ensure_onboarded(),
  '00000000-0000-0000-0000-0000000000aa'::uuid,
  'B joins the same (two-person) household'
);
select is(
  (select count(*)::int from household_member
     where household_id = '00000000-0000-0000-0000-0000000000aa' and deleted_at is null),
  2,
  'Home now has exactly two members'
);
select is(
  (select sort_order from household_member where auth_user_id = 'b2222222-2222-2222-2222-222222222222'),
  1,
  'the second member gets sort_order 1'
);

-- User C: Home is full, so C gets a fresh household with the vocab cloned in.
set local request.jwt.claims = '{"sub":"c3333333-3333-3333-3333-333333333333","role":"authenticated","email":"carol@x.com"}';
select isnt(
  ensure_onboarded(),
  '00000000-0000-0000-0000-0000000000aa'::uuid,
  'a third user gets a fresh household (Home is full)'
);

-- The next two counts span households (carol's clone vs Home), so drop back to
-- the (superuser) test role to see past RLS, which scopes each role to its own
-- household.
reset role;
select is(
  (select count(*)::int from ingredient i
     join household_member m on m.household_id = i.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333' and i.deleted_at is null),
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa' and deleted_at is null),
  'the fresh household clones the full starter vocab'
);
select is(
  (select count(*)::int from ingredient_alias a
     join household_member m on m.household_id = a.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333' and a.deleted_at is null),
  (select count(*)::int from ingredient_alias
     where household_id = '00000000-0000-0000-0000-0000000000aa' and deleted_at is null),
  'and clones every alias alongside its ingredient'
);

select * from finish();
rollback;
