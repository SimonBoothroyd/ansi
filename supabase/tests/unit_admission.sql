-- pgTAP: the unit-admission schema — `default_allowed_units()` and
-- `density_unlocked_units()`, the SQL mirrors of the app's derived rule
-- (`defaultAllowedUnitSet` / `densityUnlockedUnits` / `kImpreciseCategoryGates`
-- in allowed_units.dart), plus the two ingredient triggers that write it.
--
-- The rule is ADR-0008's model as amended by ADR-0009 (a density unlocks the
-- other family whatever the default unit), ADR-0014 (all to all) and
-- ADR-0015 (a piece weight is a row fact): the basis family whole and
-- unconditionally, the other mass/volume family whole behind a stored
-- density, `piece` on a count row THAT SAYS WHAT ONE WEIGHS, and the
-- category's imprecise words. There is no kitchen trim, no magnitude gate and
-- no `mg`.
--
-- The named shapes — the yeast, the flour, the mango, the rest — are not
-- written out twice: they live in
-- `app/test/features/ingredients/allowed_units_vectors.json`, which the Dart
-- suite loops and which `seed/scripts/gen_admission_vectors.ts` renders as the
-- GENERATED block below. Editing the JSON without regenerating fails that
-- script's own Deno test, so the two mirrors cannot drift apart quietly. The
-- remaining vectors here are hand-written because they are the SQL side's
-- business alone — each names the Dart test it twins, where there is one. The
-- Dart side is the source of truth; a stored list is a SET, so where Dart
-- asserts a display ORDER (`allowedUnitsFor` runs `_orderUnits`) the jsonb
-- here is pinned in the function's emission order instead, and the members are
-- what is compared.
--
-- Also pins: the BEFORE INSERT trigger that materializes the list, that an
-- explicit list is never overridden, that a backfill UNIONS rather than
-- re-materializes (curated removals survive, curated additions survive), that
-- the retired seed-level produce patch's admissions fall out of the rule, the
-- density→allowed_units union trigger and the piece-weight union trigger
-- beside it, 0037's `mg` removal and its widening fence, the USDA search door
-- (`probe_usda` — read-only, ranked, no floor), the basis_amount rename +
-- positivity check, and that `grams` is gone.
--
-- ADR-0015 turns the old `piece` curation guard inside out: every seeded
-- piece-default row now carries a piece weight and therefore ADMITS `piece`,
-- and nothing else may. That is a rule again rather than 143 hand-written
-- removals, so what is guarded here is the seed's data landing on it — a
-- stranded count default, or a `piece` on a row nobody counts.
--
-- 0027 widened the probe to return `description` / `category` with a limit,
-- in one total order; 0029 replaced its trigram body with BM25 over a derived
-- index and dropped the prefill trigger that used to copy a match onto a stub
-- on insert and on rename. Nothing prefills: the door is read-only and a
-- person applies the pick. Those assertions sit in the probe block below;
-- `usda_search.sql` pins the ranker itself and that the trigger stays gone.
--
-- Run by `supabase test db`.

begin;
select plan(121);

-- ---------------------------------------------------------------------------
-- default_allowed_units() vectors. The named shapes come from the shared
-- JSON, rendered below; what follows the generated block is the rest of the
-- rule — the legs allowed_units_test.dart states in prose rather than as a
-- vector, and the two units only ever read off a label.
-- ---------------------------------------------------------------------------

-- >>> GENERATED from app/test/features/ingredients/allowed_units_vectors.json
-- by supabase/seed/scripts/gen_admission_vectors.ts — do not hand-edit.
--
-- One assertion per shape in the shared vector file the app's
-- allowed_units_test.dart loops. Membership is compared, not order:
-- the app sorts for display, this function emits its own order.
select is(
  (
    select jsonb_agg(u order by u)
    from jsonb_array_elements_text(
      default_allowed_units(v.default_unit, v.basis, v.density, v.category,
                            v.piece_basis_amount)
    ) as u
  ),
  (
    select jsonb_agg(u order by u)
    from jsonb_array_elements_text(v.expect) as u
  ),
  'the ' || v.shape || ' shape: ' || v.why
)
from (values
  (
    'yeast',
    'tsp',
    'g',
    null::numeric,
    null::numeric,
    'baking'::text,
    '["g","kg","oz","lb"]'::jsonb,
    'a spoon default with no density says the whole mass family and no volume unit at all — being sold by the spoon does not make spoons convertible'
  ),
  (
    'flour',
    'cup',
    'g',
    0.59,
    null,
    'baking',
    '["cup","tsp","tbsp","fl_oz","ml","l","pt","qt","g","kg","oz","lb"]',
    'a cup default with a density: both families whole, twelve chips, and the household prunes what it will never say'
  ),
  (
    'olive-oil',
    'tbsp',
    'g',
    0.91,
    null,
    'fats & oils',
    '["tbsp","tsp","fl_oz","cup","ml","l","pt","qt","g","kg","oz","lb","pinch","dash","to_taste"]',
    'a spoon default with a density: both families plus the oil class''s imprecise words — nobody takes a handful of oil'
  ),
  (
    'egg',
    'piece',
    'g',
    null,
    50,
    'produce',
    '["piece","g","kg","oz","lb","handful"]',
    'a count default that says what one weighs: its own piece, the whole basis family, and the one imprecise word produce earns'
  ),
  (
    'egg, unweighed',
    'piece',
    'g',
    null,
    null,
    'produce',
    '["g","kg","oz","lb","handful"]',
    'the same row before anybody says what one egg weighs: no piece at all — a piece nothing can weigh is one nothing can convert, total or shop, so it is not offered (ADR-0015)'
  ),
  (
    'salt',
    'tsp',
    'g',
    null,
    null,
    'spices & seasoning',
    '["g","kg","oz","lb","pinch","dash","handful","to_taste"]',
    'the seasoning category admits the whole imprecise tail, and the spoons still need a density like everyone else''s'
  ),
  (
    'mango',
    'piece',
    'g',
    0.66,
    200,
    'produce',
    '["piece","g","kg","oz","lb","tsp","tbsp","fl_oz","cup","ml","l","pt","qt","handful"]',
    'a count default WITH a density admits the volume family whole — "1 cup diced mango" is a real line, and so is half a litre of purée'
  ),
  (
    'avocado',
    'piece',
    'g',
    0.634,
    201,
    'produce',
    '["piece","g","kg","oz","lb","tsp","tbsp","fl_oz","cup","ml","l","pt","qt","handful"]',
    'the row ADR-0010''s curation pass used to take piece AWAY from by hand: it weighs 201 g, so the rule now gives it piece outright and no per-row removal is involved'
  ),
  (
    'garlic',
    'g',
    'g',
    null,
    3,
    'produce',
    '["g","kg","oz","lb","handful"]',
    'a weight on a row nobody counts admits nothing: piece is a fact about a COUNT default, so a gram-default row carrying a 3 g clove weight still says no piece'
  ),
  (
    'broth',
    'cup',
    'ml',
    null,
    null,
    'pantry',
    '["cup","tsp","tbsp","fl_oz","ml","l","pt","qt"]',
    'a per-ml row''s volume default IS its basis family, so it stands alone — the whole volume ladder, and no gram leg until a density arrives'
  ),
  (
    'milk',
    'cup',
    'ml',
    1.03,
    null,
    'dairy',
    '["cup","tsp","tbsp","fl_oz","ml","l","pt","qt","g","kg","oz","lb"]',
    'the same per-ml row once it has a density: the mass family unlocks behind the basis family'
  ),
  (
    'rice',
    'g',
    'g',
    null,
    null,
    'grains',
    '["g","kg","oz","lb"]',
    'a gram default on its own basis family says the whole mass family, and no volume without a density'
  ),
  (
    'chicken-thigh',
    'lb',
    'g',
    null,
    null,
    'proteins',
    '["lb","g","kg","oz"]',
    'the same family entered from the customary end: a pound default admits exactly what a gram default does'
  ),
  (
    'butter',
    'oz',
    'g',
    0.91,
    null,
    'dairy',
    '["oz","g","kg","lb","tsp","tbsp","fl_oz","cup","ml","l","pt","qt"]',
    'an ounce default with a density: the mass family plus the volume family the density bridges to, fl oz included — it is an ordinary kitchen unit here'
  )
) as v(shape, default_unit, basis, density, piece_basis_amount, category,
        expect, why);
