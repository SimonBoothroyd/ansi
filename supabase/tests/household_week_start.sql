-- pgTAP: the household's first day of the week, and the re-home that follows
-- it (0043).
--
-- What is defended here:
--   * the SHAPE — `household.week_starts_on` is a not-null smallint defaulting
--     to 1 (Monday, what every household has meant since 0005) and refuses
--     anything outside the ISO range 1..7;
--   * the two questions the re-home asks — `week_key_for()` of a DATE ("which
--     week is this dinner in") and `week_rekey()` of a WINDOW ("this week
--     covers seven days, which of the new weeks is it"). The second is asserted
--     in both directions, because a rule that only ever slid a key backwards
--     would take Sun 6 Sep out to Mon 31 Aug on the way home;
--   * the RE-HOME, meal by meal: a Monday→Sunday flip moves every week back a
--     day, keeps each meal's REAL CALENDAR DATE, pushes the meal that runs past
--     the end of its week into the next one, drags the shopping tick along with
--     its week, leaves a NULL tick NULL, and carries the variant of a recipe
--     that left its week entirely while leaving the variant of a recipe that
--     still has meals there. Nothing is lost: the row count of all four tables
--     is the count before;
--   * IDEMPOTENCY — a second call changes nothing at all, `household.updated_at`
--     included;
--   * SYMMETRY — flipping back puts the household's WHOLE address book back:
--     every week row, every meal, every tick and both variants at the address
--     they started at, with nothing created, nothing emptied and nothing
--     tombstoned. That is what "flip it as often as you like" (D4) actually
--     rests on, and it is the reason a week is re-keyed to the window it
--     overlaps most rather than to the nearest earlier new-residue day;
--   * the ORPHAN REPAIR — a week written under the old key by a device that
--     was offline across the flip is re-homed by the next run, whether its
--     window is free or already occupied by the real week. The occupied case
--     is the one that could break `unique (household_id, week_start_date)`
--     mid-update, so it is run for real rather than reasoned about;
--   * ISOLATION — a second household is untouched by any of it, cannot flip
--     the first, and can flip itself as plain `authenticated` (the function is
--     security INVOKER, so its grants have to be enough on their own).
--
-- Dates are real: 2026-09-07 is a Monday, 2026-09-13 the Sunday that ends its
-- Monday-keyed week and begins its Sunday-keyed one.
--
-- Run by `supabase test db`.

begin;
select plan(47);

-- ---------------------------------------------------------------------------
-- Fixtures: two households. House A plans two weeks — a recipe cooked Mon and
-- Wed, a recipe cooked only on the Sunday, a meal in the following week — with
-- a variant on each recipe and a week-scoped tick beside a week-less one.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','ws-a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','ws-b@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','B1','22222222-2222-2222-2222-222222222222');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000301','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Beef Mince','g','beef mince');

insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Slow-Cooker Beef Ragù'),
 ('aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sunday Roast'),
 ('bbbbbbbb-0000-0000-0000-000000000101','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Dal');

insert into ingredient_group (id, household_id, recipe_id, name) values
 ('aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000101','for the ragù'),
 ('aaaaaaaa-0000-0000-0000-000000000602','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000102','for the roast');

