-- pgTAP: a recipe's share link (0054, exec plan 0051 phase 1).
--
-- What is defended here:
--   * the TOKEN — minted by the server, 22 url-safe characters, the same one
--     returned while the link is live, a fresh one after a revoke, and never
--     a shape a client chose;
--   * the ONE WRITE PATH — a member can read their household's shares and
--     cannot insert or update one directly, because a client-written row
--     could point at another household's recipe and the public page would
--     publish it;
--   * the OWNERSHIP check in both functions — another household's recipe is
--     refused (42501) exactly as a deleted one is, and the refusal moves no
--     row;
--   * ISOLATION — household B sees none of A's shares, anon can call
--     neither function, and service_role (the share page) reads by token.
--
-- Run by `supabase test db`.

begin;
select plan(27);

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','share-a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','share-b@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','B1','22222222-2222-2222-2222-222222222222');

insert into recipe (id, household_id, title, deleted_at) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Miso Noodles', null),
 ('aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Old Stew', now()),
 ('bbbbbbbb-0000-0000-0000-000000000101','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Dal', null);

-- The answers, kept across role switches. Granted so `authenticated` can
-- write them; rolled back with everything else.
create table share_seen (k text primary key, v text);
grant select, insert, update on share_seen to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- The shape, as the owner.
-- ---------------------------------------------------------------------------

select has_table('recipe_share');
select is(
  (select relrowsecurity from pg_class where relname = 'recipe_share'),
  true, 'RLS is on');
select throws_ok(
  $$ insert into recipe_share (household_id, recipe_id, token)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000101', 'guessable') $$,
  '23514', null, 'a token that is not 22 url-safe characters is refused');
select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'powersync' and tablename = 'recipe_share'),
  0, 'not synced: the app asks the functions');

-- ---------------------------------------------------------------------------
-- House A shares, as a member.
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

insert into share_seen
  values ('first', share_recipe('aaaaaaaa-0000-0000-0000-000000000101'));

select matches(
  (select v from share_seen where k = 'first'),
  '^[A-Za-z0-9_-]{22}$', 'a share mints 22 url-safe characters');
select is(
  share_recipe('aaaaaaaa-0000-0000-0000-000000000101'),
  (select v from share_seen where k = 'first'),
  'sharing again returns the same link');
select is(
  (select count(*)::int from recipe_share), 1,
  'one row: the second share minted nothing');
select is(
  (select household_id from recipe_share),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'the row belongs to the caller''s household');

-- The one write path.
select throws_ok(
  $$ insert into recipe_share (household_id, recipe_id, token)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'bbbbbbbb-0000-0000-0000-000000000101',
             'AAAAAAAAAAAAAAAAAAAAAA') $$,
  '42501', 'permission denied for table recipe_share',
  'a member cannot write a share row directly — not even in their own household');
select throws_ok(
  $$ update recipe_share set token = 'AAAAAAAAAAAAAAAAAAAAAA' $$,
  '42501', 'permission denied for table recipe_share',
  'a member cannot choose a token');

-- Ownership.
select throws_ok(
  $$ select share_recipe('bbbbbbbb-0000-0000-0000-000000000101') $$,
  '42501', null, 'another household''s recipe cannot be shared');
select throws_ok(
  $$ select share_recipe('aaaaaaaa-0000-0000-0000-000000000102') $$,
  '42501', null, 'a deleted recipe cannot be shared');
select throws_ok(
  $$ select share_recipe('cccccccc-0000-0000-0000-000000000101') $$,
  '42501', null, 'a recipe that does not exist answers the same as one that is not yours');
select throws_ok(
  $$ select unshare_recipe('bbbbbbbb-0000-0000-0000-000000000101') $$,
  '42501', null, 'another household''s recipe cannot be unshared');
select is(
  unshare_recipe('aaaaaaaa-0000-0000-0000-000000000102'), false,
  'a deleted recipe of one''s own can be unshared, and says there was nothing live');

-- Revoke, and share again.
select is(
  unshare_recipe('aaaaaaaa-0000-0000-0000-000000000101'), true,
  'stop sharing revokes the live link');
select is(
  unshare_recipe('aaaaaaaa-0000-0000-0000-000000000101'), false,
  'a second stop is not an error, and says there was nothing live');
select is(
  (select count(*)::int from recipe_share where deleted_at is null), 0,
  'no live link after a revoke');

insert into share_seen
  values ('second', share_recipe('aaaaaaaa-0000-0000-0000-000000000101'));

select isnt(
  (select v from share_seen where k = 'second'),
  (select v from share_seen where k = 'first'),
  'sharing after a revoke mints a fresh token');
select is(
  (select count(*)::int from recipe_share), 2,
  'the revoked row stays as history beside the live one');

-- ---------------------------------------------------------------------------
-- House B sees nothing of A's.
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from recipe_share), 0,
  'household B sees none of A''s shares');
select throws_ok(
  $$ select unshare_recipe('aaaaaaaa-0000-0000-0000-000000000101') $$,
  '42501', null, 'household B cannot revoke A''s link');

reset role;
select is(
  (select count(*)::int from recipe_share
    where recipe_id = 'aaaaaaaa-0000-0000-0000-000000000101'
      and deleted_at is null), 1,
  'B''s refused revoke moved nothing: A''s link is still live');

-- ---------------------------------------------------------------------------
-- anon and the share page.
-- ---------------------------------------------------------------------------

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok(
  $$ select share_recipe('aaaaaaaa-0000-0000-0000-000000000101') $$,
  '42501', null, 'anon cannot share');
select throws_ok(
  $$ select count(*) from recipe_share $$,
  '42501', null, 'anon cannot read the table');

-- The share page (phase 4) reads as service_role, by token alone.
set local role service_role;

select is(
  (select recipe_id from recipe_share
    where token = (select v from share_seen where k = 'second')
      and deleted_at is null),
  'aaaaaaaa-0000-0000-0000-000000000101'::uuid,
  'service_role finds the recipe by its live token');
select is(
  (select count(*)::int from recipe_share
    where token = (select v from share_seen where k = 'first')
      and deleted_at is null), 0,
  'a revoked token finds nothing live');

select * from finish();
rollback;