-- <<< GENERATED

-- The yeast shape read the other way: a density is what buys the volume
-- family, spoons and litres alike.
select is(
  default_allowed_units('tsp', 'g', 0.4, 'baking', null),
  '["g", "kg", "oz", "lb", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", '
  '"qt"]'::jsonb,
  'tsp default /g with density: the volume family comes whole'
);

-- The olive-oil shape's refusal — the per-word category gate, which the
-- vector's admitted list cannot state.
select ok(
  not (default_allowed_units('tbsp', 'g', 0.91, 'fats & oils', null) ? 'handful'),
  'J3: nobody takes a handful of oil'
);

-- Dart: 'an imprecise default keeps its whole tail + the basis family'.
select is(
  default_allowed_units('pinch', 'g', null, 'spices & seasoning', null),
  '["g", "kg", "oz", "lb", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'an imprecise default yields the basis family + the imprecise tail'
);

-- Dart: 'a mass default /g with density unlocks the volume family'. Oats:
-- grams AND cups are both honest; no piece.
select is(
  default_allowed_units('g', 'g', 0.4, null, null),
  '["g", "kg", "oz", "lb", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", '
  '"qt"]'::jsonb,
  'g default /g with density: both families whole, no piece'
);

-- The same rule from the per-ml side (an SQL-only extra): a count-default
-- liquid-ish row unlocks the MASS family, and the basis volume is not
-- duplicated.
select is(
  default_allowed_units('piece', 'ml', 1.0, 'dairy', 100),
  '["piece", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", "qt", "g", '
  '"kg", "oz", "lb"]'::jsonb,
  'count default /ml with density: mass unlocks, the basis volume is not '
  'duplicated'
);

-- Dart: 'an imprecise default with a density unlocks both families too, and
-- keeps its whole tail INCLUDING handful'.
select is(
  default_allowed_units('pinch', 'g', 1, 'spices & seasoning', null),
  '["g", "kg", "oz", "lb", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", '
  '"qt", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'imprecise default with density: both families whole, whole tail kept'
);

-- Dart: 'fl oz is an ordinary volume unit'. It is admitted as a member of the
-- family everywhere the family is, and as a DEFAULT it needs a density like
-- any other cross-family one.
select ok(
  default_allowed_units('cup', 'ml', null, null, null) ? 'fl_oz'
  and default_allowed_units('g', 'g', 1, null, null) ? 'fl_oz'
  and default_allowed_units('fl_oz', 'g', 1, null, null) ? 'fl_oz',
  'fl_oz rides with its family, and stands as a default once bridged'
);
select is(
  (select count(*)::int
     from unnest(array['g','kg','oz','lb','ml','l','tsp','tbsp','fl_oz','cup',
                       'pt','qt',
                       'piece','pinch','dash','handful','to_taste']) as d(unit)
    where not (default_allowed_units(d.unit, 'g', 1, null, null) ? 'fl_oz')),
  0,
  'every density-bridged row admits fl_oz — it is not excepted any more'
);

-- Dart: 'mg is gone from the catalog, so nothing can offer it'. It is not a
-- family member and not a default: `unit_family` does not know the id at all,
-- no derived list can name it, and no stored row still does.
select is(
  unit_family('mg'), null::text,
  'mg is not a unit any more (0037)'
);
select is(
  (select count(*)::int
     from unnest(array['g','kg','oz','lb','ml','l','tsp','tbsp','fl_oz','cup',
                       'pt','qt',
                       'piece','pinch','dash','handful','to_taste']) as d(unit)
    where default_allowed_units(d.unit, 'g', 1, null, null) ? 'mg'
       or default_allowed_units(d.unit, 'ml', 1, null, null) ? 'mg'),
  0,
  'no default unit, on either basis, admits mg'
);
select is(
  (select count(*)::int from ingredient
    where default_unit = 'mg' or allowed_units ? 'mg'),
  0,
  'and no stored row still says mg (the 0037 conversion)'
);

-- Dart: 'the default unit is admitted when its family is — and a row whose
-- default falls outside says so rather than smuggling it in'. Over every
-- ingredient unit (`batch` is deliberately absent): with a density every
-- default is sayable; without one, exactly the cross-family (volume, on a
-- per-g row) defaults are stranded. The `defaultUnitNeedsDensity` /
-- `unitSayableAsDefault` / `basisDefaultUnitFix` halves of that Dart test are
-- app-side read rules with no SQL leg.
select is(
  (select count(*)::int
     from (values ('g'), ('kg'), ('oz'), ('lb'),
                  ('ml'), ('l'), ('tsp'), ('tbsp'), ('fl_oz'), ('cup'),
                  ('pt'), ('qt'),
                  ('piece'), ('pinch'), ('dash'), ('handful'), ('to_taste'))
          as u(unit)
    where not (default_allowed_units(u.unit, 'g', 1, null, 1) ? u.unit)),
  0,
  'D4c: with a density every default unit is sayable'
);
select is(
  (select count(*)::int
     from (values ('g', 'mass'), ('kg', 'mass'),
                  ('oz', 'mass'), ('lb', 'mass'),
                  ('ml', 'volume'), ('l', 'volume'), ('tsp', 'volume'),
                  ('tbsp', 'volume'), ('fl_oz', 'volume'), ('cup', 'volume'),
                  ('pt', 'volume'), ('qt', 'volume'),
                  ('piece', 'count'), ('pinch', 'imprecise'),
                  ('dash', 'imprecise'), ('handful', 'imprecise'),
                  ('to_taste', 'imprecise'))
          as u(unit, family)
    where (default_allowed_units(u.unit, 'g', null, null, 1) ? u.unit)
          <> (u.family <> 'volume')),
  0,
  'D4c: without one, exactly the cross-family defaults are stranded'
);

