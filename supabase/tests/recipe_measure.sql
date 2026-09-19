-- pgTAP: a recipe's own word for one of what it makes (0048).
--
-- What is defended here:
--   * the SHAPE — a label that is a word, a `per_batch` that is a positive
--     number, and deliberately NO unique index on (recipe_id, label): two
--     offline devices coining "blob" must both land, because a 23505 on upload
--     drops the whole crud transaction (0011's doctrine);
--   * the two POINTERS — `recipe_line_item.recipe_measure_id` and
--     `week_recipe_line_override.recipe_measure_id` — each sayable only on a
--     component line, only beside a number, and never beside a unit: the word
--     IS the denomination, and `batch` or `piece` stored next to it would be a
--     lie a reader could act on. Both rules that demanded a unit WIDENED by
--     one arm and lost nothing — `recipe_line_item.unit` is still refused as
--     null on a line that names no word, and 0040's both-or-neither pair rule
--     still makes every refusal it made for a row without one;
--   * the TRIGGER: the measure must be a live measure of the very recipe the
--     line's `sub_recipe_id` names, in the same household — and liveness is
--     required only when the pointer is being set, so a line whose word has
--     gone stays editable (the retirement rule: it is unresolved, never
--     re-read as a count);
--   * the boundary — RLS on, no delete policy (soft deletes), published to
--     PowerSync, and a member reads only their own household.
--
-- Run by `supabase test db`.

begin;
select plan(29);

-- ---------------------------------------------------------------------------
-- Fixtures: two households. House A has a sauce, a bread that uses it, and a
-- word for one of what the sauce makes.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','rm-a@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000301','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Almond','g','almond');

insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Romesco Aioli'),
 ('aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Patatas Bravas'),
 ('aaaaaaaa-0000-0000-0000-000000000103','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Salsa Verde'),
 ('bbbbbbbb-0000-0000-0000-000000000101','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Their Aioli');

insert into ingredient_group (id, household_id, recipe_id, name) values
 ('aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000102','to serve');

insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-21');

-- ---------------------------------------------------------------------------
-- 1 · The table, and the two columns that point at it.
-- ---------------------------------------------------------------------------

select has_table('public', 'recipe_measure', 'recipe_measure exists');
select has_column('public', 'recipe_measure', 'per_batch',
  'the one number that defines a measure: how many a batch makes');
select has_column('public', 'recipe_line_item', 'recipe_measure_id',
  'a component line can be counted in the sub-recipe''s own word');
select has_column('public', 'week_recipe_line_override', 'recipe_measure_id',
  'and so can the week variant that re-amounts it');

-- ---------------------------------------------------------------------------
-- 2 · The shape of a measure.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ insert into recipe_measure (id, household_id, recipe_id, label, per_batch)
     values ('aaaaaaaa-0000-0000-0000-000000000901',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000101','blob',20) $$,
  'a batch of the aioli makes 20 blob — one sentence, one number'
);

select throws_ok(
  $$ insert into recipe_measure (household_id, recipe_id, label, per_batch)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000101','ladle',0) $$,
  '23514',
  null,
  'a batch that makes none of something is not a measure'
);

select throws_ok(
  $$ insert into recipe_measure (household_id, recipe_id, label, per_batch)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000101','   ',12) $$,
  '23514',
  null,
  'a word made of spaces is not a word'
);

select lives_ok(
  $$ insert into recipe_measure (id, household_id, recipe_id, label, per_batch)
     values ('aaaaaaaa-0000-0000-0000-000000000902',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000101','blob',24) $$,
  'a duplicate label LANDS — no unique index, so an offline dupe never 23505s '
  'the whole crud transaction (0011); duplicates merge on read'
);

-- The sauce that is cooked at the other end of the fence, and a word of its
-- own, so "another recipe's measure" has something to be.
insert into recipe_measure (id, household_id, recipe_id, label, per_batch) values
 ('aaaaaaaa-0000-0000-0000-000000000903','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaaaaaa-0000-0000-0000-000000000103','spoonful',8),
 ('bbbbbbbb-0000-0000-0000-000000000901','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'bbbbbbbb-0000-0000-0000-000000000101','dollop',10);

-- ---------------------------------------------------------------------------
-- 3 · Only a component line, and only beside a number.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ insert into recipe_line_item
       (id, household_id, group_id, sub_recipe_id, quantity,
        recipe_measure_id)
     values ('aaaaaaaa-0000-0000-0000-000000000701',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000101', 3,
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '3 blob of the aioli — the amount resolves with no yield at all'
);

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, ingredient_id, quantity, unit,
        recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000301', 3, 'g',
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '23514',
  null,
  'an ingredient has no batch, so it cannot be counted in a recipe''s word'
);

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, sub_recipe_id, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '23514',
  null,
  '"blob" alone says nothing — a measure counts, so it needs a number'
);

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, sub_recipe_id, quantity, unit,
        recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000101', 3, 'batch',
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '23514',
  null,
  'and no unit beside it — "3 blob" in batches would be the wrong number in '
  'the right dimension'
);

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, ingredient_id, quantity)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000301', 3) $$,
  '23514',
  null,
  'and the unit''s NOT NULL only WIDENED: a line with neither a unit nor a '
  'word is still refused, as it was before 0048'
);

