-- pgTAP: nested recipes — component lines, the two-denomination yield, and the
-- cycle/household guard (migration 0017, exec plan 0021 D1/D2/D5).
--
-- What is defended here:
--   * D1 — the identity XOR (a line is an ingredient OR a sub-recipe, never
--     both and never neither) and the "a component carries no measure" fence;
--   * D2 — yield positivity, both-or-neither per denomination, no second
--     denomination without a first, and the DIFFERENT-family rule. The
--     `unit_family()` vectors are the SQL mirror of `UnitFamily` in
--     app/lib/core/units/units.dart (the 0012/0014 mirror precedent: change
--     one, change both, and a drift fails a suite on whichever side moved);
--   * D5 — the cycle guard: a direct self-link, a two-step A→B→A, the update
--     leg, that a legal A→B→C chain still links, and that a SOFT-DELETED link
--     doesn't count (only live components make a cycle);
--   * the household fence — `sub_recipe_id`'s FK is global, so a link that
--     reaches another household's recipe must be refused, from the
--     `authenticated` role (where RLS hides the target) AND from a
--     service-role/superuser write (where it doesn't).
--
-- Run by `supabase test db`.

begin;
select plan(45);

-- ---------------------------------------------------------------------------
-- Fixtures: two households, five recipes in A (one soft-deleted), one in B.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','b@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','B1','22222222-2222-2222-2222-222222222222');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000301','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Almonds','g','almond'),
 ('bbbbbbbb-0000-0000-0000-000000000301','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Peppers','g','pepper');

insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000401','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000301','handful',30);

insert into recipe (id, household_id, title, deleted_at) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sausage Sliders', null),
 ('aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Romesco Aioli',   null),
 ('aaaaaaaa-0000-0000-0000-000000000103','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Pretzel Buns',    null),
 ('aaaaaaaa-0000-0000-0000-000000000104','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Garlic Butter',   null),
 ('aaaaaaaa-0000-0000-0000-000000000105','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Retired Sauce',   now()),
 ('bbbbbbbb-0000-0000-0000-000000000101','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Foreign Aioli',   null);

insert into ingredient_group (id, household_id, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000101'),
 ('aaaaaaaa-0000-0000-0000-000000000202','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000102'),
 ('aaaaaaaa-0000-0000-0000-000000000203','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000103'),
 ('aaaaaaaa-0000-0000-0000-000000000204','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000104'),
 ('bbbbbbbb-0000-0000-0000-000000000201','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000101');

-- ---------------------------------------------------------------------------
-- D1 — the identity XOR and the measure fence.
-- ---------------------------------------------------------------------------

select col_is_null(
  'recipe_line_item', 'ingredient_id',
  'ingredient_id is nullable now — a component line has no ingredient (D1)'
);

-- 0025: `optional` is a stored fact about a line, defaulting to "no" so every
-- line written before the column existed keeps meaning what it meant.
select col_default_is(
  'recipe_line_item', 'optional', 'false',
  'optional exists and defaults to false (plan 0025 D6b)'
);

select lives_ok(
  $$ insert into recipe_line_item (household_id, group_id, ingredient_id, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000301','g') $$,
  'an ordinary ingredient line still inserts'
);

select lives_ok(
  $$ insert into recipe_line_item (household_id, group_id, ingredient_id, measure_id, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000301',
             'aaaaaaaa-0000-0000-0000-000000000401','piece') $$,
  'an ingredient line may still carry a measure_id (0009 unchanged)'
);

select lives_ok(
  $$ insert into recipe_line_item (id, household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-0000-0000-0000-000000000501',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000102',0.25,'cup') $$,
  'a component line (sub_recipe_id only) inserts — "¼ cup Romesco Aioli"'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, ingredient_id, sub_recipe_id, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000301',
             'aaaaaaaa-0000-0000-0000-000000000103','cup') $$,
  '23514',
  'new row for relation "recipe_line_item" violates check constraint "line_item_identity_xor"',
  'BOTH ingredient_id and sub_recipe_id is refused (XOR)'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201','cup') $$,
  '23514',
  'new row for relation "recipe_line_item" violates check constraint "line_item_identity_xor"',
  'NEITHER ingredient_id nor sub_recipe_id is refused (XOR)'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, measure_id, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000103',
             'aaaaaaaa-0000-0000-0000-000000000401','piece') $$,
  '23514',
  'new row for relation "recipe_line_item" violates check constraint "line_item_component_has_no_measure"',
  'a component line may not carry a measure_id (measures are an ingredient concept)'
);