-- ADR-0014 read as a property rather than as examples: a family is admitted
-- WHOLE or not at all, on either basis, with or without a number.
select is(
  (select count(*)::int
     from (values ('g', null::numeric), ('g', 1), ('piece', 1), ('pinch', 1),
                  ('cup', 1), ('tsp', 1))
          as r(unit, density)
     cross join unnest(array['g','kg','oz','lb']) as m(unit)
    where not (default_allowed_units(r.unit, 'g', r.density, null, null) ? m.unit)),
  0,
  'the basis family is admitted whole, density or not (ADR-0014)'
);
select is(
  (select count(*)::int
     from (values ('g'), ('kg'), ('oz'), ('lb'), ('piece'), ('pinch'))
          as r(unit)
     cross join unnest(array['tsp','tbsp','fl_oz','cup','ml','l','pt','qt'])
          as v(unit)
    where not (default_allowed_units(r.unit, 'g', 1, null, null) ? v.unit)
       or (default_allowed_units(r.unit, 'g', null, null, null) ? v.unit)),
  0,
  'the other family arrives whole with a density, and not at all without one'
);

-- ---------------------------------------------------------------------------
-- The per-word imprecise gate (J3) — mirrors allowed_units_test.dart group
-- 'impreciseUnitsFor — the per-word category gate'. Read through
-- default_allowed_units() on a g-default per-g row with no density, whose
-- only other admissions are the mass family ["g","kg","oz","lb"].
-- ---------------------------------------------------------------------------

-- Dart: 'the whole mapping, category by category'. Owner ruling: pinch and
-- dash belong to the spice/seasoning/oil classes; handful belongs to greens,
-- which `produce` is the nearest category the vocabulary can express.
select is(
  default_allowed_units('g', 'g', null, 'spices & seasoning', null),
  '["g", "kg", "oz", "lb", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'spices & seasoning earns all four words'
);
select is(
  default_allowed_units('g', 'g', null, 'fats & oils', null),
  '["g", "kg", "oz", "lb", "pinch", "dash", "to_taste"]'::jsonb,
  'fats & oils earns pinch/dash/to_taste — no handful'
);
select is(
  default_allowed_units('g', 'g', null, 'produce', null),
  '["g", "kg", "oz", "lb", "handful"]'::jsonb,
  'produce earns handful and nothing else'
);
select is(
  (select count(*)::int
     from unnest(array['pantry','grains','baking','dairy','proteins']) as c(cat)
    where default_allowed_units('g', 'g', null, c.cat, null)
            <> '["g", "kg", "oz", "lb"]'::jsonb),
  0,
  'pantry / grains / baking / dairy / proteins earn no imprecise word'
);
-- An uncategorised row earns nothing — the gate is a fact about the
-- category, so no category is no licence.
select is(
  default_allowed_units('g', 'g', null, null, null),
  '["g", "kg", "oz", "lb"]'::jsonb,
  'a null category earns no imprecise word'
);
select is(
  default_allowed_units('g', 'g', null, '', null),
  '["g", "kg", "oz", "lb"]'::jsonb,
  'an empty category earns no imprecise word'
);

-- Dart: 'THE KALE VECTOR: greens take a handful, never a pinch or a dash'.
-- Under 0014's whole-set gate a server-materialized kale row could name
-- `dash`; the app offered only `handful`.
select is(
  default_allowed_units('cup', 'g', 0.2, 'produce', null),
  '["g", "kg", "oz", "lb", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", '
  '"qt", "handful"]'::jsonb,
  'kale (cup /g, density, produce): a handful, never a pinch or a dash'
);

-- Dart: 'a row whose DEFAULT unit is imprecise can always say it, whatever
-- its category'.
select is(
  default_allowed_units('pinch', 'g', null, 'produce', null),
  '["g", "kg", "oz", "lb", "pinch", "handful"]'::jsonb,
  'a pinch-default produce row keeps pinch (its own word) + handful'
);
select is(
  default_allowed_units('dash', 'g', null, 'grains', null),
  '["g", "kg", "oz", "lb", "dash"]'::jsonb,
  'a dash-default grains row keeps dash though the category earns nothing'
);

-- Dart: 'the category is matched case- and whitespace-insensitively'.
select is(
  default_allowed_units('g', 'g', null, '  Produce ', null),
  '["g", "kg", "oz", "lb", "handful"]'::jsonb,
  'the category gate trims and case-folds (  Produce  → handful)'
);
select is(
  jsonb_array_length(default_allowed_units('g', 'g', null, 'Spices & Seasoning', null)),
  8,
  'Spices & Seasoning matches the lower-case key (the mass four + four words)'
);

-- ---------------------------------------------------------------------------
-- density_unlocked_units(default, basis) — what a density buys a row, derived
-- as derived(with) − derived(without) (0021). Mirrors `densityUnlockedUnits`
-- / `densityStrippedUnits` in allowed_units.dart (group 'densityStrippedUnits
-- — what deleting a density takes back'), and is what the 0014 trigger and
-- the 0021 backfill union in, so it gets its own vectors.
-- ---------------------------------------------------------------------------

-- Dart: 'what a density is worth is the whole other family'. There is one
-- answer per BASIS now, not one per default unit: a per-100 g row gains the
-- volume family, a per-100 ml row the mass family.
select is(
  density_unlocked_units('piece', 'g'),
  array['tsp','tbsp','fl_oz','cup','ml','l','pt','qt'],
  'a piece /g default: the density buys the volume family (the mango shape)'
);
select is(
  density_unlocked_units('cup', 'g'),
  array['tsp','tbsp','fl_oz','cup','ml','l','pt','qt'],
  'a cup /g default: the same family, the row''s own default included (the '
  'flour shape)'
);
select is(
  density_unlocked_units('ml', 'ml'), array['g','kg','oz','lb'],
  'an ml /ml default: the density buys the mass family (the milk shape)'
);
select is(
  (select count(*)::int
     from (values ('g'), ('kg'), ('oz'), ('lb'), ('tsp'), ('tbsp'), ('cup'),
                  ('piece'), ('pinch'))
          as d(unit)
    where density_unlocked_units(d.unit, 'g')
            <> array['tsp','tbsp','fl_oz','cup','ml','l','pt','qt']),
  0,
  'every per-100 g row is bought the same thing by a density: the volume '
  'family, whatever its default unit'
);

-- Dart: 'what is stripped is exactly what a density adds — the two are one
-- rule read in opposite directions'. For each shape: the rule with the
-- density, minus what the density unlocks, is the rule without it (compared
-- as sets — a stored list is a set); and nothing unlocked is ever the basis
-- base the basis leg supplies.
select is(
  (select count(*)::int
     from (values ('piece', 'g', 'produce'), ('g', 'g', null),
                  ('cup', 'g', 'baking'), ('ml', 'ml', null),
                  ('to_taste', 'g', 'spices & seasoning'))
          as s(d, b, c)
    where not (
      (select coalesce(jsonb_agg(w.unit), '[]'::jsonb)
         from jsonb_array_elements_text(default_allowed_units(s.d, s.b, 1, s.c, null))
              as w(unit)
        where not (w.unit = any(density_unlocked_units(s.d, s.b))))
        @> default_allowed_units(s.d, s.b, null, s.c, null)
      and default_allowed_units(s.d, s.b, null, s.c, null) @>
      (select coalesce(jsonb_agg(w.unit), '[]'::jsonb)
         from jsonb_array_elements_text(default_allowed_units(s.d, s.b, 1, s.c, null))
              as w(unit)
        where not (w.unit = any(density_unlocked_units(s.d, s.b)))))),
  0,
  'derived(with) − unlocked = derived(without), shape by shape'
);
select is(
  (select count(*)::int
     from (values ('piece', 'g'), ('g', 'g'), ('cup', 'g'), ('ml', 'ml'),
                  ('to_taste', 'g'), ('tbsp', 'g'), ('piece', 'ml'))
          as s(d, b)
    where (case when s.b = 'ml' then 'ml' else 'g' end)
          = any(density_unlocked_units(s.d, s.b))),
  0,
  'nothing a density unlocks is ever the basis base'
);

-- ---------------------------------------------------------------------------
-- Materialization trigger (0012): null → the rule; explicit → verbatim.
-- ---------------------------------------------------------------------------

insert into household (id, name)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Test');

insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text)
values ('cccccccc-0000-0000-0000-000000000001',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Yeast', 'tsp', 'baking',
  'manual', 'trigger yeast');
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["g", "kg", "oz", "lb"]'::jsonb,
  'inserting without allowed_units materializes the derived defaults — the '
  'basis family, whole'
);

insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, allowed_units)
values ('cccccccc-0000-0000-0000-000000000002',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Explicit Row', 'tsp', 'baking',
  'manual', 'explicit row', '["cup"]'::jsonb);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000002'),
  '["cup"]'::jsonb,
  'an explicitly supplied allowed_units list is never overridden'
);

-- The migration backfill left no live vocab row without a list.
select is(
  (select count(*)::int from ingredient
     where allowed_units is null and deleted_at is null),
  0,
  'no live ingredient is left without an allowed_units list'
);

-- ---------------------------------------------------------------------------
-- 0014 / 0021: a density ARRIVING on an existing row extends allowed_units —
-- by UNION, never by re-materializing (ingredient_density_unlocks_units),
-- and since 0021 with what the density ACTUALLY buys the row.
-- ---------------------------------------------------------------------------

-- A hand-edited row: one unit the defaults would never give it ('to_taste'
-- on a baking row), and a list pruned right down. The density unions the
-- volume family in and keeps every word the household stated.
update ingredient set allowed_units = '["tsp", "to_taste"]'::jsonb
where id = 'cccccccc-0000-0000-0000-000000000001';

update ingredient set density_g_per_ml = 0.55
where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["tsp", "to_taste", "tbsp", "fl_oz", "cup", "ml", "l", "pt", "qt"]'::jsonb,
  'a density arriving unions what it unlocks and keeps the user''s own list'
);

-- Idempotent: re-stating the same density changes nothing, and an unrelated
-- update never touches the list.
update ingredient set density_g_per_ml = 0.55
where id = 'cccccccc-0000-0000-0000-000000000001';
update ingredient set canonical_name = 'Trigger Yeast II'
where id = 'cccccccc-0000-0000-0000-000000000001';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["tsp", "to_taste", "tbsp", "fl_oz", "cup", "ml", "l", "pt", "qt"]'::jsonb,
  'an unchanged density and an unrelated edit both leave the list alone'
);

-- THE FLOUR SHAPE, server-side. A cup-default per-100 g row whose list a D4b
-- `clearDensity` stripped to the basis family (the app's own honest write).
-- When a density lands SERVER-side the trigger unions the volume family the
-- density actually buys — the row's own default unit included, which is what
-- makes the row sayable again at all.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, allowed_units)
values ('cccccccc-0000-0000-0000-00000000000a',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Flour', 'cup', 'baking',
  'seed', 'trigger flour', '["g", "kg"]'::jsonb);
update ingredient set density_g_per_ml = 0.59
where id = 'cccccccc-0000-0000-0000-00000000000a';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-00000000000a'),
  '["g", "kg", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", "qt"]'::jsonb,
  'a density landing on a stripped cup /g row restores its own default''s '
  'family (the flour shape)'
);

-- …and from the per-ml side: a materialized ml-default per-ml row gains the
-- mass family, and only that, when its density lands.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, macros_basis)
values ('cccccccc-0000-0000-0000-00000000000b',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Milk', 'ml', 'dairy',
  'seed', 'trigger milk', 'ml');
update ingredient set density_g_per_ml = 1.03
where id = 'cccccccc-0000-0000-0000-00000000000b';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-00000000000b'),
  '["tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", "qt", "g", "kg", "oz", '
  '"lb"]'::jsonb,
  'a density landing on an ml /ml row unions the mass family and nothing '
  'else (the milk shape)'
);

-- 0021's backfill post-state, as an invariant over the whole table: no row
-- that carries a density and a mass/volume default is missing that default
-- from its own list. The backfill repaired exactly this shape and nothing
-- else; the trigger above keeps it true from here on.
select is(
  (select count(*)::int from ingredient
     where density_g_per_ml is not null
       and allowed_units is not null
       and default_unit in ('g','kg','oz','lb',
                            'ml','l','tsp','tbsp','fl_oz','cup','pt','qt')
       and not (allowed_units ? default_unit)),
  0,
  'no density-carrying mass/volume row lacks its own default unit (0021 backfill)'
);

-- ---------------------------------------------------------------------------
-- The US pair (0024). `pt` and `qt` are volume units like any other now:
-- admitted with their family, stranded as defaults without a density.
-- Mirrors allowed_units_test.dart group 'ADR-0014 — all to all'.
-- ---------------------------------------------------------------------------

select is(
  default_allowed_units('qt', 'ml', null, null, null),
  '["tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", "qt"]'::jsonb,
  'a qt default /ml: its own family, whole'
);
select is(
  default_allowed_units('pt', 'g', 1.0, null, null),
  '["g", "kg", "oz", "lb", "tsp", "tbsp", "fl_oz", "cup", "ml", "l", "pt", '
  '"qt"]'::jsonb,
  'a pt default /g with density: both families, whole'
);
select is(
  default_allowed_units('pt', 'g', null, null, null),
  '["g", "kg", "oz", "lb"]'::jsonb,
  'a pt default /g without density: stranded like any cross-family default '
  '(D4c)'
);
-- The magnitude gate is gone with the rest of the trim: a spoon-default row
-- with a density says quarts, and a household that never will turns the chip
-- off.
select ok(
  default_allowed_units('tsp', 'g', 0.4, null, null) ? 'qt'
  and default_allowed_units('tsp', 'ml', null, null, null) ? 'l',
  'a spoon default says litres and quarts too — the household prunes, not '
  'the rule'
);

