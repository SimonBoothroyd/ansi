-- pgTAP: the shopping overlay's week scope (migration 0019, week-redesign D3).
--
-- What is defended here:
--   * the SHAPE — `shopping_list_entry.week_start_date` exists, is a `date`,
--     and is NULLABLE (null is the global free-text staple, not a missing
--     value), plus the household+week index the list read runs on;
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
select plan(14);

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
  'nullable: null is the GLOBAL free-text staple, not a missing week');

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

-- A free-text staple belongs to no week.
select lives_ok($$
  insert into shopping_list_entry (id, household_id, free_text, checked) values
   ('aaaaaaaa-0000-0000-0000-0000000006a4','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Paper towels', false)
$$, 'a free-text staple stores no week — you are out of it whichever week is '
   'on screen');

select is(
  (select week_start_date from shopping_list_entry
    where id = 'aaaaaaaa-0000-0000-0000-0000000006a4'),
  null::date,
  'and its week really is null, not a default');

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
