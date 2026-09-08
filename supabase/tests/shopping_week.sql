-- pgTAP: the shopping overlay's week scope (migrations 0019 and 0036).
--
-- What is defended here:
--   * the SHAPE — `shopping_list_entry.week_start_date` exists, is a `date`,
--     and is NULLABLE (the column admits the week-less rows older clients
--     wrote; every entry the app writes today carries a week), plus the
--     household+week index the list read runs on;
--   * the BACKFILL 0036 leans on — a free-text row with no week lands on the
--     ISO Monday of its own `created_at`, and a second run changes nothing.
--     The list read takes one week's rows and nothing else, so a row left
--     null would be read by no week at all;
--   * that NO unique constraint arrived with it. This is the load-bearing
--     one: 0006 deliberately has no unique index on an entry, because two
--     offline devices must each be able to create a row for the same
--     ingredient and converge later — a unique index would make the second
--     device's upload fail and lose its data. So the suite proves BOTH that
--     the same ingredient can sit on two different weeks (the whole point of
--     the column) AND that it can still sit twice on ONE week (the offline
--     duplicate the app folds together in `_findOrCreateIngredientEntry`);
--   * that the column changes nothing else: the identity XOR still refuses a
--     row that is both an ingredient and a free text (or neither), a manual
--     contribution still cascades from its entry (which is why the
--     contribution needs no week of its own — it rides the entry's), and RLS
--     still fences by household with the column in play.
--
-- Run by `supabase test db`.

begin;
select plan(19);

-- ---------------------------------------------------------------------------
-- Fixtures: two households, one ingredient each.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','sw-a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','sw-b@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','B1','22222222-2222-2222-2222-222222222222');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-0000000005a1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Flour','g','flour'),
 ('bbbbbbbb-0000-0000-0000-0000000005b1','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Flour','g','flour');

-- ---------------------------------------------------------------------------
-- 1 · The shape.
-- ---------------------------------------------------------------------------

select has_column('shopping_list_entry', 'week_start_date',
  'the overlay entry carries the week it was touched on (0019 / D3)');

select col_type_is('shopping_list_entry', 'week_start_date', 'date',
  'it is a date — the same key week_plan.week_start_date is addressed by');

select col_is_null('shopping_list_entry', 'week_start_date',
  'nullable: the column still admits the week-less rows an older client wrote');

select has_index('shopping_list_entry', 'shopping_list_entry_week_idx',
  array['household_id', 'week_start_date'],
  'the list read is always "this household, this week"');

-- `shopping_list_contribution` deliberately gains nothing: a top-up hangs off
-- its entry and inherits the entry's week.
select hasnt_column('shopping_list_contribution', 'week_start_date',
  'a contribution rides its entry''s week rather than storing a second copy');

-- ---------------------------------------------------------------------------
-- 2 · The column scopes, and nothing was made unique.
-- ---------------------------------------------------------------------------

insert into shopping_list_entry
  (id, household_id, ingredient_id, checked, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-0000000006a1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000005a1', true,  '2026-08-24');

select lives_ok($$
  insert into shopping_list_entry
    (id, household_id, ingredient_id, checked, week_start_date) values
   ('aaaaaaaa-0000-0000-0000-0000000006a2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000005a1', false, '2026-08-31')
$$, 'the same ingredient sits on two different weeks — the point of the column');

select lives_ok($$
  insert into shopping_list_entry
    (id, household_id, ingredient_id, checked, week_start_date) values
   ('aaaaaaaa-0000-0000-0000-0000000006a3','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000005a1', false, '2026-08-24')
$$, 'and STILL twice on one week: no unique index, so an offline duplicate '
   'uploads instead of failing (the app folds them, 0006''s reasoning)');

select is(
  (select count(*) from shopping_list_entry
    where ingredient_id = 'aaaaaaaa-0000-0000-0000-0000000005a1'
      and week_start_date = '2026-08-24'),
  2::bigint,
  'both same-week rows are live — nothing silently dropped');

select is(
  (select count(*) from shopping_list_entry
    where ingredient_id = 'aaaaaaaa-0000-0000-0000-0000000005a1'
      and week_start_date = '2026-08-31'),
  1::bigint,
  'the other week is untouched by either of them');

-- A free-text item belongs to the week it was added on, exactly as a tick or
-- a top-up does (0036).
select lives_ok($$
  insert into shopping_list_entry
    (id, household_id, free_text, checked, week_start_date) values
   ('aaaaaaaa-0000-0000-0000-0000000006a4','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Paper towels', false, '2026-08-24')
$$, 'a free-text item stores the week it was added on — it is bought on that '
   'trip, like the top-up beside it');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-0000000006a4'),
  '2026-08-24'::date,
  'and the week it stores is the one it was written with');

-- ---------------------------------------------------------------------------
-- 2b · The backfill: a week-less free-text row lands on its created_at week.
-- ---------------------------------------------------------------------------
--
-- The column stays nullable, so an older client can still write this row —
-- and under 0036's read (`week_start_date = $1`) it would be read by no week
-- at all. The backfill is what makes it visible again, on the week the person
-- was looking at when they typed it. Wednesday 26 Aug 2026 sits in the week
-- of Monday 24 Aug.
select lives_ok($$
  insert into shopping_list_entry
    (id, household_id, free_text, checked, created_at) values
   ('aaaaaaaa-0000-0000-0000-0000000006a6','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Bin bags', false, '2026-08-26 12:00:00+00')
$$, 'an older client can still write a free-text row with no week');

-- A soft-deleted one too: an undelete must not bring a global row back into a
-- world that has no such thing.
insert into shopping_list_entry
  (id, household_id, free_text, checked, created_at, deleted_at) values
 ('aaaaaaaa-0000-0000-0000-0000000006a7','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sponges', false, '2026-08-26 12:00:00+00', now());

select is(shopping_free_text_week_backfill(), 2::integer,
  'the backfill stamps both week-less free-text rows, the soft-deleted one '
  'included (an ingredient entry with no week is a stale tick, left alone)');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-0000000006a6'),
  '2026-08-24'::date,
  'onto the ISO Monday of its own created_at');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-0000000006a7'),
  '2026-08-24'::date,
  'and the tombstoned row lands on the same Monday, so an undelete is safe');

select is(shopping_free_text_week_backfill(), 0::integer,
  'and a second run is a no-op — the backfill only ever fills a null');

-- ---------------------------------------------------------------------------
-- 3 · The column changed nothing else.
-- ---------------------------------------------------------------------------

select throws_ok($$
  insert into shopping_list_entry
    (id, household_id, ingredient_id, free_text, week_start_date) values
   ('aaaaaaaa-0000-0000-0000-0000000006a5','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000005a1','Flour','2026-08-24')
$$, '23514',
   null,
   'the identity XOR still refuses a row that is both an ingredient and a '
   'free text');

insert into shopping_list_contribution
  (id, household_id, entry_id, source_type, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-0000000007a1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000006a1','manual', 50, 'g');

delete from shopping_list_entry
  where id = 'aaaaaaaa-0000-0000-0000-0000000006a1';

select is(
  (select count(*) from shopping_list_contribution
    where id = 'aaaaaaaa-0000-0000-0000-0000000007a1'),
  0::bigint,
  'a top-up still cascades from its entry — so it inherits the entry''s week');

-- RLS, with the new column in play: House B still sees only its own rows.
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*) from shopping_list_entry),
  0::bigint,
  'RLS is untouched: House B reads none of House A''s week-scoped entries');

reset role;

select * from finish();
rollback;
