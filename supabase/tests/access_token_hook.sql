-- pgTAP: the add_household_claim access-token hook (migrations 0007 + 0008).
--
-- The hook is load-bearing for sync: GoTrue calls it on every token issue, and
-- the PowerSync sync rules scope every bucket by the `household_id` claim it
-- injects (docker/powersync.yaml) — with no claim, nothing syncs. It must
-- inject the claim for an onboarded user, pass a not-yet-onboarded user's
-- event through UNCHANGED, ignore soft-deleted memberships, and (0008) resolve
-- multiple memberships deterministically — oldest first, exactly like
-- current_household_id(), so the claim and RLS never disagree.
--
-- Run by `supabase test db`.

begin;
select plan(5);

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-aaaa-aaaa-aaaa-111111111111','authenticated','authenticated','hook-a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-bbbb-bbbb-bbbb-222222222222','authenticated','authenticated','hook-b@x.com');
insert into household (id, name) values
 ('cccccccc-cccc-cccc-cccc-cccccccccccc','Hook House'),
 ('dddddddd-dddd-dddd-dddd-dddddddddddd','Older House'),
 ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','Dead House');
-- User A: one live membership (Hook House), plus a soft-deleted one that must
-- never win, plus — created EARLIER — a live membership in Older House, so the
-- deterministic order (created_at asc) is what picks the household.
insert into household_member (household_id, display_name, auth_user_id, created_at, deleted_at) values
 ('cccccccc-cccc-cccc-cccc-cccccccccccc','A','11111111-aaaa-aaaa-aaaa-111111111111', now(),               null),
 ('dddddddd-dddd-dddd-dddd-dddddddddddd','A','11111111-aaaa-aaaa-aaaa-111111111111', now() - interval '1 day', null),
 ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','A','11111111-aaaa-aaaa-aaaa-111111111111', now() - interval '2 days', now());

-- An onboarded user's event gains the household_id claim…
select is(
  add_household_claim(
    '{"user_id":"11111111-aaaa-aaaa-aaaa-111111111111","claims":{"role":"authenticated","aud":"authenticated"}}'::jsonb
  ) -> 'claims' ->> 'household_id',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'the hook injects the oldest live membership''s household_id (deterministic, skips soft-deleted)'
);
-- …without disturbing the claims that were already there.
select is(
  add_household_claim(
    '{"user_id":"11111111-aaaa-aaaa-aaaa-111111111111","claims":{"role":"authenticated","aud":"authenticated"}}'::jsonb
  ) -> 'claims' ->> 'role',
  'authenticated',
  'existing claims survive the injection'
);

-- The claim must agree with what RLS resolves for the same user.
set local request.jwt.claims = '{"sub":"11111111-aaaa-aaaa-aaaa-111111111111","role":"authenticated"}';
select is(
  add_household_claim(
    jsonb_build_object('user_id', '11111111-aaaa-aaaa-aaaa-111111111111', 'claims', '{}'::jsonb)
  ) -> 'claims' ->> 'household_id',
  current_household_id()::text,
  'the hook and current_household_id() resolve the same membership'
);

-- A user with no membership (signed in, not yet onboarded) passes through
-- completely unchanged — no claim, no error, token still issues.
select is(
  add_household_claim(
    '{"user_id":"22222222-bbbb-bbbb-bbbb-222222222222","claims":{"role":"authenticated"}}'::jsonb
  ),
  '{"user_id":"22222222-bbbb-bbbb-bbbb-222222222222","claims":{"role":"authenticated"}}'::jsonb,
  'a not-yet-onboarded user''s event passes through unchanged'
);

-- Lock-down: only supabase_auth_admin (GoTrue) may execute the hook.
select ok(
  not has_function_privilege('authenticated', 'add_household_claim(jsonb)', 'execute')
  and has_function_privilege('supabase_auth_admin', 'add_household_claim(jsonb)', 'execute'),
  'the hook is executable by supabase_auth_admin and not by clients'
);

select * from finish();
rollback;
