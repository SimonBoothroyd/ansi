-- pgTAP: household_member.portion_factor (0026, exec plan 0027 front P).
--
-- P-D6: the column defaults to 1, so every member that existed before the
-- factor did reads exactly the head-count it always meant. P-D2: the range
-- check refuses what no segment could produce. P-D3: either member may set
-- either's — the UPDATE policy is household-scoped, not self-scoped — and
-- the grant is column-narrow: a client can move the factor and nothing else
-- on the row, and cannot reach another household's members at all.
-- Run by `supabase test db`.

begin;
select plan(9);

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111','authenticated','authenticated','ada@x.com'),
 ('00000000-0000-0000-0000-000000000000','b2222222-2222-2222-2222-222222222222','authenticated','authenticated','jun@x.com'),
 ('00000000-0000-0000-0000-000000000000','c3333333-3333-3333-3333-333333333333','authenticated','authenticated','carol@x.com');
insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');
insert into household_member (id, household_id, display_name, auth_user_id) values
 ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ada','a1111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Jun','b2222222-2222-2222-2222-222222222222'),
 ('bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Carol','c3333333-3333-3333-3333-333333333333');

-- P-D6: default 1 — a member row that never heard of the factor is a
-- one-portion eater, as the head-count always said.
select is(
  (select portion_factor from household_member
    where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1::numeric,
  'portion_factor defaults to 1'
);

-- P-D2: the range check, both ends.
select throws_ok(
  $$ update household_member set portion_factor = 0
       where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'a factor below ¼ is refused'
);
select throws_ok(
  $$ update household_member set portion_factor = 3.25
       where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null,
  'a factor above 3 is refused'
);
select lives_ok(
  $$ update household_member set portion_factor = 3
       where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'the ends of the range are in it'
);
update household_member set portion_factor = 1
  where id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- P-D3, as Ada (a1…): her partner's factor, her own, and not the neighbours'.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated","email":"ada@x.com"}';

update household_member set portion_factor = 0.75, updated_at = now()
  where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select is(
  (select portion_factor from household_member
    where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  0.75::numeric,
  'a member sets the partner''s factor (household-scoped, not self-scoped)'
);

update household_member set portion_factor = 1.25, updated_at = now()
  where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is(
  (select portion_factor from household_member
    where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1.25::numeric,
  'a member sets their own factor'
);

-- The grant is column-narrow: the client moves the factor and nothing else.
select throws_ok(
  $$ update household_member set display_name = 'Adalberta'
       where id = 'aaaaaaaa-0000-0000-0000-000000000002' $$,
  '42501', null,
  'the client cannot rename a member (no UPDATE grant on display_name)'
);
select throws_ok(
  $$ update household_member set auth_user_id = 'c3333333-3333-3333-3333-333333333333'
       where id = 'aaaaaaaa-0000-0000-0000-000000000002' $$,
  '42501', null,
  'the client cannot re-seat a member (no UPDATE grant on auth_user_id)'
);

-- Another household's member is not reachable: RLS filters the row away, so
-- the UPDATE touches nothing rather than failing loudly — read back as the
-- superuser, since Ada cannot even see the row to assert on it.
update household_member set portion_factor = 2, updated_at = now()
  where id = 'bbbbbbbb-0000-0000-0000-000000000001';
reset role;
select is(
  (select portion_factor from household_member
    where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1::numeric,
  'another household''s member is out of reach (untouched)'
);

select * from finish();
rollback;