-- The 0024 backfill's post-state, as an invariant over the whole table: no
-- stored list that names `l` and whose recomputed defaults admit `qt` lacks
-- `qt`; same for `cup` and `pt`.
select is(
  (select count(*)::int from ingredient i
     where i.allowed_units is not null
       and (   (i.allowed_units ? 'l' and not (i.allowed_units ? 'qt')
                and default_allowed_units(i.default_unit, i.macros_basis,
                                          i.density_g_per_ml, i.category,
                                          i.piece_basis_amount) ? 'qt')
            or (i.allowed_units ? 'cup' and not (i.allowed_units ? 'pt')
                and default_allowed_units(i.default_unit, i.macros_basis,
                                          i.density_g_per_ml, i.category,
                                          i.piece_basis_amount) ? 'pt'))),
  0,
  'every row that says l/cup and whose rule admits qt/pt says qt/pt'
);
-- …reaching the row the pair was added for: "1 quart broth" lands on a chip.
select ok(
  (select allowed_units ? 'qt' and allowed_units ? 'pt' and allowed_units ? 'cup'
     from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text = 'vegetable broth'),
  'vegetable broth (cup default) admits qt and pt beside its cup'
);

-- ---------------------------------------------------------------------------
-- 0037 / ADR-0014: all to all, `mg` gone, and the widening fence.
--
-- The rule itself is pinned above. What this block is about is the MIGRATION:
-- `allowed_units` is the household's after creation, so 0037 widens a row
-- ONLY where its stored list still equals what the OLD rule derived for it —
-- the mirror of ADR-0009 rule 3's "never remove", said in the other
-- direction: never overwrite what somebody stated. `mg` is the exception, and
-- deliberately: a unit that no longer exists is not a curation, so it comes
-- out of every list.
--
-- The rows below are inserted with EXPLICIT lists (the insert trigger would
-- otherwise stamp the post-0037 defaults) and the migration's own guarded
-- statement is re-run over them, scoped to the fixtures. The scope is not
-- cosmetic: run over the whole table it would widen real template rows inside
-- this transaction, hiding what the template looks like from every assertion
-- below and undoing, in a test, the curation the fence exists to protect.
-- ---------------------------------------------------------------------------

-- (a) PRISTINE: a tsp /g row storing exactly what the pre-0037 rule derived
--     (the basis base alone). It stands to gain the rest of its family.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, allowed_units)
values ('cccccccc-0000-0000-0000-000000000014',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Pristine Yeast', 'tsp', 'baking',
  'seed', 'pristine yeast', '["g"]'::jsonb);
-- (b) PRISTINE, the flour shape: a cup /g row with a density, storing the old
--     rule's answer. It gains `fl_oz` from the volume family and `oz`/`lb`
--     from the mass one.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, density_g_per_ml, allowed_units)
values ('cccccccc-0000-0000-0000-000000000015',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Pristine Flour', 'cup', 'baking',
  'seed', 'pristine flour', 0.59,
  '["cup", "tsp", "tbsp", "ml", "l", "pt", "qt", "g", "kg"]'::jsonb);
-- (c) CURATED: the same shape with one word the household added.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, density_g_per_ml, allowed_units)
values ('cccccccc-0000-0000-0000-000000000016',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Curated Flour', 'cup', 'baking',
  'seed', 'curated flour', 0.59,
  '["cup", "tsp", "tbsp", "ml", "l", "pt", "qt", "g", "kg", '
  '"to_taste"]'::jsonb);

-- 0037's widening statement, verbatim in its GUARDS and scoped to the three
-- fixtures. The old rule is computed by the same temporary function the
-- migration used; here it is inlined as the literal answers, because these
-- three rows are the point rather than the function.
update ingredient i
   set allowed_units = i.allowed_units || c.added
  from (
    select i2.id,
           (select coalesce(jsonb_agg(f.u order by f.ord), '[]'::jsonb)
              from jsonb_array_elements_text(d.units)
                   with ordinality as f(u, ord)
             where not (i2.allowed_units ? f.u))
             as added,
           (select array_agg(distinct s.u order by s.u)
              from jsonb_array_elements_text(i2.allowed_units) as s(u))
             as stored,
           (select array_agg(distinct o.u order by o.u)
              from jsonb_array_elements_text(o.old) as o(u))
             as old_default
      from ingredient i2
      cross join lateral (
        select default_allowed_units(i2.default_unit, i2.macros_basis,
                                     i2.density_g_per_ml, i2.category,
                                     i2.piece_basis_amount) as units
      ) d
      cross join lateral (
        select case i2.id
                 when 'cccccccc-0000-0000-0000-000000000014'
                   then '["g"]'::jsonb
                 else '["cup","tsp","tbsp","ml","l","pt","qt","g","kg"]'::jsonb
               end as old
      ) o
     where i2.allowed_units is not null
       and i2.id in ('cccccccc-0000-0000-0000-000000000014',
                     'cccccccc-0000-0000-0000-000000000015',
                     'cccccccc-0000-0000-0000-000000000016')
  ) c
 where c.id = i.id
   and c.added <> '[]'::jsonb
   and c.stored = c.old_default;

select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000014'),
  '["g", "kg", "oz", "lb"]'::jsonb,
  '0037 widens a PRISTINE list to the whole family, appending nothing else'
);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000015'),
  '["cup", "tsp", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "oz", "lb", '
  '"fl_oz"]'::jsonb,
  '0037 gives a pristine flour row fl_oz and the customary weights'
);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000016'),
  '["cup", "tsp", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "to_taste"]'::jsonb,
  '0037 leaves a CURATED list alone — a backfill never overwrites a stated '
  'fact'
);

-- The `mg` strip is NOT under that fence. A curated row carrying `mg` loses
-- it and keeps everything else — the migration's statement, re-run over one
-- fixture that could not exist after it.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, allowed_units)
values ('cccccccc-0000-0000-0000-000000000017',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Curated Supplement', 'g', 'pantry',
  'seed', 'curated supplement', '["g", "mg", "to_taste"]'::jsonb);
update ingredient i
   set allowed_units = (
         select coalesce(jsonb_agg(e.u order by e.ord), '[]'::jsonb)
           from jsonb_array_elements_text(i.allowed_units)
                with ordinality as e(u, ord)
          where e.u <> 'mg')
 where i.id = 'cccccccc-0000-0000-0000-000000000017'
   and i.allowed_units ? 'mg';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000017'),
  '["g", "to_taste"]'::jsonb,
  '0037 strips mg from a CURATED list too: a retired unit is not a curation'
);

-- …and the rule reached the real vocabulary. This is a POPULATION assertion,
-- and it can be stated whole because ADR-0014 admits families rather than
-- units: the template's lists are re-materialized by ONE statement in the
-- generated seed curation (`update ingredient set allowed_units =
-- default_allowed_units(...)`), with the per-row overrides applied after it,
-- so staleness is all-or-nothing. Curation removes single units from single
-- rows; it never removes a whole family from every row.
select is(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null
       and macros_basis = 'g'
       and not (allowed_units ?& array['g', 'kg', 'oz', 'lb'])),
  0,
  'every per-100 g template row says the whole mass family (ADR-0014)'
);
select is(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null
       and allowed_units is not null
       and density_g_per_ml is not null
       and not (allowed_units ? 'fl_oz')),
  0,
  'and every density-carrying row says fl_oz — a unit no earlier rule ever '
  'offered, so a stale rule or a missed re-materialization fails outright'
);

