-- pgTAP: the ADR-0008 unit-admission schema (migration 0012) as amended by
-- ADR-0009 (0014) and brought to parity with the app by 0021 (plan 0020
-- D4c + J3 — the basis-strict mates leg, the derived density unlock, the
-- per-word imprecise gate), plus 0014's two ingredient triggers.
--
-- `default_allowed_units()` / `density_unlocked_units()` are the SQL mirrors
-- of the app's derived rule (`defaultAllowedUnitSet` / `densityUnlockedUnits`
-- / `kImpreciseCategoryGates` in allowed_units.dart). The named shapes — the
-- yeast, the flour, the mango, the rest — are no longer written out twice:
-- they live in `app/test/features/ingredients/allowed_units_vectors.json`,
-- which the Dart suite loops and which `seed/scripts/gen_admission_vectors.ts`
-- renders as the GENERATED block below. Editing the JSON without regenerating
-- fails that script's own Deno test, so the two mirrors cannot drift apart
-- quietly. The remaining vectors here are hand-written because they are the
-- SQL side's business alone — each names the Dart test it twins, where there
-- is one. The Dart side is the source of truth; a stored list is a SET, so
-- where Dart asserts a display ORDER (`allowedUnitsFor` runs `_orderUnits`)
-- the jsonb here is pinned in the function's emission order instead, and the
-- members are what is compared.
--
-- Also pins: the BEFORE INSERT trigger that materializes the list, that an
-- explicit list is never overridden, that the 0014 backfill/seed refresh
-- UNIONED rather than re-materialized (curated removals survive, curated
-- additions survive), that the retired seed-level produce patch's admissions
-- now fall out of the rule (plan 0020 D4 — this assertion IS the safety net
-- that replaced the patch), the density→allowed_units union trigger (including
-- the flour shape 0021 exists for), 0021's backfill post-state, the USDA
-- search door (`probe_usda` — read-only, ranked, no floor), the basis_amount
-- rename + positivity check, and that `grams` is gone.
--
-- Plan 0022 / ADR-0010 adds the `piece` curation guard: no seeded ingredient
-- that carries a measure admits `piece`, while every measure-less count row
-- still does. That pass is DATA (curation_overrides.jsonl), not a rule — so
-- the assertion here is the only thing standing between a regenerated seed
-- and a silently restored `piece`.
--
-- Plan 0025 / 0024 adds pint and quart under D2b — quart rides with litre,
-- pint rides with cup — so every vector whose mates name `l` or `cup` grew
-- `qt` / `pt`, and a block at the end pins the rule directly plus the
-- additive backfill's post-state.
--
-- Plan 0036 / ADR-0012 (0032) makes the volume ladder symmetric — `cup` mates
-- `tsp` — so every cup-default vector grew `tsp`. The block after 0024's pins
-- the rule and, more importantly, 0032's WIDENING FENCE, on rows it inserts
-- for the purpose: a pristine list gains `tsp`, a curated one is left exactly
-- as the household left it. What it deliberately does NOT assert is a per-row
-- property of the template vocabulary — curation is allowed to remove `tsp`
-- from a cup-default row and does, and the result is byte-identical to a row
-- a widening never reached. That block's closing comment says what is
-- checkable instead, and why.
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
select plan(111);

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
      default_allowed_units(v.default_unit, v.basis, v.density, v.category)
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
    'baking'::text,
    '["g"]'::jsonb,
    'a spoon default with no density admits the basis base and nothing else — being sold by the spoon does not make spoons convertible'
  ),
  (
    'flour',
    'cup',
    'g',
    0.59,
    'baking',
    '["cup","tsp","tbsp","ml","l","pt","qt","g","kg"]',
    'a cup default with a density earns the kitchen volumes — tsp included, since ADR-0012 made the ladder symmetric — AND kg, because cup-scale justifies the big metric sibling'
  ),
  (
    'olive-oil',
    'tbsp',
    'g',
    0.91,
    'fats & oils',
    '["tbsp","tsp","cup","ml","pt","g","pinch","dash","to_taste"]',
    'a spoon default with a density: its mates, the basis base, and the oil class''s imprecise words — nobody takes a handful of oil'
  ),
  (
    'egg',
    'piece',
    'g',
    null,
    'produce',
    '["piece","g","handful"]',
    'a count default with no density: its own piece, the basis base, and the one imprecise word produce earns'
  ),
  (
    'salt',
    'tsp',
    'g',
    null,
    'spices & seasoning',
    '["g","pinch","dash","handful","to_taste"]',
    'the seasoning category admits the whole imprecise tail, and the spoons still need a density like everyone else''s'
  ),
  (
    'mango',
    'piece',
    'g',
    0.66,
    'produce',
    '["piece","g","tsp","tbsp","cup","ml","pt","handful"]',
    'a count default WITH a density admits the volume workhorses — "1 cup diced mango" is a real line — but not the big metric siblings'
  ),
  (
    'avocado',
    'piece',
    'g',
    0.634,
    'produce',
    '["piece","g","tsp","tbsp","cup","ml","pt","handful"]',
    'the same rule under the row ADR-0010''s curation pass trims: the DERIVED list still offers piece, which is exactly what a curated list then takes away'
  ),
  (
    'broth',
    'cup',
    'ml',
    null,
    'pantry',
    '["cup","tsp","tbsp","ml","l","pt","qt"]',
    'a per-ml row''s volume default IS its basis family, so it stands alone — the whole volume ladder down to tsp, and no gram leg until a density arrives'
  ),
  (
    'milk',
    'cup',
    'ml',
    1.03,
    'dairy',
    '["cup","tsp","tbsp","ml","l","pt","qt","g","kg"]',
    'the same per-ml row once it has a density: mass unlocks behind the basis family'
  )
) as v(shape, default_unit, basis, density, category, expect, why);
-- <<< GENERATED