select lives_ok(
  $$ insert into week_recipe_line_override
       (id, household_id, week_plan_id, recipe_id, recipe_line_item_id,
        action, sub_recipe_id, quantity, recipe_measure_id)
     values ('aaaaaaaa-0000-0000-0000-000000000801',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',
             'aaaaaaaa-0000-0000-0000-000000000701',
             'replace','aaaaaaaa-0000-0000-0000-000000000101', 5,
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  'this week the bravas takes 5 blob — absolute, like every override amount'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, ingredient_id,
        quantity, unit, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',
             'add','aaaaaaaa-0000-0000-0000-000000000301', 3, 'g',
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '23514',
  null,
  'an ingredient target has no batch to count on the week variant either'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, sub_recipe_id,
        recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',
             'add','aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '23514',
  null,
  'and it needs a number here too'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, sub_recipe_id,
        quantity, unit, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',
             'add','aaaaaaaa-0000-0000-0000-000000000101', 3, 'batch',
             'aaaaaaaa-0000-0000-0000-000000000901') $$,
  '23514',
  null,
  'the widened pair rule forbids a unit beside a measure, rather than merely '
  'permitting its absence'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, sub_recipe_id, quantity)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',
             'add','aaaaaaaa-0000-0000-0000-000000000101', 3) $$,
  '23514',
  null,
  'and 0040''s own refusal still stands where there is no measure: a quantity '
  'with no unit is half a fact'
);

-- ---------------------------------------------------------------------------
-- 4 · The trigger: the measure belongs to the recipe the line points at.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, sub_recipe_id, quantity, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000101', 2,
             'aaaaaaaa-0000-0000-0000-000000000903') $$,
  '23514',
  null,
  'the salsa''s "spoonful" resolved against the aioli''s batch would be a '
  'wrong batch share, quietly'
);

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, sub_recipe_id, quantity, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000101', 2,
             'bbbbbbbb-0000-0000-0000-000000000901') $$,
  '23503',
  null,
  'and another household''s word is not this household''s to say'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, sub_recipe_id,
        quantity, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',
             'add','aaaaaaaa-0000-0000-0000-000000000101', 2,
             'aaaaaaaa-0000-0000-0000-000000000903') $$,
  '23514',
  null,
  'the same fence stands on the week variant'
);

-- ---------------------------------------------------------------------------
-- 5 · A word that has gone. The number is kept; nothing degrades to a count.
-- ---------------------------------------------------------------------------

update recipe_measure set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000902';

select throws_ok(
  $$ insert into recipe_line_item
       (household_id, group_id, sub_recipe_id, quantity, recipe_measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000601',
             'aaaaaaaa-0000-0000-0000-000000000101', 2,
             'aaaaaaaa-0000-0000-0000-000000000902') $$,
  '23514',
  null,
  'a retired word cannot be pointed at by a new line'
);

update recipe_measure set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000901';

select lives_ok(
  $$ update recipe_line_item set note = 'to finish'
      where id = 'aaaaaaaa-0000-0000-0000-000000000701' $$,
  'but the line that already says it stays editable — liveness is only asked '
  'of a pointer being set'
);

select is(
  (select quantity from recipe_line_item
    where id = 'aaaaaaaa-0000-0000-0000-000000000701'),
  3::numeric,
  'and the number is kept: the line is unresolved, not re-read as a count'
);

-- ---------------------------------------------------------------------------
-- 6 · The boundary: RLS, no delete policy, published.
-- ---------------------------------------------------------------------------

select ok(
  (select relrowsecurity from pg_class
    where oid = 'recipe_measure'::regclass),
  'row level security is on'
);

select is(
  (select count(*)::int from pg_policies
    where tablename = 'recipe_measure' and cmd = 'DELETE'),
  0,
  'no delete policy — deletes are soft, as everywhere else'
);

select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'powersync' and tablename = 'recipe_measure'),
  1,
  'it syncs down with the household''s recipes'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from recipe_measure),
  (select count(*)::int from recipe_measure
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'a member reads their own household''s words and nothing else'
);

select throws_ok(
  $$ insert into recipe_measure (household_id, recipe_id, label, per_batch)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'bbbbbbbb-0000-0000-0000-000000000101','contraband',4) $$,
  '42501',
  null,
  'and cannot coin one in another household'
);

select * from finish();
rollback;