-- ---------------------------------------------------------------------------
-- 0014 / plan 0020 D4: the retired seed produce patch, as an assertion.
--
-- The template vocab used to carry cup/tbsp/ml on 49 piece-default produce
-- rows via an explicit `seed_curation.sql` patch, labelled "until ADR-0008 is
-- amended". ADR-0009 amended it, the patch is gone, and this is the safety
-- net that replaced it: the admissions must now fall out of the rule.
-- ---------------------------------------------------------------------------

select cmp_ok(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null and category = 'produce'
       and default_unit = 'piece' and density_g_per_ml is not null),
  '>', 40,
  'the template still has the piece-default produce rows this guards (~49)'
);
select is(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and deleted_at is null and category = 'produce'
       and default_unit = 'piece' and density_g_per_ml is not null
       and not (allowed_units ? 'cup' and allowed_units ? 'tbsp'
                and allowed_units ? 'ml')),
  0,
  'every piece-default produce row with a density admits cup/tbsp/ml (D4)'
);

-- …and the curated per-row overrides the seed keeps (they are not
-- density-derived and have nowhere else to live) survived the refresh: the
-- backfill unions, it does not re-materialize.
select ok(
  (select allowed_units ? 'tsp' from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text = 'liquid smoke'),
  'a curated ADDITION survives (liquid smoke keeps tsp)'
);
select ok(
  (select not (allowed_units ? 'pinch') and not (allowed_units ? 'handful')
     from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text = 'olive oil'),
  'a curated REMOVAL survives (nobody pinches olive oil)'
);

-- ---------------------------------------------------------------------------
-- ADR-0015: a piece weight is a row fact, and it is what admits `piece`.
--
-- ADR-0010 made this a hand-curated removal per row — 143 lines of
-- `{"remove": ["piece"]}` in seed/curation_overrides.jsonl, one judgment per
-- ingredient, re-decided for every new one. The owner's ruling (2026-09-08)
-- replaces the taste question with an honesty question, the same one the
-- density gate already asks:
--
--   `piece` is admitted iff the row's default unit IS `piece` AND
--   `piece_basis_amount` says what one of them weighs.
--
-- A `piece` you can weigh converts, totals and shops; one you cannot is not
-- offered, and the flesh-out form asks for the number instead. So these
-- assertions changed direction: they used to pin that no seeded row admits
-- `piece`, and they now pin that every COUNTED seeded row does — and that
-- nothing else can.
-- ---------------------------------------------------------------------------

-- The canary. Both guards below are vacuous if this set is empty, and a row
-- that has FLIPPED to a count default is a row that needs a piece weight in
-- curation_overrides.jsonl — so pin the count rather than only the property.
--
-- The number is 76, not the 77 the vocabulary held before this ruling: `mint`
-- moved off a count default because it has no honest whole (a 2 g sprig and a
-- 25 g bunch, 12× apart, and neither is "one mint"). Bumping this number
-- without reading the new row's overrides is how the guard goes quiet.
select is(
  (select count(*)::int from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and default_unit = 'piece'),
  76,
  'the template has 76 piece-default rows (the set the rule is about)'
);

-- (a) Every one of them says what one weighs. Named row by row so a failure
--     says WHICH row is stranded — this is seed_curation.sql's R3a, held
--     again here against the database that actually landed.
select is(
  (select coalesce(string_agg(match_text, ', ' order by match_text), '')
     from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and default_unit = 'piece'
      and piece_basis_amount is null),
  '',
  'every seeded piece-default row carries a piece weight (ADR-0015)'
);

-- …and therefore admits `piece`.
select is(
  (select coalesce(string_agg(match_text, ', ' order by match_text), '')
     from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and default_unit = 'piece'
      and not (allowed_units ? 'piece')),
  '',
  'and every one of them admits `piece` — the seed refresh derives it'
);

-- (b) Nothing else does. The derived rule gives `piece` to a count default
--     alone, and no allowed-unit override adds it back (R3b).
select is(
  (select coalesce(string_agg(match_text || ' (' || default_unit || ')',
                              ', ' order by match_text), '')
     from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and default_unit <> 'piece'
      and allowed_units ? 'piece'),
  '',
  'no seeded row with another default admits `piece` (ADR-0015)'
);

-- The rule read directly, both ways round: the weight is the whole of it.
select ok(
  default_allowed_units('piece', 'g', null, 'produce', 50) ? 'piece'
  and not (default_allowed_units('piece', 'g', null, 'produce', null)
           ? 'piece'),
  'a weighed count row gets `piece`; an unweighed one does not'
);

-- The borrow the migration performs, read off the row it was performed for:
-- the number IS the curated measure's, and the row says where it came from.
select results_eq(
  $$select i.piece_basis_amount::numeric, i.piece_source
      from ingredient i
     where i.household_id = '00000000-0000-0000-0000-0000000000aa'
       and i.match_text = 'onion'$$,
  $$values (110::numeric, 'borrowed from onion, medium')$$,
  'onion counts as its curated 110 g medium, and says so (the borrow)'
);
select is(
  (select count(*)::int from ingredient i
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.deleted_at is null
      and i.piece_source like 'borrowed from %'
      and not exists (
        select 1 from ingredient_measure m
        where m.ingredient_id = i.id and m.deleted_at is null
          and m.basis_amount = i.piece_basis_amount
          and 'borrowed from ' || m.label = i.piece_source)),
  0,
  'every borrowed piece weight matches a live measure of its own row'
);

-- The check constraint: a weightless `one of these` is null, never zero.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text)
values ('cccccccc-0000-0000-0000-000000000021',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Weightless', 'piece', 'produce',
  'manual', 'weightless');
select throws_ok(
  $$ update ingredient set piece_basis_amount = 0
      where id = 'cccccccc-0000-0000-0000-000000000021' $$,
  '23514',
  null,
  'piece_basis_amount rejects zero (0039 check)'
);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000021'),
  '["g", "kg", "oz", "lb", "handful"]'::jsonb,
  'an unweighed count row materializes WITHOUT `piece` (the insert trigger)'
);

-- …and the union trigger, the mirror of the density one: the weight arrives,
-- `piece` joins the list, and the household's own words are kept.
update ingredient set allowed_units = allowed_units || '["to_taste"]'::jsonb
where id = 'cccccccc-0000-0000-0000-000000000021';
update ingredient set piece_basis_amount = 60
where id = 'cccccccc-0000-0000-0000-000000000021';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000021'),
  '["g", "kg", "oz", "lb", "handful", "to_taste", "piece"]'::jsonb,
  'a piece weight arriving unions `piece` and keeps the user''s own list'
);
update ingredient set piece_basis_amount = 65
where id = 'cccccccc-0000-0000-0000-000000000021';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000021'),
  '["g", "kg", "oz", "lb", "handful", "to_taste", "piece"]'::jsonb,
  'and a second weight changes nothing — the union is idempotent'
);

