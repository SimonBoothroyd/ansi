-- pgTAP: a recipe cooked differently for ONE planned week (0040, exec plan
-- 0043).
--
-- What is defended here:
--   * the KEY — one override per (week_plan, recipe, recipe_line_item), with
--     NULLs distinct so many `add` rows are legal. That uniqueness is what
--     makes the set recomputable whole on save;
--   * the ACTION SHAPE — `include`/`exclude` are statements about a recipe
--     line and carry no values; `replace`/`add` name exactly one target; an
--     `add` has no base line and everything else has one. A row outside that
--     shape would reach the seam as a delta nobody can apply;
--   * the amount rules 0033 wrote one table over — a both-or-neither pair, a
--     measure only beside a number, a component with no measure;
--   * the CASCADES: the override is *about* a line in a week, so with either
--     gone there is nothing for it to be about;
--   * RLS fences it by household, there is no delete policy (soft deletes),
--     and it is published to PowerSync.
--
-- Run by `supabase test db`.

begin;
select plan(21);

-- ---------------------------------------------------------------------------
-- Fixtures: two households; house A has a recipe with two lines on a week.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','wv-a@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000301','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Pork sausage','g','pork sausage'),
 ('aaaaaaaa-0000-0000-0000-000000000302','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Beef mince','g','beef mince');

insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000401','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000302','onion, medium',150);

insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Slow-Cooker Beef Ragù'),
 ('aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Romesco Aioli');

insert into ingredient_group (id, household_id, recipe_id, name) values
 ('aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000101','for the ragù');

insert into recipe_line_item (id, household_id, group_id, ingredient_id, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000701','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000301',400,'g'),
 ('aaaaaaaa-0000-0000-0000-000000000702','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000302',500,'g');

insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-14'),
 ('aaaaaaaa-0000-0000-0000-000000000202','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-21');

-- ---------------------------------------------------------------------------
-- 1 · The four actions, in the shape each is allowed to wear.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ insert into week_recipe_line_override
       (id, household_id, week_plan_id, recipe_id, recipe_line_item_id,
        action, ingredient_id, quantity, unit)
     values ('aaaaaaaa-0000-0000-0000-000000000801',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000701',
             'replace','aaaaaaaa-0000-0000-0000-000000000302',400,'g') $$,
  'replace carries one target and the absolute amount it is cooked at'
);

select lives_ok(
  $$ insert into week_recipe_line_override
       (id, household_id, week_plan_id, recipe_id, recipe_line_item_id, action)
     values ('aaaaaaaa-0000-0000-0000-000000000802',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000702',
             'exclude') $$,
  'exclude is a statement about a recipe line and carries nothing else'
);

select lives_ok(
  $$ insert into week_recipe_line_override
       (id, household_id, week_plan_id, recipe_id, action, ingredient_id,
        quantity, unit, sort_order)
     values ('aaaaaaaa-0000-0000-0000-000000000803',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'add','aaaaaaaa-0000-0000-0000-000000000302',1,'piece',9) $$,
  'add has no base line — the recipe has not got this one'
);

select lives_ok(
  $$ insert into week_recipe_line_override
       (id, household_id, week_plan_id, recipe_id, action, ingredient_id,
        quantity, unit, sort_order)
     values ('aaaaaaaa-0000-0000-0000-000000000804',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'add','aaaaaaaa-0000-0000-0000-000000000301',2,'piece',10) $$,
  'a second add is legal — NULLs compare distinct in the unique index'
);

-- ---------------------------------------------------------------------------
-- 2 · One override per (week, recipe, line).
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, recipe_line_item_id, action)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000702',
             'include') $$,
  '23505',
  null,
  'a base line cannot be overridden twice in one week'
);

select lives_ok(
  $$ insert into week_recipe_line_override
       (id, household_id, week_plan_id, recipe_id, recipe_line_item_id, action)
     values ('aaaaaaaa-0000-0000-0000-000000000805',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000702',
             'include') $$,
  'the SAME line is overridable again on another week — the variant is per week'
);

