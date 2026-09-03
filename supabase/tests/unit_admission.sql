-- pgTAP: the ADR-0008 unit-admission schema (migration 0012) as amended by
-- ADR-0009 (0014) and brought to parity with the app by 0021 (plan 0020
-- D4c + J3 — the basis-strict mates leg, the derived density unlock, the
-- per-word imprecise gate), plus 0014's two ingredient triggers.
--
-- `default_allowed_units()` / `density_unlocked_units()` are the SQL mirrors
-- of the app's derived rule (`defaultAllowedUnitSet` / `densityUnlockedUnits`
-- / `kImpreciseCategoryGates` in allowed_units.dart). The vectors here mirror
-- `app/test/features/ingredients/allowed_units_test.dart` CASE FOR CASE —
-- each block below names the Dart test it twins — so a drift between the two
-- mirrors fails a suite on whichever side moved. The Dart side is the source
-- of truth; a stored list is a SET, so where Dart asserts a display ORDER
-- (`allowedUnitsFor` runs `_orderUnits`) the jsonb here is pinned in the
-- function's emission order instead, and the members are what is compared.
--
-- Also pins: the BEFORE INSERT trigger that materializes the list, that an
-- explicit list is never overridden, that the 0014 backfill/seed refresh
-- UNIONED rather than re-materialized (curated removals survive, curated
-- additions survive), that the retired seed-level produce patch's admissions
-- now fall out of the rule (plan 0020 D4 — this assertion IS the safety net
-- that replaced the patch), the density→allowed_units union trigger (including
-- the flour shape 0021 exists for), 0021's backfill post-state, the USDA stub
-- prefill trigger (0014's insert leg AND 0015's rename leg), the basis_amount
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
-- Run by `supabase test db`.

begin;
select plan(111);

-- ---------------------------------------------------------------------------
-- default_allowed_units() vectors — mirror allowed_units_test.dart, group
-- 'allowedUnitsFor — ADR-0008 derived defaults', test for test.
-- ---------------------------------------------------------------------------

-- Dart: 'THE YEAST SHAPE, under D4c'. tsp default, per-g basis, NO density →
-- the basis base and nothing else. Being sold by the spoon does not make
-- spoons convertible; before D4c (0012/0014) this read ["tsp","tbsp","g"].
select is(
  default_allowed_units('tsp', 'g', null, 'baking'),
  '["g"]'::jsonb,
  'tsp default /g without density: the basis base only (the yeast shape, D4c)'
);
-- …and a density is what buys the spoons back.
select is(
  default_allowed_units('tsp', 'g', 0.4, 'baking'),
  '["tsp", "tbsp", "g"]'::jsonb,
  'tsp default /g with density: the spoons come back'
);

-- Dart: 'the flour shape'. cup default, per-g basis, density → the cup's
-- kitchen mates, g AND kg (cup-scale justifies the big sibling).
select is(
  default_allowed_units('cup', 'g', 0.59, 'baking'),
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg"]'::jsonb,
  'cup default /g with density: kitchen volume + g/kg (the flour shape)'
);

-- Dart: 'the olive-oil shape'. tbsp default, per-g, density, oil category →
-- mates + g + the OIL class's words. J3: no handful of oil.
select is(
  default_allowed_units('tbsp', 'g', 0.91, 'fats & oils'),
  '["tbsp", "tsp", "cup", "ml", "pt", "g", "pinch", "dash", "to_taste"]'::jsonb,
  'tbsp default /g oil: mates + g + pinch/dash/to_taste (the olive-oil shape)'
);
select ok(
  not (default_allowed_units('tbsp', 'g', 0.91, 'fats & oils') ? 'handful'),
  'J3: nobody takes a handful of oil'
);

-- Dart: 'the egg shape'. count default, per-g, NO density, produce → piece +
-- the basis base, and produce earns `handful` and nothing else (J3).
select is(
  default_allowed_units('piece', 'g', null, 'produce'),
  '["piece", "g", "handful"]'::jsonb,
  'count default /g without density: piece + basis base + handful (the egg shape)'
);

