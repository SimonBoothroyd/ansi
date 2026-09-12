-- 0043_household_week_start.sql — the household says which day its week
-- starts on, and every week it has planned is re-homed to match.
--
-- The ask is not the grid order. It is that **the week you shop for on a
-- Sunday contains that Sunday's dinner**. Under a Monday key a Sunday belongs
-- to the week that is ending: you shop on Sunday for "next week" and tonight's
-- meal is in the week you just left. 0019's own preamble already half-states
-- it — "you plan next week on a Sunday, so you must be able to shop for it on
-- a Sunday" — and the week redesign's D3 solved only the *viewing* half. This
-- is the other half: which seven days that week IS.
--
-- **The preference is a household fact, not a device one.** It decides the key
-- rows are WRITTEN under, so two devices disagreeing about it would not
-- disagree about a view — they would file meals into two different weeks. So
-- it is a synced column, shipped by the existing `select *` sync rules
-- (`docker/powersync.yaml`, `docker/powersync-cloud.streams.yaml`: no rule
-- change is needed, and none is made).
--
-- **`day_of_week` already means "offset from the key", not "calendar
-- weekday".** `planning_repository_impl` computes a meal's real date as
-- `date(wp.week_start_date, '+' || pe.day_of_week || ' days')`. That is why
-- the fix can be a re-key rather than a second convention: move the key, move
-- the offsets with it, and every reader — the three week-scoped repositories,
-- `copy last week`, the cook plan's shelf-life clustering — keeps binding one
-- date and one offset, exactly as it does today. The alternative (keep Monday
-- keys, draw a Sunday window from two stored weeks) breaks clustering, gives
-- a shopping tick two possible weeks, and lets one displayed week hold two
-- contradictory recipe variants.
--
-- ---------------------------------------------------------------------------
-- Two kinds of thing move, and each moves by the same idea
-- ---------------------------------------------------------------------------
--
-- Flipping the preference and moving the weeks must be ONE transaction, or a
-- device can see "new preference, old keys" and draw Monday's meals under
-- Sunday. So the flip is a server function the client calls, and it is
-- ONLINE-ONLY — a deliberate, narrow break from "everything works offline",
-- with precedent in the online-only match engine (ADR-0004).
--
-- **A meal is a DATE.** It is re-filed into the week its own calendar date
-- falls in, and its offset is however many days that is from the new key. The
-- date is the fact; the address is the bookkeeping. Nothing about a meal is
-- re-derived: it keeps its recipe, its eaters, its portions and the evening it
-- is eaten on.
--
-- **A week and a tick are a WINDOW.** A week keyed K covers K..K+6, and a tick
-- names a shopping trip for that window. So each is re-keyed to the
-- new-residue window it overlaps MOST — the window holding its midpoint,
-- `week_rekey(K) = week_key_for(K + 3, starts_on)`. A week already at the
-- right residue rekeys to itself, so this stays residue-driven.
--
-- That choice is what makes the whole thing invertible, which is the property
-- D4 ("flip it as often as you like") actually rests on:
--
--   * Mon → Sun: K = Mon 7 Sep, midpoint Thu 10, which sits in the Sunday week
--     beginning **Sun 6** — the design doc's `shift = 1` table, exactly;
--   * Sun → Mon: K = Sun 6 Sep, midpoint Wed 9, which sits in the Monday week
--     beginning **Mon 7**. The week comes home.
--
-- A naive "always slide the key down to the previous new-residue day" agrees
-- with the doc for the short shifts it worked (1..3 days) and takes the long
-- way round for the rest: Sun 6 would slide back to Mon 31 Aug, stranding that
-- week's shopping ticks in the previous week's list and leaving an emptied week
-- row behind on every flip back. The midpoint takes the short road in both
-- directions, so a round trip restores every week row, every tick and every
-- variant to the address it started at, and creates no rows at all.
--
-- What each table does, then:
--
--   * `week_plan.week_start_date := week_rekey(week_start_date)`;
--   * `plan_entry` is re-filed by its meal date. In practice that keeps it in
--     its own moved week unless the date falls outside it, in which case it
--     joins the neighbour — the Sunday of a Monday week joining the Sunday week
--     that opens on it, and the same journey backwards on the way home;
--   * `shopping_list_entry.week_start_date := week_rekey(week_start_date)`. A
--     tick is a state about a TRIP, not about a meal, so it follows the window
--     it was made for. A NULL week stays NULL, exactly as 0019/0036 left it;
--   * `week_recipe_line_override` rides `week_plan_id` for free — with one
--     residual case: a recipe planned ONLY on the day that leaves would have
--     its variant stay behind. So the variant is carried to the week its meals
--     went to when that week has none for the same (recipe, line), and kept
--     where it is when the recipe still has meals in the old week. One variant
--     per (week, recipe) is the rule, and after the split both weeks
--     legitimately have one;
--   * everything moved has `updated_at` bumped, because that is what PowerSync
--     syncs the change down on.
--
-- **Residue-driven, per week, so it is also the repair tool.** The function
-- asks each week whether its own key matches the start day, never the
-- household as a whole. Three things fall out of that:
--
--   1. re-running it changes nothing;
--   2. flipping back is the same function with the other number;
--   3. a meal queued OFFLINE across the flip uploads under the old convention
--      and creates a week at the wrong residue. A household with mixed keys is
--      then repaired rather than skipped — so the repair is one tap rather than
--      a support incident.
--
-- **The unique index survives, and not by luck.** `week_plan` is
-- `unique (household_id, week_start_date)` and is not deferrable, so a
-- half-finished re-key must never sit on a key another row still holds. It
-- cannot: every new key has the household's new residue, so a week that is
-- still waiting its turn can only be in the way if ITS key already has that
-- residue — and a week at the right residue rekeys to itself and never moves.
-- Such a clash is therefore permanent, not transient: two rows genuinely
-- claiming one window, which is the offline orphan. (Two weeks at the same old
-- residue cannot collide either: they are ≥ 7 days apart and each moves at most
-- 3.) The orphan gives up its meals to the resident — they were re-filed by
-- date a moment earlier, so this is bookkeeping, not a move — and is tombstoned
-- empty. No row's content is dropped.
--
-- Row-preserving under docs/cloud-setup.md §2c: additive column, no drop, no
-- rewrite of anybody's content, and the one soft delete it can perform is of a
-- week row whose meals now live next door.

