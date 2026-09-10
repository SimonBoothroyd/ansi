-- pgTAP: the monotone `ingredient` rollout
-- (supabase/rollout_ingredient_refresh.sql).
--
-- The script carries a reseeded template's ingredient improvements onto
-- EXISTING households — fill-only on `density_g_per_ml` (a) and
-- `piece_basis_amount` + `piece_source` (c), union-only on `allowed_units`
-- (b), and fill-only on the ONE `fiber` key inside `macros` (d), guarded by
-- sameness. This test pins the contract, with leg (d) as its centre of
-- gravity: a row whose four figures still equal the template's gains the
-- template's fibre and nothing else moves; a row somebody edited, flipped to
-- another basis, already answered for, soft-deleted, household-only, or with
-- no macros at all is left exactly as it is; the template itself is never
-- written; and a second run touches no rows.
--
-- pgTAP cannot `\i` a file outside tests/, so the script's statement is
-- MIRRORED here verbatim between the same `>>>` / `<<<` markers, wrapped in
-- a temp function so it can run twice. `make db-lint` diffs the two blocks;
-- if this test and the script drift, that target fails.
--
-- Runs against the seeded local DB (the template "Home" household 0000…aa).
-- Run by `supabase test db`.

begin;
select plan(24);

-- Isolate: the rollout visits EVERY live non-template household, and a live
-- dev session or `make test-sim` run leaves onboarded strays behind. Tombstone
-- them (everything rolls back at the end); the assertions below only ever
-- read the fixtures.
update household set deleted_at = now() where not is_template;

-- ---------------------------------------------------------------------------
-- Fixtures. Every row is stamped a day old, so `updated_at = now()` after the
-- run means "this statement wrote it" — for the household rows that should be
-- bumped, and for the template rows that must not be.
--
-- The template side: six rows carrying the five-key macros a reseed brings
-- (one of them per ml), plus two carrying the density/units/piece weight that
-- legs (a)–(c) move. `allowed_units` is written explicitly everywhere so the
-- materialization trigger (0012) stays out of the fixtures.
-- ---------------------------------------------------------------------------
insert into ingredient (household_id, canonical_name, default_unit, macros_basis,
                        source, status, match_text, macros, allowed_units,
                        density_g_per_ml, piece_basis_amount, piece_source, updated_at)
values
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Base (test)',     'g',  'g',  'seed', 'complete', 'fibre base test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb, '["g"]'::jsonb,      null, null, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Edited (test)',   'g',  'g',  'seed', 'complete', 'fibre edited test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb, '["g"]'::jsonb,      null, null, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Basis (test)',    'ml', 'ml', 'seed', 'complete', 'fibre basis test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb, '["g","ml"]'::jsonb, null, null, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Own (test)',      'g',  'g',  'seed', 'complete', 'fibre own test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb, '["g"]'::jsonb,      null, null, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Dead (test)',     'g',  'g',  'seed', 'complete', 'fibre dead test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb, '["g"]'::jsonb,      null, null, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Null (test)',     'g',  'g',  'seed', 'complete', 'fibre null test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb, '["g"]'::jsonb,      null, null, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Legs (test)',     'g',  'g',  'seed', 'stub',     'fibre legs test',
   null, '["g","kg","cup"]'::jsonb, 0.9, 50, 'seed:typical', now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000aa', 'Fibre Own Legs (test)', 'g',  'g',  'seed', 'stub',     'fibre own legs test',
   null, '["g","kg"]'::jsonb,       1.5, 99, 'seed:typical', now() - interval '1 day');

-- The household under test: born stamped, like every post-0011 household.
insert into household (id, name, backfilled_at)
values ('00000000-0000-0000-0000-00000000f1b0', 'Fibre (test)', now());

-- Its vocabulary — clones of the template rows as they were seeded BEFORE
-- fibre existed (four keys), each one a different answer to "may we fill it?",
-- plus one ingredient of its own and the two legs (a)–(c) rows.
insert into ingredient (household_id, canonical_name, default_unit, macros_basis,
                        source, status, match_text, macros, allowed_units,
                        density_g_per_ml, piece_basis_amount, piece_source,
                        deleted_at, updated_at)
