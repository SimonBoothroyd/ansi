-- 0054_recipe_share.sql — a recipe's share link (exec plan 0051, phase 1).
--
-- One row per shared recipe: an unguessable token that a public page will
-- look up (phase 4, as service_role) to show that recipe read-only. Live, not
-- a snapshot: the row points at the recipe, it copies nothing.
--
-- **The token is minted here, never by a client.** Members may READ their
-- household's shares and nothing else; `share_recipe` and `unshare_recipe`
-- are the only writers. A client-written row could point its own household's
-- share at ANOTHER household's recipe id, and the public page would publish
-- it — so the functions are security definer by necessity, and each checks
-- the recipe is the caller's own before it touches a row.
--
-- One live link per recipe; sharing again returns it. Revoking stamps
-- `deleted_at` (deletes are soft), and the next share mints a fresh token.
-- Not synced: the app asks the functions, so no sync rule changes.

create table recipe_share (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references household(id),
  -- Cascades like `recipe_measure` (0048): with the recipe gone there is
  -- nothing left to show. A soft-deleted recipe keeps its row; the page reads
  -- `recipe.deleted_at` and answers 404.
  recipe_id    uuid not null references recipe(id) on delete cascade,
  -- 128 random bits, base64url, no padding: 22 characters from [A-Za-z0-9_-].
  -- Unique across ALL rows, revoked ones included, so a token is never
  -- reissued to name something else.
  token        text not null unique
    constraint recipe_share_token_shape check (token ~ '^[A-Za-z0-9_-]{22}$'),
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz           -- revoked: the link answers 404
);

-- At most one LIVE link per recipe — the "sharing again gives the same URL"
-- ruling. Revoked rows stay as history and do not count.
create unique index recipe_share_live_recipe_uq
  on recipe_share (recipe_id) where deleted_at is null;

comment on table recipe_share is
  'A recipe shared as a public, read-only link. `token` is what the link '
  'carries; the share page looks it up as service_role. Written only by '
  'share_recipe() / unshare_recipe(), which check the recipe is the caller''s '
  'own. A revoked link has deleted_at set; at most one live row per recipe.';

alter table recipe_share enable row level security;

-- Read-only to members: the ⋯ menu asks whether a recipe has a live link.
create policy recipe_share_read on recipe_share
  for select using (household_id = current_household_id());

grant select on recipe_share to authenticated;
grant all on recipe_share to service_role;

-- The live token for a recipe, minting one if there is none. Security definer:
-- the table has no client write grant (see the header). Refuses a recipe that
-- is not the caller's own, or that is deleted, with 42501 — the same answer
-- for both, since "not yours" must not say whether it exists.
create or replace function share_recipe(p_recipe_id uuid)
returns text
language plpgsql
security definer
-- `extensions` because that is where Supabase installs pgcrypto
-- (`gen_random_bytes`); `public` too, where 0000 would have put it on a bare
-- Postgres. Neither is writable by a client role.
set search_path = public, extensions
as $$
declare
  v_household uuid := current_household_id();
  v_token     text;
begin
  if v_household is null
     or not exists (
       select 1 from recipe r
        where r.id = p_recipe_id
          and r.household_id = v_household
          and r.deleted_at is null) then
    raise exception 'no recipe % you can share', p_recipe_id
      using errcode = '42501';
  end if;

  -- Two devices sharing at once must agree on one link, not race the unique
  -- index; per recipe, transaction-scoped (0008's shape).
  perform pg_advisory_xact_lock(hashtext('share_recipe:' || p_recipe_id::text));

  select s.token into v_token
    from recipe_share s
   where s.recipe_id = p_recipe_id
     and s.deleted_at is null;

  if v_token is null then
    v_token := rtrim(translate(
      encode(gen_random_bytes(16), 'base64'), '+/', '-_'), '=');
    insert into recipe_share (household_id, recipe_id, token)
    values (v_household, p_recipe_id, v_token);
  end if;

  return v_token;
end
$$;

comment on function share_recipe(uuid) is
  'The live share token for one of the caller''s own recipes, minted if '
  'there is none. 42501 for a recipe that is not theirs or is deleted.';

-- Revokes the recipe's live link. True when one was revoked, false when there
-- was none — a second tap is not an error. Refuses another household's recipe
-- exactly as share_recipe does; a deleted recipe of one's own may still be
-- unshared.
create or replace function unshare_recipe(p_recipe_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household uuid := current_household_id();
begin
  if v_household is null
     or not exists (
       select 1 from recipe r
        where r.id = p_recipe_id
          and r.household_id = v_household) then
    raise exception 'no recipe % you can unshare', p_recipe_id
      using errcode = '42501';
  end if;

  update recipe_share
     set deleted_at = now()
   where recipe_id = p_recipe_id
     and deleted_at is null;

  return found;
end
$$;

comment on function unshare_recipe(uuid) is
  'Revokes the live share link of one of the caller''s own recipes. True when '
  'a link was revoked, false when there was none.';

revoke execute on function share_recipe(uuid) from public, anon;
revoke execute on function unshare_recipe(uuid) from public, anon;
grant execute on function share_recipe(uuid) to authenticated;
grant execute on function unshare_recipe(uuid) to authenticated;