-- ---------------------------------------------------------------------------
-- 1 · The column.
-- ---------------------------------------------------------------------------
--
-- ISO weekday, 1 = Monday … 7 = Sunday — the same numbering as Dart's
-- `DateTime.weekday` and Postgres's `isodow`, so the client, the server and a
-- person at a SQL prompt all read one number the same way. Default 1 is what
-- every household has meant since 0005.
alter table household
  add column week_starts_on smallint not null default 1
    check (week_starts_on between 1 and 7);

-- 0008 narrowed 0001's table-level UPDATE grant to the columns a member may
-- edit, so that nobody can flip `is_template` and turn their own household into
-- the clone source every future onboarder copies. The new column joins that
-- list — the flip runs as the caller (below), so without this the door is shut
-- — and `is_template` stays off it, which is the whole point of the narrowing.
grant update (name, updated_at, deleted_at, week_starts_on)
  on household to authenticated;

comment on column household.week_starts_on is
  'The ISO weekday this household''s week begins on: 1 = Monday … 7 = Sunday, '
  'matching DateTime.weekday and Postgres isodow. It is the residue every '
  'week_plan.week_start_date and shopping_list_entry.week_start_date of the '
  'household is keyed to; change it only through set_household_week_start(), '
  'which moves the weeks in the same transaction.';