-- The yeast shape read the other way: a density is what buys the spoons back.
select is(
  default_allowed_units('tsp', 'g', 0.4, 'baking'),
  '["tsp", "tbsp", "g"]'::jsonb,
  'tsp default /g with density: the spoons come back'
);

-- The olive-oil shape's refusal — the per-word category gate, which the
-- vector's admitted list cannot state.
select ok(
  not (default_allowed_units('tbsp', 'g', 0.91, 'fats & oils') ? 'handful'),
  'J3: nobody takes a handful of oil'
);

-- Dart: 'an imprecise default keeps its whole tail + the basis base'.
select is(
  default_allowed_units('pinch', 'g', null, 'spices & seasoning'),
  '["g", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'an imprecise default yields basis base + the imprecise tail'
);

-- Dart: 'a mass default /g with density unlocks kitchen volume'. Oats: grams
-- AND cups are both honest; no piece.
select is(
  default_allowed_units('g', 'g', 0.4, null),
  '["g", "kg", "tsp", "tbsp", "cup", "pt", "ml"]'::jsonb,
  'g default /g with density: own family + the volume workhorses, no piece'
);

-- The same amendment from the per-ml side (an SQL-only extra): a
-- count-default liquid-ish row unlocks the MASS workhorses, and the basis
-- leg's ml is not duplicated.
select is(
  default_allowed_units('piece', 'ml', 1.0, 'dairy'),
  '["piece", "ml", "tsp", "tbsp", "cup", "pt", "g"]'::jsonb,
  'count default /ml with density: mass unlocks, basis ml not duplicated'
);

-- Dart: 'an imprecise default with a density unlocks both families too, and
-- keeps its whole tail INCLUDING handful'.
select is(
  default_allowed_units('pinch', 'g', 1, 'spices & seasoning'),
  '["g", "tsp", "tbsp", "cup", "pt", "ml", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'imprecise default with density: both families unlock, whole tail kept'
);

-- Dart: 'mg and fl oz stay label-reading units: offered only as the default
-- itself, never as anyone else''s mate'. `mg` is mass on a per-g row — its
-- own family, so D4c admits it bare; `fl_oz` is volume and needs the density
-- like every other cross-family default.
select ok(
  default_allowed_units('mg', 'g', null, null) ? 'mg',
  'mg is admitted as its own default (basis family, no density needed)'
);
select ok(
  default_allowed_units('fl_oz', 'g', 1, null) ? 'fl_oz',
  'fl_oz is admitted as its own default once a density bridges it'
);
select is(
  (select count(*)::int
     from unnest(array['g','kg','oz','lb','ml','l','tsp','tbsp','cup',
                       'pt','qt',
                       'piece','pinch','dash','handful','to_taste']) as d(unit)
    where default_allowed_units(d.unit, 'g', 1, null) ? 'mg'
       or default_allowed_units(d.unit, 'g', 1, null) ? 'fl_oz'),
  0,
  'no other default ever admits mg or fl_oz as a mate'
);

