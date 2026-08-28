-- pgTAP: step-7 onboarding, hardened in 0008 (advisory lock, template clone).
--
-- ensure_onboarded() is what the app calls after sign-in. It must: serialise
-- concurrent onboards on an advisory lock; never join a template household;
-- give a first user a fresh household with the template vocab cloned in
-- (EXCLUDING `source = 'manual'` ingredients and `'import_correction'`
-- aliases — a household's private typed-in data); let a second user fill the
-- open seat; give a third a fresh clone; and cleanly no-op the clone (empty
-- vocab) when no template exists. Idempotent throughout.
--
-- Runs against the seeded local DB (the template "Home" household 0000…aa
-- holds the starter vocab and its aliases). Run by `supabase test db`.

begin;
select plan(18);

-- Isolate from any pre-existing memberships (a live dev session may have
-- onboarded users). All rolled back at the end.
delete from household_member;

-- Private, typed-in rows inside the template household: the clone must leave
-- both behind. (In real life a template never accumulates these — this pins
-- the exclusion anyway.)
insert into ingredient (household_id, canonical_name, default_unit, source, match_text)
values ('00000000-0000-0000-0000-0000000000aa', 'Secret Sauce', 'tbsp', 'manual', 'secret sauce');
insert into ingredient_alias (household_id, ingredient_id, alias_text, match_text, source)
select '00000000-0000-0000-0000-0000000000aa', id, 'private correction', 'private correction', 'import_correction'
from ingredient
where household_id = '00000000-0000-0000-0000-0000000000aa' and match_text = 'olive oil';

-- Measures (0009): one on a curated template row (guarantees a non-zero clone
-- even if the seeded starter measures change) and one on the manual ingredient
-- (which must stay behind with its ingredient).
insert into ingredient_measure (household_id, ingredient_id, label, grams)
select '00000000-0000-0000-0000-0000000000aa', id, 'glug (test)', 12
from ingredient
where household_id = '00000000-0000-0000-0000-0000000000aa' and match_text = 'olive oil';
insert into ingredient_measure (household_id, ingredient_id, label, grams)
select '00000000-0000-0000-0000-0000000000aa', id, 'secret scoop', 30
from ingredient
where household_id = '00000000-0000-0000-0000-0000000000aa' and match_text = 'secret sauce';

-- Five authenticated users; no user_metadata, so display_name falls back to
-- the email local-part (the dev email/password path). e5… is a filler used to
-- close the last open seat before the no-template case.
insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111','authenticated','authenticated','ada@x.com'),
 ('00000000-0000-0000-0000-000000000000','b2222222-2222-2222-2222-222222222222','authenticated','authenticated','jun@x.com'),
 ('00000000-0000-0000-0000-000000000000','c3333333-3333-3333-3333-333333333333','authenticated','authenticated','carol@x.com'),
 ('00000000-0000-0000-0000-000000000000','d4444444-4444-4444-4444-444444444444','authenticated','authenticated','dee@x.com'),
 ('00000000-0000-0000-0000-000000000000','e5555555-5555-5555-5555-555555555555','authenticated','authenticated','eve@x.com');

set local role authenticated;

-- User A: the template is never joinable, so A gets a fresh household…
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated","email":"ada@x.com"}';
select isnt(
  ensure_onboarded(),
  '00000000-0000-0000-0000-0000000000aa'::uuid,
  'A never joins the template household — gets a fresh one'
);
-- …the onboard ran under the advisory lock (xact-scoped: still held here)…
select ok(
  exists(select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()),
  'ensure_onboarded() takes the onboarding advisory lock'
);
-- Remember A's household for cross-user assertions (a tx-scoped GUC — later
-- statements can't re-derive it under another user's RLS + statement snapshot).
do $$ begin
  perform set_config('test.hh_a',
    (select household_id::text from household_member
      where auth_user_id = 'a1111111-1111-1111-1111-111111111111'), true);
end $$;
-- …and calling again is a no-op (idempotent).
select is(
  ensure_onboarded(),
  current_setting('test.hh_a')::uuid,
  'ensure_onboarded() is idempotent'
);
select is(
  (select display_name from household_member where auth_user_id = 'a1111111-1111-1111-1111-111111111111'),
  'ada',
  'display_name falls back to the email local-part'
);