-- 0039's BACKFILL, re-run over a fixture that could not exist after it: a
-- piece-default row carrying the retired `default_measure_id` and no weight
-- yet. The number is COPIED off that measure — a stated fact, never a guess —
-- and the row records where it came from. (In the migration this ran before
-- the trigger above existed and §4 did the union; here the trigger is already
-- in place and does it, which is the same end state by the other door.)
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text)
values ('cccccccc-0000-0000-0000-000000000023',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Backfill Onion', 'piece',
  'produce', 'seed', 'backfill onion');
insert into ingredient_measure (id, household_id, ingredient_id, label,
  basis_amount, sort_order, source)
values ('cccccccc-0000-0000-0000-0000000000b1',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'cccccccc-0000-0000-0000-000000000023', 'onion, medium', 110, 0,
  'seed:typical');
update ingredient set default_measure_id = 'cccccccc-0000-0000-0000-0000000000b1'
where id = 'cccccccc-0000-0000-0000-000000000023';

update ingredient i
   set piece_basis_amount = m.basis_amount,
       piece_source       = 'borrowed from ' || m.label
  from ingredient_measure m
 where m.id = i.default_measure_id
   and m.deleted_at is null
   and i.default_unit = 'piece'
   and i.piece_basis_amount is null
   and i.id = 'cccccccc-0000-0000-0000-000000000023';

select results_eq(
  $$select piece_basis_amount::numeric, piece_source, allowed_units
      from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000023'$$,
  $$values (110::numeric, 'borrowed from onion, medium',
            '["g", "kg", "oz", "lb", "handful", "piece"]'::jsonb)$$,
  '0039 copies the curated measure''s amount onto the row, says so, and the '
  'row then admits `piece`'
);

-- The trigger is gated on the DEFAULT UNIT too: a weight on a row nobody
-- counts admits nothing, whatever the number says.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text)
values ('cccccccc-0000-0000-0000-000000000022',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Trigger Garlic', 'g', 'produce',
  'manual', 'trigger garlic');
update ingredient set piece_basis_amount = 3
where id = 'cccccccc-0000-0000-0000-000000000022';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000022'),
  '["g", "kg", "oz", "lb", "handful"]'::jsonb,
  'a 3 g clove on a gram-default row admits no `piece` (the garlic shape)'
);

-- The board's two import frames, pinned at the data end. Avocado is the
-- single-measure row (one chip, preselected); gold potato is the pick-one row
-- (three chips, nothing preselected).
select is(
  (select count(*)::int from ingredient_measure m
     join ingredient i on i.id = m.ingredient_id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.match_text = 'avocado' and m.deleted_at is null),
  1,
  'avocado carries exactly one measure (the preselect frame)'
);
select is(
  (select count(*)::int from ingredient_measure m
     join ingredient i on i.id = m.ingredient_id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.match_text = 'gold potato' and m.deleted_at is null),
  3,
  'gold potato carries three measures (the small/medium/large pick-one frame)'
);

-- The three measure edits the owner ruled in the same pass.
select is(
  (select m.basis_amount::numeric from ingredient_measure m
     join ingredient i on i.id = m.ingredient_id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.match_text = 'broccoli' and m.label = 'whole'
      and m.deleted_at is null),
  608::numeric,
  'broccoli''s 608 g bunch is relabelled `whole` — a whole broccoli'
);
select ok(
  (select m.source like 'usda_fdc:170379%' from ingredient_measure m
     join ingredient i on i.id = m.ingredient_id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.match_text = 'broccoli' and m.label = 'whole'
      and m.deleted_at is null),
  'the relabel keeps the USDA provenance of the row it replaces'
);
select is_empty(
  $$select 1 from ingredient_measure m
      join ingredient i on i.id = m.ingredient_id
     where i.match_text = 'cherry tomato' and m.deleted_at is null$$,
  'cherry tomato carries no measure at all (the borrowed `cherry` is gone)'
);
-- …and it cannot acquire `piece` by the back door either: it is cup-default,
-- and the derived rule admits `piece` only for a count default — a weight on
-- the row would not change that (ADR-0015).
select is(
  default_allowed_units('cup', 'g', 0.6298, 'produce', 20) ? 'piece',
  false,
  'a volume-default row is never admitted `piece`, weight or no weight'
);
select results_eq(
  $$select m.label, m.basis_amount::numeric, m.source
      from ingredient_measure m
      join ingredient i on i.id = m.ingredient_id
     where i.household_id = '00000000-0000-0000-0000-0000000000aa'
       and i.match_text = 'ginger' and m.deleted_at is null
     order by m.sort_order$$,
  $$values ('slice', 2.2::numeric, 'usda_fdc:169231 (5 slices (1" dia))'),
           ('piece, 1 inch', 12::numeric, 'seed:typical')$$,
  'ginger keeps `slice` and gains the owner-asked `piece, 1 inch` (12 g)'
);

-- The density note attached to the same ruling: basil, thai basil and cherry
-- tomato are measured by the spoon and the cup, so the tsp↔g chips have to
-- exist. Those chips are a DENSITY, not a measure (ADR-0008 §2) — assert the
-- USDA rows carry one, and macros, rather than curating a guessed number.
select results_eq(
  $$select match_text, density_g_per_ml::numeric, status,
           (macros is not null)
      from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text in ('basil', 'thai basil', 'cherry tomato')
     order by match_text$$,
  $$values ('basil', 0.1014::numeric, 'complete', true),
           ('cherry tomato', 0.6298::numeric, 'complete', true),
           ('thai basil', 0.1014::numeric, 'complete', true)$$,
  'basil / thai basil / cherry tomato carry a USDA density AND macros'
);

-- ---------------------------------------------------------------------------
-- The USDA search door.
--
-- Two private reference rows so the vectors do not depend on which FDC foods
-- the seed happens to carry, and one household row for the "it writes
-- nothing" pair below. `usda_food` is server-only (ADR-0005), and so is the
-- BM25 index derived from it; `usda_probe` is SECURITY DEFINER precisely so
-- an `authenticated` caller — who has no grant on either — still gets an
-- answer.
--
-- Nothing prefills any more: the insert/rename trigger that used to copy a
-- USDA row onto a stub was dropped, and `usda_search.sql` pins that it stays
-- dropped. A pick is a human action through this door.
-- ---------------------------------------------------------------------------

insert into usda_food (fdc_id, description, category, density_g_per_ml,
  macros, match_text)
values (999000001, 'Zzquux Test Reference Food', 'produce', 0.75,
  '{"kcal": 100, "protein": 2, "carb": 20, "fat": 1}'::jsonb,
  'zzquux test reference food'),
  -- A near miss of the first, so the total order is observable.
  (999000002, 'Zzquux Test Reference Food Two', 'produce', 0.5,
  '{"kcal": 50, "protein": 1, "carb": 10, "fat": 1}'::jsonb,
  'zzquux test reference food two');

-- The index is DERIVED: an insert into usda_food is invisible to the probe
-- until it is rebuilt. Rebuilding is a truncate + re-scan of the whole
-- reference set and costs a second here, which is cheaper than a test that
-- silently ranks against a corpus missing its own fixtures.
select usda_rebuild_search_index();

insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text, macros)
values ('cccccccc-0000-0000-0000-000000000009',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Qqfoo Fleshed Out', 'g',
  'stub', 'manual', 'qqfoo fleshed out', '{"kcal": 7}'::jsonb);

-- ---------------------------------------------------------------------------
-- 0016 / 0027 / 0029: the probe exposed as an RPC.
--
-- `probe_usda` is the only door a client has onto the reference set. It reads,
-- ranks and returns; it writes nothing, and a human applies whatever it
-- offers.
-- ---------------------------------------------------------------------------

-- 0027 widened both signatures with a limit (default 1): the one-argument
-- forms are gone, so a PostgREST call can never be ambiguous between two
-- overloads.
select has_function('probe_usda', array['text', 'integer'],
  'probe_usda(text, int) exists — the D7b client door, with a limit (0027)');
select hasnt_function('probe_usda', array['text'],
  'the one-argument probe_usda is gone — no overload ambiguity');
select has_function('usda_probe', array['text', 'integer'],
  'usda_probe(text, int) exists — the shared probe both callers read');
select hasnt_function('usda_probe', array['text'],
  'the one-argument usda_probe is gone');

-- SECURITY DEFINER with a pinned search_path: these read a table no client
-- role is granted, so definer rights are the point and an unpinned search_path
-- would be the hole. Two functions, not three — `ingredient_prefill_from_usda`
-- was dropped with the silent prefill, and naming it here covered nothing
-- while reading as though it did.
select ok(
  (select bool_and(p.prosecdef) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('probe_usda', 'usda_probe')),
  'the probe and its RPC are both SECURITY DEFINER'
);
select ok(
  (select bool_and(p.proconfig::text like '%search_path=public, extensions%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('probe_usda', 'usda_probe')),
  'both pin search_path to public, extensions (definer hygiene)'
);

-- The grant shape: authenticated reaches the RPC and NOTHING else. anon
-- reaches neither, and the reference table stays ungranted (ADR-0005).
select ok(
  has_function_privilege('authenticated', 'probe_usda(text, int)', 'execute'),
  'authenticated may call probe_usda — the D7b door is open'
);
select ok(
  not has_function_privilege('anon', 'probe_usda(text, int)', 'execute'),
  'anon may not: enrichment is for a signed-in household'
);
select ok(
  not has_function_privilege('authenticated', 'usda_probe(text, int)', 'execute'),
  'authenticated may NOT call the helper directly — one door, not two'
);
select ok(
  not has_table_privilege('authenticated', 'usda_food', 'select'),
  'and usda_food itself is still unreachable (ADR-0005 unmoved by D7b)'
);

-- It returns the best-ranked candidate whole: the row a person would pick,
-- with the source stamp the form writes onto the ingredient if they do.
select is(
  (select fdc_id from probe_usda('zzquux test reference food')),
  999000001,
  'probe_usda returns the best-ranked candidate'
);
select is(
  (select macros ->> 'kcal' from probe_usda('zzquux test reference food')),
  '100',
  'with its macros'
);
select is(
  (select density_g_per_ml from probe_usda('zzquux test reference food')),
  0.75::numeric,
  'and its density'
);
select is(
  (select source from probe_usda('zzquux test reference food')),
  'usda_fdc:999000001',
  'and the source stamp a pick would carry — one formatter, not two'
);
select is(
  (select description from probe_usda('zzquux test reference food')),
  'Zzquux Test Reference Food',
  'probe_usda names its candidate (0027 U-D1)'
);
select is(
  (select category from probe_usda('zzquux test reference food')),
  'produce',
  'and gives its category'
);
select is(
  (select count(*) from probe_usda('zzquux test reference food')),
  1::bigint,
  'the default limit is still ONE — every existing caller unchanged'
);

-- With a limit it lists, in one total order (rank_score desc, fdc_id asc): the
-- exact hit, then the near miss that shares its words but carries one more.
select is(
  (select array_agg(fdc_id order by ord)
     from probe_usda('zzquux test reference food', 2)
     with ordinality as p(fdc_id, description, category, density_g_per_ml,
       macros, score, source, ord)),
  array[999000001, 999000002],
  'a listed probe is ordered: the exact hit, then the near miss (U-D3)'
);
select ok(
  (select bool_and(score = 1.0) from probe_usda(
     'zzquux test reference food', 2)),
  'both cover every word of the query, so both report a score of 1'
);
select is(
  (select count(*) from probe_usda('zzquux test reference food', 3)),
  3::bigint,
  'the cap is honoured exactly — there is no floor withholding rows below it'
);
select ok(
  (select min(score) < 0.5 from probe_usda(
     'zzquux test reference food', 3)),
  'and the third row is a weak one: the ranker offers what it has and lets '
  'the person judge (0029 — no floor)'
);
select is(
  (select fdc_id from probe_usda('zzquux test reference food', 0)),
  999000001,
  'a limit of zero reads as one, not as nothing'
);

-- A query whose words the reference set has never seen matches nothing at
-- all — the empty sheet is "no such food", not "everything is weak".
select is_empty(
  $$ select * from probe_usda('qqfoo qqzzxyw') $$,
  'a query of unknown words returns nothing'
);
select is_empty(
  $$ select * from probe_usda('') $$,
  'and an empty name probes nothing rather than scanning the reference set'
);

-- It WRITES NOTHING. Calling it leaves both the reference set and the
-- household vocabulary exactly as they were.
select is(
  (select count(*) from usda_food),
  (select count(*) from (select * from usda_food) u
    where (select count(*) from probe_usda('zzquux test reference food')) >= 0),
  'probe_usda writes nothing to usda_food'
);
select is(
  (select updated_at from ingredient
    where id = 'cccccccc-0000-0000-0000-000000000009'),
  (select updated_at from ingredient
    where id = 'cccccccc-0000-0000-0000-000000000009'
      and (select count(*) from probe_usda('qqfoo fleshed out')) >= 0),
  'and nothing to ingredient — it is a read, not a prefill'
);

-- ---------------------------------------------------------------------------
-- Basis-aware measures (0012): grams is gone; basis_amount is guarded.
-- ---------------------------------------------------------------------------

select has_column('ingredient_measure', 'basis_amount',
  'ingredient_measure carries basis_amount');
select hasnt_column('ingredient_measure', 'grams',
  'the old grams column is dropped (renamed via new column)');

select throws_ok(
  $$ insert into ingredient_measure (household_id, ingredient_id, label,
       basis_amount)
     values ('cccccccc-cccc-cccc-cccc-cccccccccccc',
       'cccccccc-0000-0000-0000-000000000001', 'bad glug', 0) $$,
  '23514',
  null,
  'basis_amount rejects non-positive amounts (0012 check)'
);

-- 0028: no admission list is a jsonb STRING any more — the connector decodes
-- `allowed_units` before upload and the migration re-typed what was stored.
select is(
  (select count(*)::int from ingredient
     where jsonb_typeof(allowed_units) = 'string'),
  0,
  'no ingredient carries allowed_units as a jsonb string (0028 repair)'
);

select * from finish();
rollback;