-- ---------------------------------------------------------------------------
-- D2 — unit_family(), the SQL mirror of units.dart.
-- ---------------------------------------------------------------------------

select is(unit_family('g'),        'mass',      'unit_family: g is mass');
select is(unit_family('lb'),       'mass',      'unit_family: lb is mass');
select is(unit_family('cup'),      'volume',    'unit_family: cup is volume');
select is(unit_family('fl_oz'),    'volume',    'unit_family: fl_oz is volume');
select is(unit_family('pt'),       'volume',    'unit_family: pt is volume (0024)');
select is(unit_family('qt'),       'volume',    'unit_family: qt is volume (0024)');
select is(unit_family('piece'),    'count',     'unit_family: piece is count');
select is(unit_family('to_taste'), 'imprecise', 'unit_family: to_taste is imprecise');
select is(
  unit_family('batch'), null::text,
  'unit_family: an id units.dart does not carry has no family (batch is a '
  'component denomination, not a Unit)'
);

-- ---------------------------------------------------------------------------
-- D2 — the yield checks.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ update recipe set yield_qty = 1, yield_unit = 'cup'
     where id = 'aaaaaaaa-0000-0000-0000-000000000102' $$,
  'a first denomination sets — "Romesco Aioli makes 1 cup"'
);

select throws_ok(
  $$ update recipe set yield_qty = 0, yield_unit = 'cup'
     where id = 'aaaaaaaa-0000-0000-0000-000000000102' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_qty_check"',
  'yield_qty must be > 0'
);

select throws_ok(
  $$ update recipe set yield_qty = -1, yield_unit = 'cup'
     where id = 'aaaaaaaa-0000-0000-0000-000000000102' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_qty_check"',
  'a negative yield_qty is refused'
);

select throws_ok(
  $$ update recipe set yield_qty = 2, yield_unit = null
     where id = 'aaaaaaaa-0000-0000-0000-000000000103' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_pair"',
  'a yield amount without a unit is half a fact — refused'
);

select throws_ok(
  $$ update recipe set yield_qty = null, yield_unit = 'piece'
     where id = 'aaaaaaaa-0000-0000-0000-000000000103' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_pair"',
  'a yield unit without an amount is half a fact — refused'
);

select throws_ok(
  $$ update recipe set yield_qty_2 = 250, yield_unit_2 = 'g'
     where id = 'aaaaaaaa-0000-0000-0000-000000000103' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_2_needs_first"',
  'no second denomination without a first'
);

select throws_ok(
  $$ update recipe set yield_qty_2 = 250
     where id = 'aaaaaaaa-0000-0000-0000-000000000102' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_2_pair"',
  'a second amount without its unit is refused'
);

select throws_ok(
  $$ update recipe set yield_unit_2 = 'g'
     where id = 'aaaaaaaa-0000-0000-0000-000000000102' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_2_pair"',
  'a second unit without its amount is refused'
);

select throws_ok(
  $$ update recipe set yield_qty = 250, yield_unit = 'g',
                       yield_qty_2 = 0.25, yield_unit_2 = 'kg'
     where id = 'aaaaaaaa-0000-0000-0000-000000000104' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_2_other_family"',
  'the second denomination must be a DIFFERENT family (g + kg is a restatement, '
  'not a bridge)'
);

select throws_ok(
  $$ update recipe set yield_qty = 250, yield_unit = 'g',
                       yield_qty_2 = 250, yield_unit_2 = 'g'
     where id = 'aaaaaaaa-0000-0000-0000-000000000104' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_2_other_family"',
  'the same unit twice is refused by the family rule'
);

select lives_ok(
  $$ update recipe set yield_qty = 250, yield_unit = 'g',
                       yield_qty_2 = 16, yield_unit_2 = 'tbsp'
     where id = 'aaaaaaaa-0000-0000-0000-000000000104' $$,
  'mass + volume bridges — "makes 250 g · 16 tbsp"'
);

select lives_ok(
  $$ update recipe set yield_qty = 8, yield_unit = 'piece',
                       yield_qty_2 = 960, yield_unit_2 = 'g'
     where id = 'aaaaaaaa-0000-0000-0000-000000000103' $$,
  'count + mass bridges — "makes 8 (piece) · 960 g" (the sausage answer)'
);

