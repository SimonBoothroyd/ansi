-- pgTAP: household isolation + usda_food server-only (docs/SECURITY.md).
--
-- The durable version of the manual check run when 0001–0002 landed: RLS keeps
-- one household out of another's rows, and usda_food never reaches a client
-- role. Run by `supabase test db`.

begin;
select plan(6);

-- Two households, one member each, one ingredient each, one usda row.
insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','b@x.com');
insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');
insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','B1','22222222-2222-2222-2222-222222222222');
insert into ingredient (household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Flour','g','flour'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Sugar','g','sugar');
insert into usda_food (fdc_id, description, match_text) values
 (1,'Flour, all purpose','flour all purpose');

-- Act as authenticated user A.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  current_household_id(),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'current_household_id() resolves A from membership'
);
select is(
  (select count(*) from ingredient)::int, 1,
  'A sees exactly one ingredient (RLS filters B out)'
);
select is(
  (select canonical_name from ingredient), 'Flour',
  'the row A sees is its own (Flour, not Sugar)'
);
select throws_ok(
  $$ insert into ingredient (household_id, canonical_name, default_unit, match_text)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Contraband','g','contraband') $$,
  '42501',
  'new row violates row-level security policy for table "ingredient"',
  'A cannot insert into House B'
);
select throws_ok(
  $$ select count(*) from usda_food $$,
  '42501',
  'permission denied for table usda_food',
  'usda_food is denied to the authenticated (client) role'
);

-- usda_food is reachable server-side.
reset role;
set local role service_role;
select is(
  (select count(*) from usda_food)::int, 1,
  'service_role can read usda_food'
);

select * from finish();
rollback;