-- Dart: 'D4c: the default unit is admitted when its family is — and a row
-- whose default falls outside says so rather than smuggling it in'. Over
-- every ingredient unit (kIngredientUnits — `batch` is deliberately absent):
-- with a density every default is sayable; without one, exactly the
-- cross-family (volume, on a per-g row) defaults are stranded. The
-- `defaultUnitNeedsDensity` / `unitSayableAsDefault` / `basisDefaultUnitFix`
-- halves of that Dart test are app-side read rules with no SQL leg.
select is(
  (select count(*)::int
     from (values ('g'), ('kg'), ('mg'), ('oz'), ('lb'),
                  ('ml'), ('l'), ('tsp'), ('tbsp'), ('fl_oz'), ('cup'),
                  ('pt'), ('qt'),
                  ('piece'), ('pinch'), ('dash'), ('handful'), ('to_taste'))
          as u(unit)
    where not (default_allowed_units(u.unit, 'g', 1, null) ? u.unit)),
  0,
  'D4c: with a density every default unit is sayable'
);
select is(
  (select count(*)::int
     from (values ('g', 'mass'), ('kg', 'mass'), ('mg', 'mass'),
                  ('oz', 'mass'), ('lb', 'mass'),
                  ('ml', 'volume'), ('l', 'volume'), ('tsp', 'volume'),
                  ('tbsp', 'volume'), ('fl_oz', 'volume'), ('cup', 'volume'),
                  ('pt', 'volume'), ('qt', 'volume'),
                  ('piece', 'count'), ('pinch', 'imprecise'),
                  ('dash', 'imprecise'), ('handful', 'imprecise'),
                  ('to_taste', 'imprecise'))
          as u(unit, family)
    where (default_allowed_units(u.unit, 'g', null, null) ? u.unit)
          <> (u.family <> 'volume')),
  0,
  'D4c: without one, exactly the cross-family defaults are stranded'
);

-- ---------------------------------------------------------------------------
-- The per-word imprecise gate (J3) — mirrors allowed_units_test.dart group
-- 'impreciseUnitsFor — the per-word category gate'. Read through
-- default_allowed_units() on a g-default per-g row, whose only other
-- admissions are its own ["g","kg"].
-- ---------------------------------------------------------------------------

-- Dart: 'the whole mapping, category by category'. Owner ruling: pinch and
-- dash belong to the spice/seasoning/oil classes; handful belongs to greens,
-- which `produce` is the nearest category the vocabulary can express.
select is(
  default_allowed_units('g', 'g', null, 'spices & seasoning'),
  '["g", "kg", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'spices & seasoning earns all four words'
);
select is(
  default_allowed_units('g', 'g', null, 'fats & oils'),
  '["g", "kg", "pinch", "dash", "to_taste"]'::jsonb,
  'fats & oils earns pinch/dash/to_taste — no handful'
);
select is(
  default_allowed_units('g', 'g', null, 'produce'),
  '["g", "kg", "handful"]'::jsonb,
  'produce earns handful and nothing else'
);
select is(
  (select count(*)::int
     from unnest(array['pantry','grains','baking','dairy','proteins']) as c(cat)
    where default_allowed_units('g', 'g', null, c.cat) <> '["g", "kg"]'::jsonb),
  0,
  'pantry / grains / baking / dairy / proteins earn no imprecise word'
);
-- An uncategorised row earns nothing — the gate is a fact about the
-- category, so no category is no licence.
select is(
  default_allowed_units('g', 'g', null, null),
  '["g", "kg"]'::jsonb,
  'a null category earns no imprecise word'
);
select is(
  default_allowed_units('g', 'g', null, ''),
  '["g", "kg"]'::jsonb,
  'an empty category earns no imprecise word'
);

-- Dart: 'THE KALE VECTOR: greens take a handful, never a pinch or a dash'.
-- Under 0014's whole-set gate a server-materialized kale row could name
-- `dash`; the app offered only `handful`.
select is(
  default_allowed_units('cup', 'g', 0.2, 'produce'),
  '["cup", "tsp", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "handful"]'::jsonb,
  'kale (cup /g, density, produce): a handful, never a pinch or a dash'
);