-- ---------------------------------------------------------------------------
-- 2 · The two questions the re-home asks, each answered in one place.
-- ---------------------------------------------------------------------------
--
-- `week_key_for` is asked of a DATE: which week does this evening's dinner
-- belong to. `week_rekey` is asked of a WINDOW: this week covers seven days —
-- which of the new weeks is it? Keeping them apart is the whole correctness
-- story, and keeping each to one definition is what stops the function from
-- answering the same question three slightly different ways.
create or replace function week_key_for(p_date date, p_starts_on smallint)
returns date
language sql
immutable
as $$
  select p_date - ((extract(isodow from p_date)::int - p_starts_on + 7) % 7);
$$;

comment on function week_key_for(date, smallint) is
  'The first day of the week containing p_date for a household that starts its '
  'week on ISO weekday p_starts_on (1 = Monday … 7 = Sunday). A date already '
  'on that weekday is its own key, so `week_start_date = week_key_for('
  'week_start_date, starts_on)` is exactly "this week is at the right '
  'residue".';

create or replace function week_rekey(p_key date, p_starts_on smallint)
returns date
language sql
immutable
as $$
  select week_key_for(p_key + 3, p_starts_on);
$$;

comment on function week_rekey(date, smallint) is
  'Where a week (or a shopping tick) keyed p_key belongs once the household '
  'starts its week on p_starts_on: the new-residue window it overlaps most, '
  'which is the one holding its midpoint. Moves a key by at most three days '
  'in either direction, is the identity on a key already at the right residue, '
  'and is its own inverse across a flip and a flip back — which is what makes '
  'a week row and its ticks come home rather than drift a week earlier each '
  'time.';