select throws_ok(
  $$ update recipe set yield_qty_2 = 0
     where id = 'aaaaaaaa-0000-0000-0000-000000000103' $$,
  '23514',
  'new row for relation "recipe" violates check constraint "recipe_yield_qty_2_check"',
  'yield_qty_2 must be > 0 too'
);

select lives_ok(
  $$ update recipe set yield_qty = null, yield_unit = null,
                       yield_qty_2 = null, yield_unit_2 = null
     where id = 'aaaaaaaa-0000-0000-0000-000000000103' $$,
  'clearing both denominations is fine — a yield-less recipe is legal (D2)'
);

-- ---------------------------------------------------------------------------
-- D5 — the cycle guard.
-- ---------------------------------------------------------------------------
-- Live so far: Sliders(101) → Aioli(102), inserted above.

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',1,'batch') $$,
  '23514',
  'a recipe cannot be a component of itself (aaaaaaaa-0000-0000-0000-000000000101)',
  'a direct self-link A→A is refused'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000101',1,'batch') $$,
  '23514',
  'linking recipe aaaaaaaa-0000-0000-0000-000000000101 would create a component cycle',
  'a two-step cycle A→B→A is refused'
);

select lives_ok(
  $$ insert into recipe_line_item (id, household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-0000-0000-0000-000000000502',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000202',
             'aaaaaaaa-0000-0000-0000-000000000103',1,'batch') $$,
  'a legal chain links: A→B already, now B→C'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000203',
             'aaaaaaaa-0000-0000-0000-000000000101',1,'batch') $$,
  '23514',
  'linking recipe aaaaaaaa-0000-0000-0000-000000000101 would create a component cycle',
  'the three-step close C→A is refused (the walk is transitive)'
);

select lives_ok(
  $$ insert into recipe_line_item (id, household_id, group_id, ingredient_id, quantity, unit)
     values ('aaaaaaaa-0000-0000-0000-000000000503',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000203',
             'aaaaaaaa-0000-0000-0000-000000000301',100,'g') $$,
  'a plain ingredient line on C, to be re-pointed by the update leg'
);

select throws_ok(
  $$ update recipe_line_item
       set ingredient_id = null,
           sub_recipe_id = 'aaaaaaaa-0000-0000-0000-000000000101'
     where id = 'aaaaaaaa-0000-0000-0000-000000000503' $$,
  '23514',
  'linking recipe aaaaaaaa-0000-0000-0000-000000000101 would create a component cycle',
  'the UPDATE leg is guarded too — converting a line into a cycling component is refused'
);

-- Soft delete B→C, then C→B becomes legal: only LIVE links make a cycle.
update recipe_line_item set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000502';

select lives_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000203',
             'aaaaaaaa-0000-0000-0000-000000000102',1,'batch') $$,
  'a soft-deleted link does not make a cycle (the walk is live-links-only)'
);

-- ---------------------------------------------------------------------------
-- The household fence — the FK is global, the link must not be.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'bbbbbbbb-0000-0000-0000-000000000101',1,'batch') $$,
  '23503',
  'sub_recipe_id bbbbbbbb-0000-0000-0000-000000000101 is not a live recipe in this household',
  'a superuser/service-role write cannot link across households either'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000105',1,'batch') $$,
  '23503',
  'sub_recipe_id aaaaaaaa-0000-0000-0000-000000000105 is not a live recipe in this household',
  'a soft-deleted recipe is not linkable'
);

-- The same fence from the client role, where RLS hides the target entirely.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  current_household_id(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'acting as a member of House A'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'bbbbbbbb-0000-0000-0000-000000000101',1,'batch') $$,
  '23503',
  'sub_recipe_id bbbbbbbb-0000-0000-0000-000000000101 is not a live recipe in this household',
  'authenticated: a cross-household sub_recipe_id is refused (RLS hides it, the '
  'guard names it)'
);

select lives_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000104',2,'tbsp') $$,
  'authenticated: linking the household''s OWN recipe still works — "2 tbsp '
  'Garlic Butter"'
);

select throws_ok(
  $$ insert into recipe_line_item (household_id, group_id, sub_recipe_id, quantity, unit)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000201',
             'aaaaaaaa-0000-0000-0000-000000000101',1,'batch') $$,
  '23514',
  'a recipe cannot be a component of itself (aaaaaaaa-0000-0000-0000-000000000101)',
  'authenticated: the cycle guard applies to the client role too'
);

reset role;

select is(
  (select count(*)::int from recipe_line_item
     where household_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  0,
  'nothing leaked into House B'
);

select * from finish();
rollback;