insert into recipe_line_item (id, household_id, group_id, ingredient_id, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000701','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000301',400,'g'),
 ('aaaaaaaa-0000-0000-0000-000000000702','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000602','aaaaaaaa-0000-0000-0000-000000000301',900,'g');

-- Two Monday-keyed weeks in House A, one in House B.
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-07'),
 ('aaaaaaaa-0000-0000-0000-000000000202','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-14'),
 ('bbbbbbbb-0000-0000-0000-000000000201','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','2026-09-07');

-- Mon 7 Sep, Wed 9 Sep, Sun 13 Sep, and Thu 17 Sep in the week after.
insert into plan_entry
  (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000901','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201',0,'Dinner','aaaaaaaa-0000-0000-0000-000000000101'),
 ('aaaaaaaa-0000-0000-0000-000000000902','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201',2,'Dinner','aaaaaaaa-0000-0000-0000-000000000101'),
 ('aaaaaaaa-0000-0000-0000-000000000903','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201',6,'Dinner','aaaaaaaa-0000-0000-0000-000000000102'),
 ('aaaaaaaa-0000-0000-0000-000000000904','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000202',3,'Dinner','aaaaaaaa-0000-0000-0000-000000000101'),
 ('bbbbbbbb-0000-0000-0000-000000000901','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000201',6,'Dinner','bbbbbbbb-0000-0000-0000-000000000101');

-- One variant per recipe on the first week: the ragù still has Mon and Wed
-- meals there after the flip, the roast has none.
insert into week_recipe_line_override
  (id, household_id, week_plan_id, recipe_id, recipe_line_item_id, action) values
 ('aaaaaaaa-0000-0000-0000-000000000801','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000701','exclude'),
 ('aaaaaaaa-0000-0000-0000-000000000802','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-0000-0000-0000-000000000702','exclude');

-- A tick made against the first week, and the week-less row an older client
-- wrote (0019: an ingredient entry with no week belongs to no week).
insert into shopping_list_entry
  (id, household_id, ingredient_id, checked, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000a01','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000301', true, '2026-09-07'),
 ('aaaaaaaa-0000-0000-0000-000000000a02','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000301', false, null);

-- The household's whole address book in one string: every week (and whether it
-- is tombstoned), every meal by its week and offset, every tick by its week,
-- every variant by the week it hangs on. Deliberately carries no `updated_at`
-- — a re-home is about addresses, and the timestamps are what PowerSync reads,
-- not what the household's plan IS.
create function ws_state(p_household uuid) returns text
language sql as $$
  select coalesce(string_agg(line, e'\n' order by line), '')
    from (
      select 'week ' || wp.week_start_date::text
             || case when wp.deleted_at is null then '' else ' (gone)' end as line
        from week_plan wp
       where wp.household_id = p_household
      union all
      select 'meal ' || wp.week_start_date::text || '+' || pe.day_of_week::text
             || ' ' || pe.recipe_id::text
        from plan_entry pe
        join week_plan wp on wp.id = pe.week_plan_id
       where pe.household_id = p_household
      union all
      select 'tick ' || coalesce(s.week_start_date::text, 'no week')
             || ' ' || s.id::text
        from shopping_list_entry s
       where s.household_id = p_household
      union all
      select 'variant ' || wp.week_start_date::text || ' ' || o.id::text
        from week_recipe_line_override o
        join week_plan wp on wp.id = o.week_plan_id
       where o.household_id = p_household
    ) t;
$$;

-- Every meal's real calendar date, which the re-home may never change.
create function ws_dates(p_household uuid) returns text
language sql as $$
  select coalesce(
    string_agg((wp.week_start_date + pe.day_of_week)::text, ','
               order by (wp.week_start_date + pe.day_of_week), pe.id), '')
    from plan_entry pe
    join week_plan wp on wp.id = pe.week_plan_id
   where pe.household_id = p_household;
$$;

-- ---------------------------------------------------------------------------
-- 1 · The column.
-- ---------------------------------------------------------------------------

select has_column('household', 'week_starts_on',
  'the household says which day its week starts on');

select col_type_is('household', 'week_starts_on', 'smallint',
  'an ISO weekday number, 1 = Monday … 7 = Sunday');

select col_not_null('household', 'week_starts_on',
  'every household has one — there is no "unset" week');

select is(
  (select week_starts_on from household
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::smallint,
  'and it defaults to Monday, which is what every household has meant '
  'since 0005');

select throws_ok($$
  insert into household (id, name, week_starts_on)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc','Zero','0')
$$, '23514', null,
  'ISO weekdays start at 1, so 0 is not a day');

select throws_ok($$
  insert into household (id, name, week_starts_on)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc','Eight','8')
$$, '23514', null,
  'and end at 7, so there is no eighth');

-- ---------------------------------------------------------------------------
-- 2 · The two questions: which week is this DATE in, and where does this
--     seven-day WINDOW go.
-- ---------------------------------------------------------------------------

select is(
  array[week_key_for('2026-09-13', 1::smallint),
        week_key_for('2026-09-07', 1::smallint)],
  array['2026-09-07'::date, '2026-09-07'::date],
  'Monday-first: the Sunday belongs to the week that began six days earlier, '
  'and a Monday is its own key');

select is(
  array[week_key_for('2026-09-13', 7::smallint),
        week_key_for('2026-09-07', 7::smallint)],
  array['2026-09-13'::date, '2026-09-06'::date],
  'Sunday-first: the Sunday now OPENS its week, and the Monday after it keys '
  'back to the day before — the whole point of the setting');

-- A WEEK is not a date: it covers seven days, so it goes to the new window it
-- overlaps most — the one holding its midpoint. Asserted in both directions
-- because that is the whole claim: the Monday week goes to the Sunday before
-- it, and that Sunday week comes back to exactly the Monday it came from. A
-- rule that only ever slid a key backwards would send it to Mon 31 Aug instead,
-- a week early, and would do it again on every flip.
select is(
  array[week_rekey('2026-09-07', 7::smallint),
        week_rekey('2026-09-06', 1::smallint),
        week_rekey('2026-09-07', 1::smallint)],
  array['2026-09-06'::date, '2026-09-07'::date, '2026-09-07'::date],
  'the week keyed Mon 7 Sep becomes the one keyed Sun 6 Sep and comes home to '
  'Mon 7 Sep, and a week already at the right residue rekeys to itself');

-- ---------------------------------------------------------------------------
-- 3 · The flip: Monday → Sunday.
-- ---------------------------------------------------------------------------

do $$ begin
  perform set_config('ws.orig',
    ws_state('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  perform set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 7::smallint);
end $$;

select is(
  (select week_starts_on from household
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  7::smallint,
  'the household now starts its week on Sunday');

select is(
  (select week_start_date from week_plan
    where id = 'aaaaaaaa-0000-0000-0000-000000000201'),
  '2026-09-06'::date,
  'the week keyed Mon 7 Sep is now keyed Sun 6 Sep — the same window, moved '
  'back a day');

select is(
  (select week_start_date from week_plan
    where id = 'aaaaaaaa-0000-0000-0000-000000000202'),
  '2026-09-13'::date,
  'and the week after it likewise, onto Sun 13 Sep');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'aaaaaaaa-0000-0000-0000-000000000901'),
  array['2026-09-06','1'],
  'Monday''s ragù keeps its week and slides to offset 1');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'aaaaaaaa-0000-0000-0000-000000000902'),
  array['2026-09-06','3'],
  'Wednesday''s likewise, to offset 3');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'aaaaaaaa-0000-0000-0000-000000000903'),
  array['2026-09-13','0'],
  'and the Sunday roast LEAVES the week it was the tail of and OPENS the next '
  'one — the thing the whole setting is for');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'aaaaaaaa-0000-0000-0000-000000000904'),
  array['2026-09-13','4'],
  'the following week''s Thursday meal moves with its own week, to offset 4');