-- Dart: 'a row whose DEFAULT unit is imprecise can always say it, whatever
-- its category'.
select is(
  default_allowed_units('pinch', 'g', null, 'produce'),
  '["g", "pinch", "handful"]'::jsonb,
  'a pinch-default produce row keeps pinch (its own word) + handful'
);
select is(
  default_allowed_units('dash', 'g', null, 'grains'),
  '["g", "dash"]'::jsonb,
  'a dash-default grains row keeps dash though the category earns nothing'
);

-- Dart: 'the category is matched case- and whitespace-insensitively'.
select is(
  default_allowed_units('g', 'g', null, '  Produce '),
  '["g", "kg", "handful"]'::jsonb,
  'the category gate trims and case-folds (  Produce  → handful)'
);
select is(
  jsonb_array_length(default_allowed_units('g', 'g', null, 'Spices & Seasoning')),
  6,
  'Spices & Seasoning matches the lower-case key (g, kg + four words)'
);

-- ---------------------------------------------------------------------------
-- density_unlocked_units(default, basis) — what a density buys a row, derived
-- as derived(with) − derived(without) (0021). Mirrors `densityUnlockedUnits`
-- / `densityStrippedUnits` in allowed_units.dart (group 'densityStrippedUnits
-- — what deleting a density takes back'), and is what the 0014 trigger and
-- the 0021 backfill union in, so it gets its own vectors.
-- ---------------------------------------------------------------------------

-- Dart: 'the mango shape: the volume leg goes, piece and the basis base stay'.
select is(
  density_unlocked_units('piece', 'g'), array['tsp','tbsp','cup','pt','ml'],
  'a piece /g default: the density buys the volume workhorses (the mango shape)'
);
-- Dart: 'THE FLOUR SHAPE, under D4c: the volume family goes — including the
-- row''s own default unit, which the density was the only thing admitting'.
-- 0014's one-argument leg returned ["g","kg"] here — already admitted by the
-- basis leg — which is the bug 0021 exists for.
select is(
  density_unlocked_units('cup', 'g'), array['cup','tsp','tbsp','ml','l','pt','qt'],
  'a cup /g default: the density buys the volume family, own default included (the flour shape)'
);
-- Dart: 'the milk shape: a per-ml row loses g, keeps every volume unit'.
select is(
  density_unlocked_units('ml', 'ml'), array['g'],
  'an ml /ml default: the density buys g only (the milk shape)'
);
select is(
  density_unlocked_units('g', 'g'), array['tsp','tbsp','cup','pt','ml'],
  'a mass default unlocks the volume workhorses'
);
select is(
  density_unlocked_units('tbsp', 'g'), array['tbsp','tsp','cup','ml','pt'],
  'a spoon-scale volume default /g: the density buys its own spoons back (no kilos of tbsp)'
);
select is(
  density_unlocked_units('cup', 'ml'), array['g','kg'],
  'a cup-scale volume default on its own basis also justifies kg'
);
select is(
  density_unlocked_units('piece', 'ml'), array['tsp','tbsp','cup','pt','g'],
  'a count default /ml unlocks the volume workhorses AND g — never the basis ml'
);
select is(
  density_unlocked_units('pinch', 'g'), array['tsp','tbsp','cup','pt','ml'],
  'an imprecise default unlocks both families too, minus the basis leg (ADR-0009)'
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
         from jsonb_array_elements_text(default_allowed_units(s.d, s.b, 1, s.c))
              as w(unit)
        where not (w.unit = any(density_unlocked_units(s.d, s.b))))
        @> default_allowed_units(s.d, s.b, null, s.c)
      and default_allowed_units(s.d, s.b, null, s.c) @>
      (select coalesce(jsonb_agg(w.unit), '[]'::jsonb)
         from jsonb_array_elements_text(default_allowed_units(s.d, s.b, 1, s.c))
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
  '["g"]'::jsonb,
  'inserting without allowed_units materializes the ADR defaults (basis-strict since 0021)'
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
-- on a baking row) and one the defaults WOULD give it once a density lands
-- removed ('tbsp'). The density unions its own spoons back and keeps the
-- user's list.
update ingredient set allowed_units = '["tsp", "to_taste"]'::jsonb
where id = 'cccccccc-0000-0000-0000-000000000001';

update ingredient set density_g_per_ml = 0.55
where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000001'),
  '["tsp", "to_taste", "tbsp"]'::jsonb,
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
  '["tsp", "to_taste", "tbsp"]'::jsonb,
  'an unchanged density and an unrelated edit both leave the list alone'
);

