-- pgTAP: a density keeps the sentence it was said in (0053).
--
-- What is defended here:
--
--   * the SHAPE — the four columns exist and are nullable, so a build that
--     predates them writes an ingredient exactly as before;
--   * the WHOLE — a sentence is all four columns or none, and neither amount
--     can be zero;
--   * the OLD DOOR — a write of `density_g_per_ml` alone is accepted over a
--     row that holds a sentence, because the last shipped build writes exactly
--     that. The app then shows the number, not the stale sentence.

begin;
select plan(9);

insert into household (id, name) values
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('bbbbbbbb-0000-0000-0000-000000000501','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Granola','g','granola');

-- 1 · The shape.

select col_is_null('public', 'ingredient', 'density_amount',
  'a row need not say its density');
select col_is_null('public', 'ingredient', 'density_unit', 'nor its unit');
select col_is_null('public', 'ingredient', 'density_weighs_amount',
  'nor what it weighs');
select col_is_null('public', 'ingredient', 'density_weighs_unit',
  'nor in what');

-- 2 · The whole.

select throws_ok(
  $$ update ingredient set density_amount = 0.3333, density_unit = 'cup'
      where id = 'bbbbbbbb-0000-0000-0000-000000000501' $$,
  '23514', null,
  'half a sentence says nothing'
);

select throws_ok(
  $$ update ingredient set density_amount = 0, density_unit = 'cup',
            density_weighs_amount = 40, density_weighs_unit = 'g'
      where id = 'bbbbbbbb-0000-0000-0000-000000000501' $$,
  '23514', null,
  'nothing weighs nothing'
);

select lives_ok(
  $$ update ingredient set density_g_per_ml = 0.50721034,
            density_amount = 0.333333333333, density_unit = 'cup',
            density_weighs_amount = 40, density_weighs_unit = 'g'
      where id = 'bbbbbbbb-0000-0000-0000-000000000501' $$,
  '1/3 cup weighs 40 g is kept beside the number derived from it'
);

-- 3 · The old door stays open.

select lives_ok(
  $$ update ingredient set density_g_per_ml = 0.9
      where id = 'bbbbbbbb-0000-0000-0000-000000000501' $$,
  'an older build''s bare density write still lands'
);

select lives_ok(
  $$ update ingredient set density_g_per_ml = null, density_amount = null,
            density_unit = null, density_weighs_amount = null,
            density_weighs_unit = null
      where id = 'bbbbbbbb-0000-0000-0000-000000000501' $$,
  'a density is taken back by clearing it whole'
);

select finish();
rollback;