values
  -- (1) still exactly the template's four figures → gains the fibre.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Base (test)',   'g', 'g', 'usda_fdc:12345', 'complete', 'fibre base test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb, '["g"]'::jsonb,      null, null, null, null, now() - interval '1 day'),
  -- (2) one figure edited → we cannot know its fibre.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Edited (test)', 'g', 'g', 'seed', 'complete', 'fibre edited test',
   '{"kcal":120,"protein":5,"carb":10,"fat":1}'::jsonb, '["g"]'::jsonb,      null, null, null, null, now() - interval '1 day'),
  -- (3) flipped to per g against a per ml template → different numbers by
  --     definition, so the sameness comparison never even applies.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Basis (test)',  'ml', 'g', 'seed', 'complete', 'fibre basis test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb, '["g","ml"]'::jsonb, null, null, null, null, now() - interval '1 day'),
  -- (4) already carries a fibre of its own.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Own (test)',    'g', 'g', 'seed', 'complete', 'fibre own test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":9}'::jsonb, '["g"]'::jsonb, null, null, null, null, now() - interval '1 day'),
  -- (5) tombstoned: stays tombstoned, and stays four-key.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Dead (test)',   'g', 'g', 'seed', 'complete', 'fibre dead test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb, '["g"]'::jsonb,      null, null, null, now(), now() - interval '1 day'),
  -- (6) the household's own ingredient — no template counterpart at all.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Brew (test)',   'g', 'g', 'manual', 'complete', 'fibre homebrew test',
   '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb, '["g"]'::jsonb,      null, null, null, null, now() - interval '1 day'),
  -- (7) no macros at all: a stub gains no fibre and stays a stub.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Null (test)',   'g', 'g', 'seed', 'stub', 'fibre null test',
   null, '["g"]'::jsonb, null, null, null, null, now() - interval '1 day'),
  -- Legs (a)–(c): everything to gain.
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Legs (test)',   'g', 'g', 'seed', 'stub', 'fibre legs test',
   null, '["g","oz"]'::jsonb, null, null, null, null, now() - interval '1 day'),
  -- Legs (a)/(c) fill-only: its own density and piece weight, on a row the
  -- union DOES touch (the template admits a unit it lacks), so "untouched"
  -- here means "the statement ran over it and still kept its numbers".
  ('00000000-0000-0000-0000-00000000f1b0', 'Fibre Own Legs (test)', 'g', 'g', 'seed', 'stub', 'fibre own legs test',
   null, '["g","oz"]'::jsonb, 0.5, 10, 'mine', null, now() - interval '1 day');

-- A soft-deleted household holding a fillable row: must gain nothing.
insert into household (id, name, backfilled_at, deleted_at)
values ('00000000-0000-0000-0000-00000000fdea', 'Fibre Gone (test)', now(), now());
insert into ingredient (household_id, canonical_name, default_unit, macros_basis,
                        source, status, match_text, macros, allowed_units, updated_at)
