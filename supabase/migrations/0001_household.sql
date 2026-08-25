-- 0001_household.sql — the household + members, and the RLS anchor.
--
-- Everything in the app is scoped to a household (spec §3). This migration lands
-- the two tables that scope defines (spec §51–53) and the helper every later
-- policy calls to answer "which household is the caller in?". Keep it minimal:
-- full auth/onboarding and the PowerSync token wiring are step 7 — this is only
-- the ground the ingredient model (0002) needs to stand on.

create table household (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz            -- soft-delete tombstone (spec §3)
);

create table household_member (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  display_name  text not null,       -- the named person; eaters[] point here
  auth_user_id  uuid not null references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (household_id, auth_user_id)
);

-- The RLS anchor. Resolves the caller's household from their membership — no
-- custom JWT claim required, so it works before the step-7 token hook exists.
-- SECURITY DEFINER so policies can call it without recursing through
-- household_member's own RLS; STABLE so the planner can cache it per statement.
create or replace function current_household_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select household_id
  from household_member
  where auth_user_id = auth.uid()
    and deleted_at is null
  limit 1;
$$;

-- RLS: a member sees and edits only their own household. Inserts (creating a
-- household, adding a member) are onboarding — done server-side with the service
-- role, which bypasses RLS — so no insert policy ships here.
alter table household enable row level security;
alter table household_member enable row level security;

create policy household_read on household
  for select using (id = current_household_id());
create policy household_update on household
  for update using (id = current_household_id())
  with check (id = current_household_id());

create policy household_member_read on household_member
  for select using (household_id = current_household_id());

-- Table privileges. RLS only filters rows a role can already reach — the role
-- still needs the base grant. The app connects as `authenticated`; its grants
-- mirror the policies above (no DELETE — deletes are soft). `service_role` (edge
-- functions, onboarding) is trusted server-side and bypasses RLS. `anon` gets
-- nothing: the app is auth-only. (Local default privileges only auto-grant Dxt
-- here, so these are explicit rather than relying on that.)
grant select, update on household to authenticated;
grant select on household_member to authenticated;
grant all on household, household_member to service_role;

-- Sync these down so eaters[] can resolve names offline (rules land in step 7).
alter publication powersync add table household, household_member;