-- THE FLOUR SHAPE, server-side — the tracker row 0021 retires. A cup-default
-- per-100 g row whose list a D4b `clearDensity` stripped to the basis family
-- (the app's own honest write). When a density then lands SERVER-side, 0014's
-- leg unioned ["g","kg"] — already there — and `cup`, the row's own default,
-- stayed out of its stored list. Since 0021 the trigger unions the volume
-- family the density actually buys.
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
  '["g", "kg", "cup", "tsp", "tbsp", "ml", "l", "pt", "qt"]'::jsonb,
  'a density landing on a stripped cup /g row restores its own default''s family (the flour shape)'
);

-- …and from the per-ml side: a materialized ml-default per-ml row gains g,
-- and only g, when its density lands.
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
  '["ml", "l", "tsp", "tbsp", "cup", "pt", "qt", "g"]'::jsonb,
  'a density landing on an ml /ml row unions g and nothing else (the milk shape)'
);

-- 0021's backfill post-state, as an invariant over the whole table: no row
-- that carries a density and a mass/volume default is missing that default
-- from its own list. The backfill repaired exactly this shape and nothing
-- else; the trigger above keeps it true from here on.
select is(
  (select count(*)::int from ingredient
     where density_g_per_ml is not null
       and allowed_units is not null
       and default_unit in ('g','kg','mg','oz','lb',
                            'ml','l','tsp','tbsp','fl_oz','cup','pt','qt')
       and not (allowed_units ? default_unit)),
  0,
  'no density-carrying mass/volume row lacks its own default unit (0021 backfill)'
);

-- ---------------------------------------------------------------------------
-- 0024 / plan 0025 D2b: pint and quart. Quart rides with litre, pint rides
-- with cup — wherever a default's mates name `l` they name `qt`, wherever
-- they name `cup` they name `pt`; the pair as defaults mate one rung each
-- side; both join the `big` gate. Mirrors allowed_units_test.dart group
-- 'pint and quart (plan 0025 D2b)'.
-- ---------------------------------------------------------------------------

-- Dart: 'the broth shape: a cup default admits a pint, and a quart with it'.
select ok(
  default_allowed_units('cup', 'ml', null, 'pantry') ? 'pt'
  and default_allowed_units('cup', 'ml', null, 'pantry') ? 'qt',
  'a cup-default row admits pt (rides with cup) and qt (rides with l)'
);
-- Dart: 'a litre default admits a quart'.
select is(
  default_allowed_units('l', 'ml', null, null),
  '["l", "ml", "cup", "pt", "qt"]'::jsonb,
  'an l-default row admits qt — and pt, since its mates name cup'
);
-- Dart: 'a spoon default admits neither — no quarts of yeast'.
select ok(
  not (default_allowed_units('tsp', 'ml', null, null) ? 'pt')
  and not (default_allowed_units('tsp', 'ml', null, null) ? 'qt')
  and not (default_allowed_units('tsp', 'g', 0.4, null) ? 'pt')
  and not (default_allowed_units('tsp', 'g', 0.4, null) ? 'qt'),
  'a tsp-default row admits neither pt nor qt, density or not'
);
-- Dart: 'the pair as defaults'. qt mates one rung each side and, being
-- litre-scale, passes the big gate on the basis leg; pt likewise at cup
-- scale.
select is(
  default_allowed_units('qt', 'ml', null, null),
  '["qt", "pt", "cup", "l", "ml"]'::jsonb,
  'a qt default /ml: its own mates, one rung each side'
);
select is(
  default_allowed_units('pt', 'g', 1.0, null),
  '["pt", "cup", "qt", "ml", "g", "kg"]'::jsonb,
  'a pt default /g with density: mates + g AND kg (pint is cup-scale, so big)'
);
select is(
  default_allowed_units('pt', 'g', null, null),
  '["g", "kg"]'::jsonb,
  'a pt default /g without density: stranded like any cross-family default (D4c)'
);
-- The density cross leg names cup, so it names pt; it never named l, so a
-- density buys a gram row no quart.
select ok(
  'pt' = any(density_unlocked_units('g', 'g'))
  and not ('qt' = any(density_unlocked_units('g', 'g'))),
  'a density buys a mass row pt but not qt (the cross leg names cup, not l)'
);