select is(
  ws_dates('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '2026-09-07,2026-09-09,2026-09-13,2026-09-17',
  'every meal is on the same calendar day it was on before: the address '
  'changed, the dinner did not');

select is(
  (select count(*) from week_plan
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2::bigint,
  'no week was created or lost — the Sunday meal found the week it needed '
  'by the key that week was ABOUT to have');

select is(
  (select count(*) from plan_entry
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  4::bigint,
  'all four meals are still there');

select is(
  (select count(*) from shopping_list_entry
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2::bigint,
  'both shopping rows are still there');

select is(
  (select count(*) from week_recipe_line_override
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2::bigint,
  'and both variants — a re-home moves rows, it never drops one');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-000000000a01'),
  '2026-09-06'::date,
  'the tick follows its week: a shop is a state about a trip, and the trip '
  'moved');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-000000000a02'),
  null::date,
  'a week-less row stays week-less — 0019''s rule, and no week is invented '
  'for it');

select is(
  (select week_plan_id from week_recipe_line_override
    where id = 'aaaaaaaa-0000-0000-0000-000000000801'),
  'aaaaaaaa-0000-0000-0000-000000000201'::uuid,
  'the ragù''s variant stays on its week — the recipe still has Mon and Wed '
  'meals there');

select is(
  (select week_plan_id from week_recipe_line_override
    where id = 'aaaaaaaa-0000-0000-0000-000000000802'),
  'aaaaaaaa-0000-0000-0000-000000000202'::uuid,
  'the roast''s variant is CARRIED to the week its only meal left for — '
  'otherwise this week would cook a variant of a dish it no longer plans');

select is(
  (select count(*) from week_plan
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and week_start_date <> week_rekey(week_start_date, 7::smallint)),
  0::bigint,
  'and no week is left at the old residue');

-- ---------------------------------------------------------------------------
-- 4 · Idempotency: the same call again is a no-op.
-- ---------------------------------------------------------------------------

do $$ begin
  perform set_config('ws.flipped',
    ws_state('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  perform set_config('ws.touched',
    (select updated_at::text from household
      where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  perform set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 7::smallint);
end $$;

select is(
  ws_state('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  current_setting('ws.flipped'),
  'running it again moves nothing: the function asks each week whether IT is '
  'at the right residue, and they all are');

select is(
  (select updated_at::text from household
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  current_setting('ws.touched'),
  'not even the household row is re-stamped — a no-op flip syncs nothing down');

-- ---------------------------------------------------------------------------
-- 5 · Symmetry: flipping back restores the whole address book.
-- ---------------------------------------------------------------------------

do $$ begin
  perform set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1::smallint);
end $$;

select is(
  (select week_starts_on from household
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::smallint,
  'back to Monday');

select is(
  ws_state('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  current_setting('ws.orig'),
  'and EVERYTHING is back where it started — every week row, every meal, '
  'every tick, both variants. A meal comes home because it is filed by its '
  'date; a week and a tick come home because each goes to the window it '
  'overlaps most, and that rule is its own inverse');

select is(
  (select array[count(*)::text,
                count(*) filter (where deleted_at is not null)::text]
     from week_plan
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  array['2','0'],
  'with no week row created, emptied or tombstoned along the way: the round '
  'trip costs the household nothing, which is what makes the setting a setting '
  'rather than a one-way door');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-000000000a01'),
  '2026-09-07'::date,
  'the tick is back on the week it was made against — it is re-keyed by the '
  'same window rule its week is, so it can never be stranded in the '
  'neighbour''s list');

select is(
  (select array_agg(wp.week_start_date::text order by o.id)
     from week_recipe_line_override o
     join week_plan wp on wp.id = o.week_plan_id
    where o.household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  array['2026-09-07','2026-09-07'],
  'and both variants are back on the week their recipes are cooked in: the '
  'roast''s was carried out with its meals on the way there and carried BACK '
  'on the way home — the crossing happens in the other direction each time');

-- ---------------------------------------------------------------------------
-- 6 · The orphan a device that was offline across the flip uploads.
-- ---------------------------------------------------------------------------
--
-- It writes under the OLD convention, so it lands at a residue the household
-- no longer keys by. The next run repairs it — which is why the setting is
-- also its own repair tool, and why it may be flipped any number of times.

do $$ begin
  perform set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 7::smallint);
end $$;

-- (a) Its window is free: nobody had planned that week yet.
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000203','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-21');
insert into plan_entry
  (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000905','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000203',1,'Dinner','aaaaaaaa-0000-0000-0000-000000000101');

do $$ begin
  perform set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 7::smallint);
end $$;

select is(
  (select week_start_date from week_plan
    where id = 'aaaaaaaa-0000-0000-0000-000000000203'),
  '2026-09-20'::date,
  'a week uploaded under the old key is re-homed by the next run — the '
  'function is residue-driven per WEEK, so a household with mixed keys is '
  'repaired rather than skipped');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text,
                (wp.week_start_date + pe.day_of_week)::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'aaaaaaaa-0000-0000-0000-000000000905'),
  array['2026-09-20','2','2026-09-22'],
  'and the meal it carried is still on Tue 22 Sep, now at offset 2');

select is(
  (select count(*) from week_plan
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3::bigint,
  'the repair renamed the orphan rather than cloning it');

-- (b) Its window is already occupied — the case that would break
--     `unique (household_id, week_start_date)` if the re-key were one
--     unordered UPDATE. Two rows cannot hold one window, so the orphan hands
--     its meals to the resident and goes.
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000204','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-07');
insert into plan_entry
  (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000906','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000204',2,'Dinner','aaaaaaaa-0000-0000-0000-000000000101');

select lives_ok($$
  select set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 7::smallint)
$$, 'an orphan whose window is ALREADY planned does not collide with it: the '
   'weeks are re-keyed lowest-key-first, and a target that is genuinely taken '
   'is a duplicate rather than a move');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text,
                (wp.week_start_date + pe.day_of_week)::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'aaaaaaaa-0000-0000-0000-000000000906'),
  array['2026-09-06','3','2026-09-09'],
  'the orphan''s meal lands on the resident week, still on Wed 9 Sep');

select isnt(
  (select deleted_at from week_plan
    where id = 'aaaaaaaa-0000-0000-0000-000000000204'),
  null::timestamptz,
  'and the emptied duplicate is tombstoned — two rows covering one window is '
  'the state every week-scoped read assumes cannot happen');

select is(
  (select count(*) from (
     select week_key_for(week_start_date, 7::smallint)
       from week_plan
      where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        and deleted_at is null
      group by 1 having count(*) > 1) dupes),
  0::bigint,
  'no window is left with two live weeks in it');

select is(
  (select count(*) from plan_entry
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  6::bigint,
  'and across four flips and two repairs, not one meal was dropped');

-- ---------------------------------------------------------------------------
-- 7 · The other household never felt any of it.
-- ---------------------------------------------------------------------------

select is(
  (select array[h.week_starts_on::text, wp.week_start_date::text,
                pe.day_of_week::text]
     from household h
     join week_plan wp on wp.household_id = h.id
     join plan_entry pe on pe.week_plan_id = wp.id
    where h.id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  array['1','2026-09-07','6'],
  'House B is still Monday-first, with its Sunday meal still the tail of its '
  'Monday week — the flip is one household''s, not the table''s');

-- ---------------------------------------------------------------------------
-- 8 · Under RLS, as the plain `authenticated` the app connects as.
-- ---------------------------------------------------------------------------
--
-- The function is SECURITY INVOKER, so this is the real test of it: the grants
-- and policies of 0001/0005/0006/0040 have to be enough on their own, and the
-- fence has to hold in the other direction.

set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select throws_ok($$
  select set_household_week_start(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1::smallint)
$$, '42501', null,
  'House B cannot flip House A''s week: RLS hides the row, so the function '
  'refuses rather than quietly touching nothing');

select lives_ok($$
  select set_household_week_start(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 7::smallint)
$$, 'but it can flip its own, as plain `authenticated` — the door is exactly '
   'as wide as the four tables behind it');

select is(
  (select array[wp.week_start_date::text, pe.day_of_week::text,
                (wp.week_start_date + pe.day_of_week)::text]
     from plan_entry pe join week_plan wp on wp.id = pe.week_plan_id
    where pe.id = 'bbbbbbbb-0000-0000-0000-000000000901'),
  array['2026-09-13','0','2026-09-13'],
  'and its Sunday meal opens a week the function had to CREATE for it, under '
  'the insert policy the app already has');

select is(
  (select count(*) from week_plan
    where household_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  2::bigint,
  'the emptied Sun 6 Sep week is kept, not swept');

select throws_ok($$
  select set_household_week_start(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 0::smallint)
$$, '22023', null,
  'and a day that is not an ISO weekday is refused by name, before anything '
  'moves');

reset role;

select * from finish();
rollback;