-- ---------------------------------------------------------------------------
-- 3 · The action shape.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, recipe_line_item_id, action,
        quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000701',
             'include', 400, 'g') $$,
  '23514',
  null,
  'include carries no amount — it only says the optional line counts'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, ingredient_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'exclude','aaaaaaaa-0000-0000-0000-000000000301') $$,
  '23514',
  null,
  'exclude without a base line has nothing to exclude'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, recipe_line_item_id, action,
        ingredient_id, sub_recipe_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000702',
             'replace','aaaaaaaa-0000-0000-0000-000000000301',
             'aaaaaaaa-0000-0000-0000-000000000102') $$,
  '23514',
  null,
  'replace names ONE target — the XOR of 0017, one table over'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, recipe_line_item_id, action,
        ingredient_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'aaaaaaaa-0000-0000-0000-000000000701',
             'add','aaaaaaaa-0000-0000-0000-000000000301') $$,
  '23514',
  null,
  'add has no base line to be about'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, ingredient_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'substitute','aaaaaaaa-0000-0000-0000-000000000301') $$,
  '23514',
  null,
  'there are four actions and no fifth'
);

-- ---------------------------------------------------------------------------
-- 4 · The amount rules 0033 wrote, one table over.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, ingredient_id, quantity)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'add','aaaaaaaa-0000-0000-0000-000000000301', 400) $$,
  '23514',
  null,
  'a quantity with no unit is half a fact'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, ingredient_id,
        measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'add','aaaaaaaa-0000-0000-0000-000000000302',
             'aaaaaaaa-0000-0000-0000-000000000401') $$,
  '23514',
  null,
  'a measure counts things, so it means nothing without a number'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, sub_recipe_id,
        quantity, unit, measure_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'add','aaaaaaaa-0000-0000-0000-000000000102',
             1,'piece','aaaaaaaa-0000-0000-0000-000000000401') $$,
  '23514',
  null,
  'a component override carries no measure'
);

-- ---------------------------------------------------------------------------
-- 5 · The cascades. An override is ABOUT a line in a week.
-- ---------------------------------------------------------------------------

delete from recipe_line_item
 where id = 'aaaaaaaa-0000-0000-0000-000000000701';

select is(
  (select count(*)::int from week_recipe_line_override
    where recipe_line_item_id = 'aaaaaaaa-0000-0000-0000-000000000701'),
  0,
  'the line going takes its overrides with it'
);

delete from week_plan where id = 'aaaaaaaa-0000-0000-0000-000000000201';

select is(
  (select count(*)::int from week_recipe_line_override
    where week_plan_id = 'aaaaaaaa-0000-0000-0000-000000000201'),
  0,
  'the week going takes its overrides with it'
);

-- ---------------------------------------------------------------------------
-- 6 · The boundary: RLS, no delete policy, published.
-- ---------------------------------------------------------------------------

select ok(
  (select relrowsecurity from pg_class
    where oid = 'week_recipe_line_override'::regclass),
  'row level security is on'
);

select is(
  (select count(*)::int from pg_policies
    where tablename = 'week_recipe_line_override' and cmd = 'DELETE'),
  0,
  'no delete policy — deletes are soft, as everywhere else'
);

select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'powersync'
      and tablename = 'week_recipe_line_override'),
  1,
  'it syncs down with the household'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from week_recipe_line_override),
  (select count(*)::int from week_recipe_line_override
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'a member reads their own household and nothing else'
);

select throws_ok(
  $$ insert into week_recipe_line_override
       (household_id, week_plan_id, recipe_id, action, ingredient_id)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',
             'add','aaaaaaaa-0000-0000-0000-000000000301') $$,
  '42501',
  null,
  'and cannot write one into another household'
);

select * from finish();
rollback;