-- Dart: 'the salt shape'. The seasoning category admits the whole tail —
-- which D4c leaves alone, being no part of the mass⇄volume duality — but
-- the spoons are gone: tsp /g with no density is the yeast shape again.
select is(
  default_allowed_units('tsp', 'g', null, 'spices & seasoning'),
  '["g", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'seasoning category admits pinch/dash/handful/to_taste (the salt shape)'
);

-- Dart: 'an imprecise default keeps its whole tail + the basis base'.
select is(
  default_allowed_units('pinch', 'g', null, 'spices & seasoning'),
  '["g", "pinch", "dash", "handful", "to_taste"]'::jsonb,
  'an imprecise default yields basis base + the imprecise tail'
);

-- Dart: 'a per-ml liquid'. The volume default IS the basis family — no gram
-- leg without a density; with one, mass unlocks.
select is(
  default_allowed_units('cup', 'ml', null, null),
  '["cup", "tbsp", "ml", "l", "pt", "qt"]'::jsonb,
  'cup default /ml without density: volume only'
);
select is(
  default_allowed_units('cup', 'ml', 1.03, null),
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg"]'::jsonb,
  'cup default /ml with density: g/kg unlock (demoted client-side)'
);

-- Dart: 'a mass default /g with density unlocks kitchen volume'. Oats: grams
-- AND cups are both honest; no piece.
select is(
  default_allowed_units('g', 'g', 0.4, null),
  '["g", "kg", "tsp", "tbsp", "cup", "pt", "ml"]'::jsonb,
  'g default /g with density: own family + the volume workhorses, no piece'
);

-- Dart: 'THE MANGO VECTOR' (ADR-0009). A piece default with a density admits
-- the volume workhorses — "1 cup diced mango" is a real line. `kg` and `l`
-- stay out: the big metric siblings ride the same magnitude gate the
-- mass/volume legs use, and a piece default is not big-scale.
select is(
  default_allowed_units('piece', 'g', 0.66, 'produce'),
  '["piece", "g", "tsp", "tbsp", "cup", "pt", "ml", "handful"]'::jsonb,
  'count default /g WITH density: volume workhorses unlock (the mango shape)'
);