-- The 0024 backfill's post-state, as an invariant over the whole table: no
-- stored list that names `l` and whose recomputed defaults admit `qt` lacks
-- `qt`; same for `cup` and `pt`. True of the template after a reset (the seed
-- re-materializes) and of a migrated database (the backfill unions) alike.
select is(
  (select count(*)::int from ingredient i
     where i.allowed_units is not null
       and (   (i.allowed_units ? 'l' and not (i.allowed_units ? 'qt')
                and default_allowed_units(i.default_unit, i.macros_basis,
                                          i.density_g_per_ml, i.category) ? 'qt')
            or (i.allowed_units ? 'cup' and not (i.allowed_units ? 'pt')
                and default_allowed_units(i.default_unit, i.macros_basis,
                                          i.density_g_per_ml, i.category) ? 'pt'))),
  0,
  'every row that says l/cup and whose rule admits qt/pt says qt/pt (0024 backfill)'
);
-- …reaching the row the plan was about: "1 quart broth" lands on a chip.
select ok(
  (select allowed_units ? 'qt' and allowed_units ? 'pt' and allowed_units ? 'cup'
     from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and match_text = 'vegetable broth'),
  'vegetable broth (cup default) admits qt and pt beside its cup'
);
-- …and the union is what the migration does to a list it did not write: a
-- hand-edited row that says cup keeps its curated word and gains only the
-- pair, exactly as the backfill statement would leave it.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, macros_basis, density_g_per_ml, allowed_units)
values ('cccccccc-0000-0000-0000-00000000000c',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Curated Stock', 'cup', 'pantry',
  'manual', 'curated stock', 'ml', 1.0, '["cup", "ml", "to_taste"]'::jsonb);
update ingredient i
   set allowed_units = i.allowed_units || (
         select coalesce(jsonb_agg(n.unit order by n.ord), '[]'::jsonb)
           from jsonb_array_elements_text(
                  default_allowed_units(i.default_unit, i.macros_basis,
                                        i.density_g_per_ml, i.category))
                with ordinality as n(unit, ord)
          where (   (n.unit = 'qt' and i.allowed_units ? 'l')
                 or (n.unit = 'pt' and i.allowed_units ? 'cup'))
            and not (i.allowed_units ? n.unit))
 where i.id = 'cccccccc-0000-0000-0000-00000000000c';
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-00000000000c'),
  '["cup", "ml", "to_taste", "pt"]'::jsonb,
  'the backfill shape: a curated list that says cup (not l) gains pt only, keeps to_taste'
);

-- ---------------------------------------------------------------------------
-- 0032 / ADR-0012: the volume ladder is symmetric — `cup` mates `tsp`.
--
-- The rule change is one array entry; the interesting half is the widening
-- backfill's fence. `allowed_units` is the household's after creation, so
-- 0032 adds `tsp` ONLY where the stored list still equals the OLD derived
-- default for that row — the mirror of ADR-0009 rule 3's "never remove",
-- said in the other direction: never overwrite what somebody stated.
--
-- The three rows below are inserted with EXPLICIT lists (the insert trigger
-- would otherwise stamp the post-0032 defaults) and the migration's own
-- guarded statement is re-run over them, which is what makes these
-- assertions about the migration rather than about the function.
-- ---------------------------------------------------------------------------

-- Dart: 'ADR-0012: a cup default mates tsp, in both directions'.
select ok(
  default_allowed_units('cup', 'g', 0.59, 'baking') ? 'tsp'
  and default_allowed_units('cup', 'ml', null, 'pantry') ? 'tsp',
  'a cup-default row admits tsp — with a density, and on its own basis'
);
-- …and the trim in the other direction is untouched: a spoon-default row is
-- still not a cup-scale food.
select ok(
  not (default_allowed_units('tsp', 'ml', null, null) ? 'l')
  and not (default_allowed_units('tsp', 'ml', null, null) ? 'cup'),
  'tsp''s own mates are unchanged — no cups or litres of yeast'
);

-- (a) PRISTINE: the stored list is exactly what the pre-0032 rule derived.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, density_g_per_ml, allowed_units)
values ('cccccccc-0000-0000-0000-00000000000d',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Pristine Sugar', 'cup', 'baking',
  'seed', 'pristine sugar', 0.85,
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg"]'::jsonb);
-- (b) CURATED: the same shape with one word the household added.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, density_g_per_ml, allowed_units)
values ('cccccccc-0000-0000-0000-00000000000e',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Curated Sugar', 'cup', 'baking',
  'seed', 'curated sugar', 0.85,
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "to_taste"]'::jsonb);
-- (c) OUT OF SHAPE: a cup default whose rule admits no volume unit at all
--     (per-100 g, no density — D4c), so there is nothing to widen.
insert into ingredient (id, household_id, canonical_name, default_unit,
  category, source, match_text, allowed_units)