values ('00000000-0000-0000-0000-00000000fdea', 'Fibre Base (test)', 'g', 'g', 'seed', 'complete', 'fibre base test',
        '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb, '["g"]'::jsonb, now() - interval '1 day');

select ok(
  not ((select macros from ingredient
         where household_id = '00000000-0000-0000-0000-00000000f1b0'
           and match_text = 'fibre base test') ? 'fiber'),
  'fixture: the household row starts with the four keys only'
);

-- ---------------------------------------------------------------------------
-- The rollout, verbatim. Keep in lockstep with the script (make db-lint).
-- Wrapped in plpgsql rather than sql so the statement's ROW_COUNT — the
-- number the operator reads off the run — is an assertable value.
-- ---------------------------------------------------------------------------
create function pg_temp.rollout_ingredient_refresh() returns int
language plpgsql as $rollout$
declare
  touched int;
begin
-- >>> rollout_ingredient_refresh.sql — mirrored in tests/ingredient_rollout.sql
with tpl_household as (
  -- Same resolution as ensure_onboarded(): oldest live template.
  select id from household
  where is_template and deleted_at is null
  order by created_at
  limit 1
),
tpl as (
  -- One template row per match_text. `distinct on` is belt-and-braces: the
  -- generator already forbids collisions, and the oldest row wins if one ever
  -- slips through, so the rollout stays deterministic.
  select distinct on (i.match_text)
         i.match_text, i.density_g_per_ml, i.allowed_units,
         i.piece_basis_amount, i.piece_source, i.macros, i.macros_basis
  from ingredient i
  join tpl_household th on th.id = i.household_id
  where i.deleted_at is null
  order by i.match_text, i.created_at, i.id
)
update ingredient i
set
  -- (a) fill only; coalesce keeps a household's own density verbatim.
  density_g_per_ml = coalesce(i.density_g_per_ml, t.density_g_per_ml),
  -- (b) union only; the household's admissions come first (a stored SET —
  -- the client owns display order), the template's additions append.
  allowed_units = case
    when i.allowed_units is null and t.allowed_units is null then null
    else (
      select coalesce(jsonb_agg(u.unit order by u.ord, u.unit), '[]'::jsonb)
      from (
        select e.unit, min(e.ord) as ord
        from (
          select unit, ord
          from jsonb_array_elements_text(coalesce(i.allowed_units, '[]'::jsonb))
               with ordinality as own(unit, ord)
          union all
          select unit, 1000 + ord
          from jsonb_array_elements_text(coalesce(t.allowed_units, '[]'::jsonb))
               with ordinality as tmpl(unit, ord)
        ) e
        group by e.unit
      ) u
    )
  end,
  -- (c) fill only, and the provenance rides with the number: a household that
  -- has said what one of these weighs keeps its answer AND its `piece_source`
  -- verbatim. `piece` itself is not written here — it arrives through (b),
  -- because the template's own list already says it.
  piece_basis_amount = coalesce(i.piece_basis_amount, t.piece_basis_amount),
  piece_source = case
    when i.piece_basis_amount is not null then i.piece_source
    else t.piece_source
  end,
  -- (d) fill the fibre key only, and only where the household's macros still
  -- ARE the template's. `||` adds one key and rewrites nothing else. The
  -- guard is the whole contract: a row whose figures somebody edited is
  -- never touched, because its fibre is not the template's to give.
  macros = case
    when jsonb_typeof(i.macros) = 'object'          -- not null, and an object
     and not (i.macros ? 'fiber')                   -- nothing of its own yet
     and jsonb_typeof(t.macros -> 'fiber') = 'number'
     -- Same basis, or the figures are not comparable at all: a row the
     -- household flipped to per ml holds different numbers by definition,
     -- and a per-100-ml fibre would not be the per-100-g one anyway.
     and i.macros_basis = t.macros_basis
     -- Sameness: the four figures still equal the template's (jsonb numbers
     -- compare by value, so 5 and 5.0 are the same figure).
     and (i.macros - 'fiber') = (t.macros - 'fiber')
    then i.macros || jsonb_build_object('fiber', t.macros -> 'fiber')
    else i.macros
  end,
  -- Bump so PowerSync replicates the change down to every device.
  updated_at = now()
from tpl t, household h
where h.id = i.household_id
  and not h.is_template          -- never write to the template itself
  and h.deleted_at is null
  and i.deleted_at is null       -- a row the household deleted stays deleted
  and i.match_text = t.match_text
  and (
    -- leg (a): a density to gain
    (i.density_g_per_ml is null and t.density_g_per_ml is not null)
    or
    -- leg (b): a unit to gain (jsonb containment = "template ⊆ household")
    (t.allowed_units is not null
     and not (t.allowed_units <@ coalesce(i.allowed_units, '[]'::jsonb)))
    or
    -- leg (c): a piece weight to gain
    (i.piece_basis_amount is null and t.piece_basis_amount is not null)
    or
    -- leg (d): a fibre figure to gain, on macros that are still the
    -- template's — the same predicate as the SET above.
    (jsonb_typeof(i.macros) = 'object'
     and not (i.macros ? 'fiber')
     and jsonb_typeof(t.macros -> 'fiber') = 'number'
     and i.macros_basis = t.macros_basis
     and (i.macros - 'fiber') = (t.macros - 'fiber'))
  );
