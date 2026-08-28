-- seed_measures.sql — HAND-CURATED starter measures for the template vocab
-- (roadmap step 7.6). Runs after seed.sql (which creates the template
-- household + vocab); rows join onto ingredients by match_text, so a vocab
-- regeneration that drops a row simply drops its measures too.
--
-- seed.sql is generated (never hand-edit); measures are curated judgment, so
-- they live here. `ensure_onboarded` (0009) clones these to new households.
--
-- Weights are honest, sourced numbers (invariant 3 — the count↔mass bridge is
-- a stored weight, never a guess):
--   * "USDA FDC portion" — the gram weight of that portion in USDA FoodData
--     Central (SR Legacy / FNDDS food portions; CC0).
--   * "retail pack"      — the printed net weight of the common retail unit.
--   * "typical"          — a typical mid-size specimen where FDC has no clean
--     portion; deliberately round numbers, clearly approximate.

begin;

insert into ingredient_measure (household_id, ingredient_id, label, grams, sort_order)
select '00000000-0000-0000-0000-0000000000aa', i.id, m.label, m.grams, m.sort_order
from ingredient i
join (values
  -- match_text            label                grams  sort  source
  ('garlic',               'clove',                 3, 0),  -- USDA FDC portion
  ('onion',                'onion, medium',       110, 0),  -- USDA FDC portion
  ('red onion',            'onion, medium',       110, 0),  -- USDA FDC portion
  ('shallot',              'shallot, medium',      30, 0),  -- typical
  ('scallion',             'scallion',             15, 0),  -- USDA FDC portion
  ('carrot',               'carrot, medium',       61, 0),  -- USDA FDC portion
  ('celery',               'stalk, medium',        40, 0),  -- USDA FDC portion
  ('russet potato',        'potato, medium',      213, 0),  -- USDA FDC portion
  ('russet potato',        'potato, large',       299, 1),  -- USDA FDC portion
  ('gold potato',          'potato, medium',      213, 0),  -- USDA FDC portion
  ('red potato',           'potato, medium',      213, 0),  -- USDA FDC portion
  ('sweet potato',         'sweetpotato, medium', 130, 0),  -- USDA FDC portion
  ('tomato',               'tomato, medium',      123, 0),  -- USDA FDC portion
  ('zucchini',             'zucchini, medium',    196, 0),  -- USDA FDC portion
  ('cucumber',             'cucumber',            301, 0),  -- USDA FDC portion
  ('avocado',              'avocado, medium',     201, 0),  -- USDA FDC portion
  ('banana',               'banana, medium',      118, 0),  -- USDA FDC portion
  ('lime',                 'lime',                 67, 0),  -- USDA FDC portion
  ('lemon',                'lemon',                84, 0),  -- typical
  ('jalapeño',             'jalapeño',             14, 0),  -- USDA FDC portion
  ('red bell pepper',      'pepper, medium',      119, 0),  -- USDA FDC portion
  ('green bell pepper',    'pepper, medium',      119, 0),  -- USDA FDC portion
  ('extra firm tofu',      'block (14 oz)',       397, 0),  -- retail pack
  ('silken tofu',          'block (12.3 oz)',     349, 0),  -- retail pack (shelf-stable)
  ('tempeh',               'package (8 oz)',      227, 0),  -- retail pack
  ('coconut milk',         'can (400 ml)',        400, 0),  -- retail pack (~1.0 g/ml)
  ('chickpea canned',      'can (15 oz)',         425, 0),  -- retail pack
  ('black bean canned',    'can (15 oz)',         425, 0)   -- retail pack
) as m(ing_match, label, grams, sort_order) on i.match_text = m.ing_match
where i.household_id = '00000000-0000-0000-0000-0000000000aa';

commit;