values ('cccccccc-0000-0000-0000-00000000000f',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Stranded Rice', 'cup', 'pantry',
  'seed', 'stranded rice', '["g", "kg"]'::jsonb);

-- 0032's statement, verbatim in its GUARDS and scoped to the three fixtures.
--
-- The scope is deliberate and it is not cosmetic. Run over the whole table
-- this widens real template rows — the curated ones whose stored list happens
-- to equal the rule minus `tsp` — inside this transaction, which both hides
-- what the template actually looks like from every assertion below it and
-- undoes, in a test, the curation the fence exists to protect. The guards are
-- what is under test here; the table scope is not.
update ingredient i
   set allowed_units = i.allowed_units || '["tsp"]'::jsonb
  from (
    select i2.id,
           (select array_agg(distinct s.u order by s.u)
              from jsonb_array_elements_text(i2.allowed_units) as s(u))
             as stored,
           (select array_agg(distinct f.u order by f.u)
              from jsonb_array_elements_text(d.units) as f(u)
             where f.u <> 'tsp')
             as old_default,
           d.units as fresh
      from ingredient i2
      cross join lateral (
        select default_allowed_units(i2.default_unit, i2.macros_basis,
                                     i2.density_g_per_ml, i2.category) as units
      ) d
     where i2.allowed_units is not null
       and i2.default_unit = 'cup'
       and not (i2.allowed_units ? 'tsp')
       and i2.id in ('cccccccc-0000-0000-0000-00000000000d',
                     'cccccccc-0000-0000-0000-00000000000e',
                     'cccccccc-0000-0000-0000-00000000000f')
  ) c
 where c.id = i.id
   and c.fresh ? 'tsp'
   and c.stored = c.old_default;