-- ---------------------------------------------------------------------------
-- 3 · The flip.
-- ---------------------------------------------------------------------------
--
-- SECURITY INVOKER (the default, stated out loud): the caller is the
-- household's own member and every statement below is fenced by the ordinary
-- RLS policies of 0001/0005/0006/0040. A household that is not yours is
-- invisible to the first SELECT, so the function refuses instead of quietly
-- touching nothing. There is no reason for this door to be wider than the
-- tables behind it — it writes only rows the caller could already write.
create or replace function set_household_week_start(
  p_household_id uuid,
  p_starts_on    smallint
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_current    smallint;
  -- The weeks whose key moves EARLIER, and the weeks whose key moves LATER.
  -- Read before anything moves, and used only by the variant carry, which has
  -- to know which side of its old week the departing meals went out of.
  v_earlier    uuid[];
  v_later      uuid[];
  v_taken      boolean;
  w            record;
begin
  if p_starts_on is null or p_starts_on not between 1 and 7 then
    raise exception
      'week_starts_on must be an ISO weekday 1..7 (1 = Monday … 7 = Sunday), got %',
      coalesce(p_starts_on::text, 'null')
      using errcode = '22023';
  end if;

  -- Two devices flipping at once must queue rather than interleave their
  -- re-homes. The lock is per household and transaction-scoped, the shape
  -- `ensure_onboarded` has used since 0008 — and unlike `select … for update`
  -- it needs no table-wide UPDATE privilege, which 0008 deliberately took away.
  perform pg_advisory_xact_lock(
    hashtext('set_household_week_start:' || p_household_id::text));

  -- RLS hides every other household, so `not found` is "not yours" as surely
  -- as it is "no such row" — and saying so is better than touching nothing and
  -- reporting success.
  select h.week_starts_on into v_current
    from household h
   where h.id = p_household_id
     and h.deleted_at is null;

  if not found then
    raise exception 'no household % you can write to', p_household_id
      using errcode = '42501',
            hint = 'The flip runs as a member of the household it names.';
  end if;

  if v_current is distinct from p_starts_on then
    update household
       set week_starts_on = p_starts_on,
           updated_at     = now()
     where id = p_household_id;
  end if;

  select coalesce(array_agg(wp.id) filter (
           where week_rekey(wp.week_start_date, p_starts_on)
                 < wp.week_start_date), '{}'::uuid[]),
         coalesce(array_agg(wp.id) filter (
           where week_rekey(wp.week_start_date, p_starts_on)
                 > wp.week_start_date), '{}'::uuid[])
    into v_earlier, v_later
    from week_plan wp
   where wp.household_id = p_household_id;

  -- 3a · The weeks a meal is about to need but the household has not got.
  --
  -- Only the crossing case reaches here: a meal whose date falls outside its
  -- own moved week belongs to the neighbour, and that week may never have been
  -- planned. An existing week is matched by the key it is ABOUT to have rather
  -- than the one it has now, so this creates no duplicates — and the row it
  -- inserts is already at the right residue, so it is never in anybody's way.
  insert into week_plan (household_id, week_start_date)
  select distinct p_household_id, d.dest_key
    from (
      select week_key_for(wp.week_start_date + pe.day_of_week, p_starts_on)
               as dest_key
        from plan_entry pe
        join week_plan wp on wp.id = pe.week_plan_id
       where pe.household_id = p_household_id
    ) d
   where not exists (
     select 1
       from week_plan v
      where v.household_id = p_household_id
        and week_rekey(v.week_start_date, p_starts_on) = d.dest_key);

  -- 3b · Every meal lands on the week its own calendar date falls in.
  --
  -- Written as "the date is the fact" rather than "add the shift to the
  -- offset": both give the design doc's table for a clean household, but only
  -- this one also repairs a household whose weeks are at two different
  -- residues, and only this one is obviously correct when the meal crosses into
  -- a neighbouring week — in either direction. `canon` picks ONE destination
  -- per window: the week already at the right residue when there is one, and
  -- otherwise the lowest key, which is the same row 3c below leaves standing.
  --
  -- Soft-deleted meals move too: an address is not a visibility, and an
  -- undelete must not surface a meal on the wrong day.
  with dest as (
    select pe.id as entry_id,
           wp.week_start_date + pe.day_of_week as meal_date,
           week_key_for(wp.week_start_date + pe.day_of_week, p_starts_on)
             as dest_key
      from plan_entry pe
      join week_plan wp on wp.id = pe.week_plan_id
     where pe.household_id = p_household_id
  ),
  canon as (
    select distinct on (week_rekey(v.week_start_date, p_starts_on))
           week_rekey(v.week_start_date, p_starts_on) as target,
           v.id
      from week_plan v
     where v.household_id = p_household_id
     order by week_rekey(v.week_start_date, p_starts_on),
              (v.week_start_date
                is distinct from week_rekey(v.week_start_date, p_starts_on)),
              v.week_start_date, v.id
  )
  update plan_entry pe
     set week_plan_id = c.id,
         day_of_week  = d.meal_date - d.dest_key,
         updated_at   = now()
    from dest d
    join canon c on c.target = d.dest_key
   where pe.id = d.entry_id
     and (pe.week_plan_id is distinct from c.id
          or pe.day_of_week is distinct from (d.meal_date - d.dest_key));

  -- 3c · The weeks themselves.
  --
  -- A loop rather than one UPDATE because of the duplicate branch, not because
  -- of the unique index: as the header proves, a week still waiting its turn
  -- can only be in the way if it is already at the right residue, in which case
  -- it never moves and the clash is a real duplicate. The order is ascending so
  -- that when two off-residue weeks DO claim one window, the row left standing
  -- is the same one `canon` above filed the meals under.
  for w in
    select wp.id,
           wp.deleted_at,
           week_rekey(wp.week_start_date, p_starts_on) as target
      from week_plan wp
     where wp.household_id = p_household_id
       and wp.week_start_date
           <> week_rekey(wp.week_start_date, p_starts_on)
     order by wp.week_start_date, wp.id
  loop
    select exists (
      select 1
        from week_plan v
       where v.household_id = p_household_id
         and v.week_start_date = w.target
         and v.id <> w.id)
      into v_taken;

    if v_taken then
      -- The offline orphan: two rows for one window. Its meals moved to the
      -- resident in 3b, so what is left is an empty duplicate, and two week
      -- rows covering the same seven days is the state every week-scoped read
      -- assumes cannot happen.
      if w.deleted_at is null then
        update week_plan
           set deleted_at = now(),
               updated_at = now()
         where id = w.id;
      end if;
    else
      update week_plan
         set week_start_date = w.target,
             updated_at      = now()
       where id = w.id;
    end if;
  end loop;

  -- 3d · The variant of a recipe that left its week entirely.
  --
  -- A variant rides `week_plan_id`, so it moves with its week for free. The
  -- exception is the recipe planned only on the day that crossed into the
  -- neighbouring week: its meals are there and its variant is here. Which
  -- neighbour is not a guess — it is the side the key moved away from. A week
  -- whose key moved EARLIER lost its tail (the Sunday of a Monday week, off
  -- into the week after), and a week whose key moved LATER lost its head (that
  -- same Sunday, coming home into the week before). Carry the variant there —
  -- but only from a week this call re-homed, only when no live meal of that
  -- recipe is left behind, only when the destination actually has one, and only
  -- when the destination has no variant of its own for the same line (the
  -- unique key of 0040, NULLs distinct, so an `add` row is never blocked by
  -- another `add`).
  --
  -- `src` / `dst` rather than `w` / `d`: `w` is the loop's record variable
  -- above, and a plpgsql variable shadows a table alias of the same name.
  update week_recipe_line_override o
     set week_plan_id = dst.id,
         updated_at   = now()
    from week_plan src
    join week_plan dst
      on dst.household_id = src.household_id
     and dst.deleted_at is null
   where o.household_id = p_household_id
     and o.deleted_at is null
     and src.id = o.week_plan_id
     and ((src.id = any (v_earlier)
           and dst.week_start_date = src.week_start_date + 7)
       or (src.id = any (v_later)
           and dst.week_start_date = src.week_start_date - 7))
     and not exists (
       select 1 from plan_entry pe
        where pe.week_plan_id = src.id
          and pe.recipe_id    = o.recipe_id
          and pe.deleted_at is null)
     and exists (
       select 1 from plan_entry pe
        where pe.week_plan_id = dst.id
          and pe.recipe_id    = o.recipe_id
          and pe.deleted_at is null)
     and not exists (
       select 1 from week_recipe_line_override x
        where x.week_plan_id        = dst.id
          and x.recipe_id           = o.recipe_id
          and x.recipe_line_item_id = o.recipe_line_item_id);

  -- 3e · The shopping overlay follows its window.
  --
  -- Pure date arithmetic — a tick names a week by date and needs no `week_plan`
  -- row to exist, which is exactly why it has to be re-keyed by the same window
  -- rule the week row is: a tick that slid a different distance from the week
  -- it belongs to would land in the neighbour's list. A NULL week stays NULL:
  -- it is a pre-0019 tick that belongs to no week, and inventing one for it is
  -- exactly what invariant 3 forbids.
  update shopping_list_entry s
     set week_start_date = week_rekey(s.week_start_date, p_starts_on),
         updated_at      = now()
   where s.household_id = p_household_id
     and s.week_start_date is not null
     and s.week_start_date
         <> week_rekey(s.week_start_date, p_starts_on);
end;
$$;

comment on function set_household_week_start(uuid, smallint) is
  'Sets household.week_starts_on and re-homes every week of that household to '
  'the new key in the SAME transaction, so no device ever sees a new '
  'preference against old keys. A meal is a date and is re-filed into the week '
  'its own date falls in, crossing into a neighbouring week when it has to '
  '(created when absent); a week row and a shopping tick are a seven-day '
  'window and move to the new window they overlap most. Residue-driven per '
  'week, so re-running is a no-op, a week written offline under the old key is '
  'repaired on the next run, and a flip back puts every week, meal, tick and '
  'variant at the address it started at.';

-- The door is exactly as wide as the tables behind it: `authenticated` may
-- call it, and RLS decides whose weeks move. `anon` has no grant on any of the
-- four tables, so leaving it EXECUTE would be a door onto nothing — but a door
-- onto nothing is still a door.
revoke execute on function set_household_week_start(uuid, smallint)
  from public, anon;
grant execute on function set_household_week_start(uuid, smallint)
  to authenticated, service_role;