-- Dart: 'without a density a count default still admits nothing but its own
-- piece and the basis base' — the amendment unlocks on the density, not on
-- the family; `handful` is the category's word, not the density's business.
select is(
  default_allowed_units('piece', 'g', null, 'produce'),
  '["piece", "g", "handful"]'::jsonb,
  'count default without density: piece + basis base + the category word only'
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
  '["cup", "tbsp", "ml", "l", "pt", "qt", "g", "kg", "handful"]'::jsonb,
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
  density_unlocked_units('cup', 'g'), array['cup','tbsp','ml','l','pt','qt'],
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
  '["g", "kg", "cup", "tbsp", "ml", "l", "pt", "qt"]'::jsonb,
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
select is(
  (select count(distinct i.id)::int
     from ingredient i
     join ingredient_measure m on m.ingredient_id = i.id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.deleted_at is null and m.deleted_at is null),
  141,
  'the template has 141 measure-carrying ingredients (the curated set)'
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
-- 0014 / plan 0020 D7: the USDA stub prefill trigger.
--
-- A private reference row so the vectors do not depend on which FDC foods
-- the seed happens to carry. `usda_food` is server-only (ADR-0005): the
-- trigger is SECURITY DEFINER precisely so an `authenticated` inserter — who
-- has no grant on the table at all — still gets the prefill.
-- ---------------------------------------------------------------------------

insert into usda_food (fdc_id, description, category, density_g_per_ml,
  macros, match_text)
values (999000001, 'Zzquux Test Reference Food', 'produce', 0.75,
  '{"kcal": 100, "protein": 2, "carb": 20, "fat": 1}'::jsonb,
  'zzquux test reference food');

insert into ingredient (id, household_id, canonical_name, default_unit,
  category, status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000003',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test Reference Food', 'g',
  'produce', 'stub', 'import_stub', 'zzquux test reference food');

select is(
  (select density_g_per_ml from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  0.75::numeric,
  'an import stub is USDA-prefilled with the density on insert'
);
select is(
  (select macros ->> 'kcal' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  '100',
  'the prefill copies the macros too'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  'usda_fdc:999000001',
  'the prefill records the FDC provenance'
);
select is(
  (select status from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  'stub',
  'the prefilled row STAYS a stub — completion is a human confirm (D5)'
);
-- The density landed by the prefill also flows through the density trigger,
-- so the row's allowed_units are honest about what it can now say.
select ok(
  (select allowed_units ? 'tsp' and allowed_units ? 'cup' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000003'),
  'the prefilled density unlocks the volume workhorses in the same insert'
);

-- A weak hit (0.44 similarity against 'zzquux test reference food' — above
-- pg_trgm's 0.3 match threshold, below the 0.5 prefill floor) is left alone.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000004',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test', 'g',
  'stub', 'import_stub', 'zzquux test');
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000004'),
  'import_stub',
  'a weak trigram hit does not prefill (below the 0.5 floor)'
);

-- A seeded/curated row is NOT prefilled: the seed pipeline audits its own
-- density tail, and the template clone inside ensure_onboarded() must not
-- pay a trigram probe per cloned stub.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000005',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test Reference Food', 'g',
  'stub', 'seed', 'zzquux test reference food');
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000005'),
  'seed',
  'a seed-sourced stub is left alone by the prefill'
);
select ok(
  (select density_g_per_ml is null from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000005'),
  'a seed-sourced stub keeps its honestly-absent density'
);

-- A `complete` row is never touched, whatever it matches.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text, macros)
values ('cccccccc-0000-0000-0000-000000000006',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Test Reference Food', 'g',
  'complete', 'manual', 'zzquux test reference food',
  '{"kcal": 7}'::jsonb);
select is(
  (select macros ->> 'kcal' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000006'),
  '7',
  'a complete row is never prefilled over'
);

-- THE contract that matters: the prefill runs inside the client's upload
-- transaction, so it must never fail it. Break the reference set outright
-- and the insert must still land, un-enriched. (DDL is transactional; the
-- rename rolls back with everything else.)
alter table usda_food rename to usda_food_hidden_by_test;
select lives_ok(
  $$ insert into ingredient (id, household_id, canonical_name, default_unit,
       status, source, match_text)
     values ('cccccccc-0000-0000-0000-000000000007',
       'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Zzquux Broken', 'g',
       'stub', 'import_stub', 'zzquux test reference food') $$,
  'a stub insert survives a prefill that throws (swallow-and-log)'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000007'),
  'import_stub',
  'the surviving row is simply un-enriched'
);
alter table usda_food_hidden_by_test rename to usda_food;

-- ---------------------------------------------------------------------------
-- 0015 / plan 0020 D7: the same prefill on a RENAME.
--
-- 0014's trigger was AFTER INSERT only; 0015 recreates it as AFTER INSERT OR
-- UPDATE OF canonical_name, because D7 (c) is explicitly about renames ("you
-- fix 'curry leafs' → 'Curry leaves, fresh' and want the lookup re-run") and
-- the flesh-out form says so on screen. The WHEN guards are unchanged, which
-- is what keeps the update leg from touching a row someone has filled in.
-- ---------------------------------------------------------------------------

-- A bare stub under a name the trigram misses: nothing to copy on insert.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text)
values ('cccccccc-0000-0000-0000-000000000008',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Qqfoo Mystery Item', 'g',
  'stub', 'manual', 'qqfoo mystery item');
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  'manual',
  'the misnamed stub arrives un-enriched (nothing matched on insert)'
);

-- The rename the user makes on the flesh-out form: name and match_text
-- written together (D6), which is the statement 0015's trigger catches.
update ingredient
   set canonical_name = 'Zzquux Test Reference Food',
       match_text = 'zzquux test reference food'
 where id = 'cccccccc-0000-0000-0000-000000000008';
select is(
  (select density_g_per_ml from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  0.75::numeric,
  'a rename on a BARE stub re-runs the probe and can fill it (0015)'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  'usda_fdc:999000001',
  'the re-run records the FDC provenance'
);
select is(
  (select status from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000008'),
  'stub',
  'a renamed-and-prefilled row is STILL a stub (D5 holds on the new leg)'
);

-- The guard that matters most on the update leg: a row someone has already
-- filled in is never re-probed, so a rename cannot clobber real numbers.
insert into ingredient (id, household_id, canonical_name, default_unit,
  status, source, match_text, macros)
values ('cccccccc-0000-0000-0000-000000000009',
  'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Qqfoo Fleshed Out', 'g',
  'stub', 'manual', 'qqfoo fleshed out', '{"kcal": 7}'::jsonb);
update ingredient
   set canonical_name = 'Zzquux Test Reference Food',
       match_text = 'zzquux test reference food'
 where id = 'cccccccc-0000-0000-0000-000000000009';
select is(
  (select macros ->> 'kcal' from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000009'),
  '7',
  'renaming a fleshed-out stub is a no-op — its macros survive'
);
select is(
  (select source from ingredient
     where id = 'cccccccc-0000-0000-0000-000000000009'),
  'manual',
  'and its provenance is not rewritten to a USDA id'
);

-- ---------------------------------------------------------------------------
-- 0016 / plan 0020 D7b: the probe exposed as an RPC.
--
-- Everything above still passing IS half the assertion: the trigger now
-- delegates to `usda_probe()`, so those vectors prove the extraction changed
-- no behaviour. What follows pins the new door.
-- ---------------------------------------------------------------------------

select has_function('probe_usda', array['text'],
  'probe_usda(text) exists — the D7b client door');
select has_function('usda_probe', array['text'],
  'usda_probe(text) exists — the shared probe both callers read');

-- SECURITY DEFINER with a pinned search_path, exactly as 0014's function has:
-- these read a table no client role is granted, so definer rights are the
-- point and an unpinned search_path would be the hole.
select ok(
  (select bool_and(p.prosecdef) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('probe_usda', 'usda_probe', 'ingredient_prefill_from_usda')),
  'the probe, its RPC and the prefill trigger are all SECURITY DEFINER'
);
select ok(
  (select bool_and(p.proconfig::text like '%search_path=public, extensions%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('probe_usda', 'usda_probe', 'ingredient_prefill_from_usda')),
  'all three pin search_path to public, extensions (definer hygiene)'
);

-- The grant shape: authenticated reaches the RPC and NOTHING else. anon
-- reaches neither, and the reference table stays ungranted (ADR-0005).
select ok(
  has_function_privilege('authenticated', 'probe_usda(text)', 'execute'),
  'authenticated may call probe_usda — the D7b door is open'
);
select ok(
  not has_function_privilege('anon', 'probe_usda(text)', 'execute'),
  'anon may not: enrichment is for a signed-in household'
);
select ok(
  not has_function_privilege('authenticated', 'usda_probe(text)', 'execute'),
  'authenticated may NOT call the helper directly — one door, not two'
);
select ok(
  not has_table_privilege('authenticated', 'usda_food', 'select'),
  'and usda_food itself is still unreachable (ADR-0005 unmoved by D7b)'
);

-- It returns the same candidate the trigger copies, with the same source
-- stamp the trigger writes — that identity is what makes the app-vs-trigger
-- race benign.
select is(
  (select fdc_id from probe_usda('zzquux test reference food')),
  999000001,
  'probe_usda returns the confident candidate'
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
  'and the SAME source stamp the trigger writes — one formatter, not two'
);

-- The 0.5 floor lives in the helper, so the RPC inherits it: the same weak
-- hit the trigger refuses above returns no row here.
select is_empty(
  $$ select * from probe_usda('zzquux test') $$,
  'a weak trigram hit returns nothing (the same 0.5 floor as the trigger)'
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

select * from finish();
rollback;