-- <<< rollout_ingredient_refresh.sql
  get diagnostics touched = row_count;
  return touched;
end;
$rollout$;

select is(
  pg_temp.rollout_ingredient_refresh(),
  3,
  'the rollout runs, and touches exactly the three rows with something to gain'
);

-- ---------------------------------------------------------------------------
-- Leg (d): the fill, and nothing else on the row.
-- ---------------------------------------------------------------------------
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre base test'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb,
  'a row whose four figures still equal the template''s gains the template fibre'
);
select is(
  (select status from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre base test'),
  'complete',
  'its status is not rewritten'
);
select is(
  (select source from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre base test'),
  'usda_fdc:12345',
  'nor its own provenance source'
);
select is(
  (select density_g_per_ml from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre base test'),
  null::numeric,
  'and no other column moves with it'
);
select is(
  (select updated_at from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre base test'),
  now(),
  'updated_at is bumped, so PowerSync replicates the row down'
);

-- ---------------------------------------------------------------------------
-- Leg (d): every row the sameness guard walks past.
-- ---------------------------------------------------------------------------
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre edited test'),
  '{"kcal":120,"protein":5,"carb":10,"fat":1}'::jsonb,
  'a row with one figure edited is left alone — its fibre is not the template''s to give'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre basis test'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb,
  'a row the household flipped to another macros_basis is left alone'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre own test'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":9}'::jsonb,
  'a row that already carries a fibre keeps its own value'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre dead test'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb,
  'a soft-deleted row gains nothing'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre homebrew test'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb,
  'a household-only row with no template counterpart gains nothing'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre null test'),
  null::jsonb,
  'a row with no macros at all gains none (the fill never invents a shape)'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000fdea'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1}'::jsonb,
  'a soft-deleted household gains nothing'
);
select is(
  (select count(*)::int from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and updated_at = now()),
  0,
  'the template itself is never written'
);

-- ---------------------------------------------------------------------------
-- Legs (a)–(c) still hold: the mirror covers the whole statement, not just
-- the new leg.
-- ---------------------------------------------------------------------------
select is(
  (select density_g_per_ml from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre legs test'),
  0.9::numeric,
  'leg (a): a null density is filled from the template'
);
select ok(
  (select allowed_units from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre legs test') @> '["oz","kg","cup"]'::jsonb,
  'leg (b): allowed_units is the union — the household''s own unit kept, the template''s added'
);
select is(
  (select piece_basis_amount from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre legs test'),
  50::numeric,
  'leg (c): a null piece weight is filled from the template'
);
select is(
  (select piece_source from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre legs test'),
  'seed:typical',
  'and its provenance rides with the number'
);
select is(
  (select density_g_per_ml from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre own legs test'),
  0.5::numeric,
  'leg (a) is fill-only: a household''s own density survives a row the union rewrote'
);
select is(
  (select piece_basis_amount from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre own legs test'),
  10::numeric,
  'leg (c) is fill-only: so does its own piece weight'
);
select is(
  (select piece_source from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre own legs test'),
  'mine',
  'and the piece_source beside it'
);

-- ---------------------------------------------------------------------------
-- Idempotent: a second run changes nothing.
-- ---------------------------------------------------------------------------
select is(
  pg_temp.rollout_ingredient_refresh(),
  0,
  'a second run touches no rows'
);
select is(
  (select macros from ingredient
    where household_id = '00000000-0000-0000-0000-00000000f1b0'
      and match_text = 'fibre base test'),
  '{"kcal":100,"protein":5,"carb":10,"fat":1,"fiber":3}'::jsonb,
  'and the rolled-out fibre is exactly what the first run wrote'
);

select * from finish();
rollback;