select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-00000000000d'),
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "tsp"]'::jsonb,
  '0032 widens a PRISTINE cup-default list with tsp, appending nothing else'
);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-00000000000e'),
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "to_taste"]'::jsonb,
  '0032 leaves a CURATED list alone — a backfill never overwrites a stated fact'
);
select is(
  (select allowed_units from ingredient
     where id = 'cccccccc-0000-0000-0000-00000000000f'),
  '["g", "kg"]'::jsonb,
  '0032 adds nothing where the rule admits no volume unit (the D4c shape)'
);
-- …and it reached the real vocabulary. This is a POPULATION assertion, and
-- the shape of it is the point.
--
-- The obvious version — "no template cup-default row whose rule admits `tsp`
-- is missing it" — cannot live here, because curation is allowed to falsify
-- it and does. Eight cup-default rows carry a stated `remove` for `tsp` with
-- a reason attached (`pea`, `edamame`, `corn frozen`, `pasta cooked`, and the
-- four cooked staples: `lentil cooked`, `quinoa cooked`, `white rice cooked`,
-- `brown rice cooked` — "poured by the cup, not spooned by the tsp"). That is
-- the same house pattern as the 28 mass-default rows ("a spoon of dry pasta
-- is senseless"), and ADR-0012's own fence says a stated fact outranks a
-- derived one. An assertion that fails whenever somebody states a fact is
-- punishing the behaviour the ADR protects.
--
-- Nor can it be rescued by looking harder at the row. `lentil cooked` stores
-- exactly the rule's answer minus `tsp` — which is also, precisely, what a
-- row the widening never reached looks like. Curated and stale are the same
-- bytes; no SQL here can separate them.
--
-- So this asks the question the database CAN answer, and it happens to be the
-- one worth asking. The template's lists are re-materialized by ONE statement
-- in `seed_curation.sql` (`update ingredient set allowed_units =
-- default_allowed_units(...) where household_id = <template>`), with the
-- per-row overrides applied after it. Staleness is therefore all-or-nothing:
-- if that refresh or the function had missed ADR-0012, EVERY cup-default row
-- would lack `tsp` and this count would be 0, not 84. A per-row invariant is
-- the wrong instrument for an all-or-nothing failure; a population count is
-- the right one, and it is immune to curation by construction — curation
-- takes `tsp` off a handful of rows, never off all ninety-two.
--
-- The threshold's only job is to separate "none" from "nearly all", so any
-- number between them does. 92 cup-default rows, 84 carrying `tsp`, 8 curated
-- away: plenty of headroom for the vocabulary to grow and to be curated
-- further without this needing to be renumbered.
select cmp_ok(
  (select count(*)::int from ingredient
     where household_id = '00000000-0000-0000-0000-0000000000aa'
       and default_unit = 'cup' and allowed_units ? 'tsp'),
  '>', 50,
  'the template’s cup-default rows say tsp — the seed re-materialized under '
  'ADR-0012, which is all-or-nothing (84 of 92; a stale rule gives 0)'
);
-- The migration's own behaviour is not measured here at all, and does not
-- need to be: on a fresh reset 0032's backfill runs against an empty database
-- and the seed writes these lists afterwards. What 0032 does is pinned
-- directly, on purpose-built rows, by the three assertions above.
--
-- One consequence of "curated and stale are the same bytes" belongs on the
-- record: on a MIGRATED database 0032 widens a row that removed exactly
-- `tsp` and nothing else, because it satisfies the fence as ADR-0012 states
-- it. That is the collision ADR-0009 already accepted in its own words — a
-- household that removed a unit and later trips the rule "gets it back …
-- the unit is sayable again" — not a defect in the guard. Plan 0036's
-- decision log carries the finding.

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
-- Plan 0022 / ADR-0010: `piece` is an admission fact, curated by hand.
--
-- The owner's ruling (2026-09-02): `piece` is the fallback for when no
-- appropriate measure exists. Where a piece-type measure names the thing — a
-- clove, an avocado, a medium potato — `piece` is not admitted at all, so
-- nothing at runtime ever has to guess which measure a `piece` meant. The
-- decision is DATA (one curated line per row in seed/curation_overrides.jsonl),
-- never a derived rule: deriving it would put `piece` back on broccoli and
-- take it off ginger. These assertions are the safety net that stops a reseed
-- or an unrelated generator change from quietly putting `piece` back.
-- ---------------------------------------------------------------------------

-- The canary. The guard below is vacuous if this set is empty, and a row that
-- has GAINED a measure since the pass is a row that needs its own ruling in
-- curation_overrides.jsonl — so pin the count rather than only the property.
--
-- The number moves when the vocabulary gains a measure-carrying row, and it
-- moved to 142 for `Canned Lentils`, which arrived with a `can (400 g),
-- drained` measure. It is exactly the case this canary is for, and it came
-- with the ruling it demands: `lentil canned` removes `piece` ("the natural
-- count is the can") and names that can as its default measure, so the guard
-- below still holds. Bumping this number without reading the new row's
-- overrides is how the guard goes quiet.
select is(
  (select count(distinct i.id)::int
     from ingredient i
     join ingredient_measure m on m.ingredient_id = i.id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.deleted_at is null and m.deleted_at is null),
  142,
  'the template has 142 measure-carrying ingredients (the curated set)'
);

-- The rule itself, named row by row so a failure says WHICH row regressed.
select is(
  (select coalesce(string_agg(distinct i.match_text, ', '), '')
     from ingredient i
     join ingredient_measure m on m.ingredient_id = i.id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.deleted_at is null and m.deleted_at is null
      and i.allowed_units ? 'piece'),
  '',
  'no seeded ingredient carrying a measure admits `piece` (plan 0022)'
);

-- The other half of the ruling, and the reason `default_allowed_units()` and
-- its Dart mirror are deliberately NOT touched: a measure-less count row must
-- still get `piece`, because there is nothing clearer to say. That is the
-- fallback a household's own new ingredient gets, asked about only when they
-- add a measure to it.
select ok(
  default_allowed_units('piece', 'g', null, 'produce') ? 'piece',
  'a measure-less count row still gets `piece` (the derived rule is untouched)'
);

-- As it happens EVERY seeded count-default row carries a measure, so after the
-- pass the template admits `piece` nowhere. That is the ruling landing, not an
-- accident — but pin it, because the number moving is how a reseed announces
-- that a row gained or lost its measures.
select is(
  (select count(*)::int from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and allowed_units ? 'piece'),
  0,
  'no seeded row admits `piece`: all 76 count-default rows carry a measure'
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
-- and the derived rule admits `piece` only for a count default.
select is(
  default_allowed_units('cup', 'g', 0.6298, 'produce') ? 'piece',
  false,
  'a volume-default row is never admitted `piece` by the rule'
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