-- User B fills the open seat in A's household.
set local request.jwt.claims = '{"sub":"b2222222-2222-2222-2222-222222222222","role":"authenticated","email":"jun@x.com"}';
select is(
  ensure_onboarded(),
  current_setting('test.hh_a')::uuid,
  'B fills the open seat in A''s household'
);
select is(
  (select sort_order from household_member where auth_user_id = 'b2222222-2222-2222-2222-222222222222'),
  1,
  'the second member gets sort_order 1'
);

-- User C: A's household is full, so C gets another fresh clone.
set local request.jwt.claims = '{"sub":"c3333333-3333-3333-3333-333333333333","role":"authenticated","email":"carol@x.com"}';
select isnt(
  ensure_onboarded(),
  current_setting('test.hh_a')::uuid,
  'a third user gets a fresh household (A''s is full)'
);
select isnt(
  ensure_onboarded(),
  '00000000-0000-0000-0000-0000000000aa'::uuid,
  'the third user''s household is not the template either'
);

-- Cross-household assertions need to see past RLS: back to the superuser role.
reset role;
select is(
  (select count(*)::int from household_member
     where household_id = current_setting('test.hh_a')::uuid and deleted_at is null),
  2,
  'A''s household has exactly two members'
);
select is(
  (select count(*)::int from household_member
     where household_id = '00000000-0000-0000-0000-0000000000aa' and deleted_at is null),
  0,
  'the template household stays member-less (never syncs, never read via RLS)'
);

-- The clone copies the full curated template vocab…
select is(
  (select count(*)::int from ingredient i
     join household_member m on m.household_id = i.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333' and i.deleted_at is null),
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null and source is distinct from 'manual'),
  'the fresh household clones the template vocab minus manual rows'
);
select is(
  (select count(*)::int from ingredient_alias a
     join household_member m on m.household_id = a.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333' and a.deleted_at is null),
  (select count(*)::int from ingredient_alias a
     join ingredient i on i.id = a.ingredient_id
     where a.household_id = '00000000-0000-0000-0000-0000000000aa'
       and a.deleted_at is null and a.source <> 'import_correction'
       and i.source is distinct from 'manual'),
  'and every alias except import corrections (and manual-ingredient aliases)'
);
select is(
  (select count(*)::int from ingredient_measure im
     join household_member m on m.household_id = im.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333' and im.deleted_at is null),
  (select count(*)::int from ingredient_measure im
     join ingredient i on i.id = im.ingredient_id
     where im.household_id = '00000000-0000-0000-0000-0000000000aa'
       and im.deleted_at is null and i.source is distinct from 'manual'),
  'and every measure of a cloned ingredient (0009)'
);
-- …but never the private rows themselves.
select is(
  (select count(*)::int from ingredient i
     join household_member m on m.household_id = i.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333'
       and i.match_text = 'secret sauce'),
  0,
  'a manual (typed-in) ingredient never leaves the source household'
);
select is(
  (select count(*)::int from ingredient_measure im
     join household_member m on m.household_id = im.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333'
       and im.label = 'secret scoop'),
  0,
  'a measure on a manual ingredient never leaves the source household'
);
select is(
  (select count(*)::int from ingredient_alias a
     join household_member m on m.household_id = a.household_id
     where m.auth_user_id = 'c3333333-3333-3333-3333-333333333333'
       and a.source = 'import_correction'),
  0,
  'an import_correction alias never leaves the source household'
);

-- No template at all (the empty-cloud case): the clone cleanly no-ops.
-- Close C's open seat with a filler member so D must take the create path,
-- and soft-delete the template (just clearing is_template would instead turn
-- the member-less Home into an open, joinable household).
insert into household_member (household_id, display_name, auth_user_id)
select household_id, 'Eve', 'e5555555-5555-5555-5555-555555555555'
from household_member where auth_user_id = 'c3333333-3333-3333-3333-333333333333';
update household set deleted_at = now() where is_template;

set local role authenticated;
set local request.jwt.claims = '{"sub":"d4444444-4444-4444-4444-444444444444","role":"authenticated","email":"dee@x.com"}';
select lives_ok(
  $$ select ensure_onboarded() $$,
  'no template household → onboarding still succeeds'
);
reset role;
select is(
  (select count(*)::int from ingredient i
     join household_member m on m.household_id = i.household_id
     where m.auth_user_id = 'd4444444-4444-4444-4444-444444444444'),
  0,
  'and the new household simply starts with an empty vocab'
);

select * from finish();
rollback;
