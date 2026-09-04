-- pgTAP: the monotone `ingredient_measure` rollout
-- (supabase/rollout_measure_refresh.sql, exec plan 0023).
--
-- The script carries a reseeded template's measures onto EXISTING households
-- — insert-missing, keyed on (ingredient match_text, measure label). This
-- test pins the contract: a template measure the household's matching
-- ingredient lacks is inserted (label, basis_amount, sort_order, source
-- verbatim; a fresh updated_at so PowerSync replicates it); an existing live
-- measure keeps its own weight even where the template's differs; a
-- household's own measures are untouched; a label the household soft-deleted
-- is never resurrected; a soft-deleted template measure, a measure on a
-- `manual` template ingredient, and a measure whose basis disagrees with the
-- household's row never cross; soft-deleted households/ingredients gain
-- nothing; the template itself is never written; and a second run is a
-- no-op.
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
-- Fixtures. Three template ingredients: a curated per-g row (the rollout
-- source), a curated per-ml row (the basis-mismatch case) and a `manual` row
-- (private — its measures never leave the template).
-- ---------------------------------------------------------------------------
insert into ingredient (household_id, canonical_name, default_unit, macros_basis, source, match_text) values
  ('00000000-0000-0000-0000-0000000000aa', 'Rollout Tin (test)',    'g',  'g',  'seed',   'rollout tin test'),
  ('00000000-0000-0000-0000-0000000000aa', 'Rollout Milk (test)',   'ml', 'ml', 'seed',   'rollout milk test'),
  ('00000000-0000-0000-0000-0000000000aa', 'Rollout Secret (test)', 'g',  'g',  'manual', 'rollout secret test');

-- The household under test: born stamped, like every post-0011 household.
insert into household (id, name, backfilled_at)
values ('00000000-0000-0000-0000-00000000b0b0', 'Rollout (test)', now());
-- Its vocab: clones of the three template rows (the milk row with its basis
-- FLIPPED to per-g by the flesh-out form), one ingredient of its own, and a
-- tombstoned second copy of the tin.
insert into ingredient (household_id, canonical_name, default_unit, macros_basis, source, match_text, deleted_at) values
  ('00000000-0000-0000-0000-00000000b0b0', 'Rollout Tin (test)',      'g',  'g', 'seed',   'rollout tin test',      null),
  ('00000000-0000-0000-0000-00000000b0b0', 'Rollout Milk (test)',     'ml', 'g', 'seed',   'rollout milk test',     null),
  ('00000000-0000-0000-0000-00000000b0b0', 'Rollout Secret (test)',   'g',  'g', 'manual', 'rollout secret test',   null),
  ('00000000-0000-0000-0000-00000000b0b0', 'Rollout Homebrew (test)', 'g',  'g', 'manual', 'rollout homebrew test', null),
  ('00000000-0000-0000-0000-00000000b0b0', 'Rollout Tin (dead)',      'g',  'g', 'seed',   'rollout tin test',      now());

-- A soft-deleted household holding the tin: must gain nothing.
insert into household (id, name, backfilled_at, deleted_at)
values ('00000000-0000-0000-0000-00000000dead', 'Gone (test)', now(), now());
insert into ingredient (household_id, canonical_name, default_unit, source, match_text)
values ('00000000-0000-0000-0000-00000000dead', 'Rollout Tin (test)', 'g', 'seed', 'rollout tin test');

-- The household's own measures on the tin: one of its own, one it deleted,
-- and one whose label the template ALSO carries (with a different weight).
insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, source, deleted_at)
select '00000000-0000-0000-0000-00000000b0b0', id, m.label, m.amt, 'manual', m.dead
from ingredient,
     (values ('my scoop', 30, null::timestamptz),
             ('old can', 400, now()),
             ('shared label', 99, null)) as m(label, amt, dead)
where household_id = '00000000-0000-0000-0000-00000000b0b0'
  and match_text = 'rollout tin test' and deleted_at is null;
-- …and one on the ingredient that has no template counterpart.
insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, source)
select '00000000-0000-0000-0000-00000000b0b0', id, 'ladle', 50, 'manual'
from ingredient
where household_id = '00000000-0000-0000-0000-00000000b0b0'
  and match_text = 'rollout homebrew test';

-- The reseeded template's measures on the tin: the one the household lacks
-- (the rollout's whole point), the shared label (must NOT overwrite 99), the
-- label the household deleted (must NOT resurrect), and a tombstoned one
-- (must not cross).
insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, sort_order, source, deleted_at)
select '00000000-0000-0000-0000-0000000000aa', id, m.label, m.amt, m.ord, 'seed:typical', m.dead
from ingredient,
     (values ('can (test)', 400, 3, null::timestamptz),
             ('shared label', 400, 0, null),
             ('old can', 400, 0, null),
             ('dead template', 1, 0, now())) as m(label, amt, ord, dead)
where household_id = '00000000-0000-0000-0000-0000000000aa'
  and match_text = 'rollout tin test';
-- On the per-ml milk (the household's copy is per-g) and on the manual row.
insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, source)
select '00000000-0000-0000-0000-0000000000aa', id, 'carton', 1000, 'seed:typical'
from ingredient
where household_id = '00000000-0000-0000-0000-0000000000aa'
  and match_text = 'rollout milk test';
insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, source)
select '00000000-0000-0000-0000-0000000000aa', id, 'secret scoop', 30, 'seed:typical'
from ingredient
where household_id = '00000000-0000-0000-0000-0000000000aa'
  and match_text = 'rollout secret test';

-- Remember the template's row count: the rollout must never write to it.
-- (A tx-scoped GUC inside `do`, as onboarding.sql does — a bare SELECT would
-- print a non-TAP line.)
do $$ begin
  perform set_config('test.tpl_rows',
    (select count(*)::text from ingredient_measure
      where household_id = '00000000-0000-0000-0000-0000000000aa'), true);
end $$;

select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and deleted_at is null),
  3,
  'fixture: the household starts with three live measures of its own'
);

-- ---------------------------------------------------------------------------
-- The rollout, verbatim. Keep in lockstep with the script (make db-lint).
-- ---------------------------------------------------------------------------
create function pg_temp.rollout_measure_refresh() returns void
language sql as $rollout$
-- >>> rollout_measure_refresh.sql — mirrored in tests/measure_rollout.sql
with tpl_household as (
  -- Same resolution as ensure_onboarded(): oldest live template.
  select id from household
  where is_template and deleted_at is null
  order by created_at
  limit 1
),
tpl as (
  -- One template measure per (match_text, label). `distinct on` is
  -- belt-and-braces: the seed guards on the label, and the oldest row wins
  -- if a duplicate ever slips through, so the rollout stays deterministic.
  -- `manual` template ingredients are excluded exactly as the clone
  -- excludes them.
  select distinct on (si.match_text, im.label)
         si.match_text, si.macros_basis,
         im.label, im.basis_amount, im.sort_order, im.source
  from ingredient_measure im
  join tpl_household th on th.id = im.household_id
  join ingredient si on si.id = im.ingredient_id
   and si.household_id = th.id
   and si.deleted_at is null
   and si.source is distinct from 'manual'
  where im.deleted_at is null
  order by si.match_text, im.label, im.created_at, im.id
)
insert into ingredient_measure
  (household_id, ingredient_id, label, basis_amount, sort_order, source)
select di.household_id, di.id, t.label, t.basis_amount, t.sort_order, t.source
from tpl t
join ingredient di on di.match_text = t.match_text
 and di.deleted_at is null          -- a row the household deleted stays deleted
join household h on h.id = di.household_id
 and not h.is_template              -- never write to the template itself
 and h.deleted_at is null
where
  -- `basis_amount` is an amount in the INGREDIENT's basis unit (0012). A
  -- household that flipped its row's basis would read the template's number
  -- in the wrong unit — leave that ingredient alone rather than invent one.
  di.macros_basis = t.macros_basis
  -- Insert-missing: no row with this label on this ingredient, live OR
  -- tombstoned. A label the household soft-deleted stays deleted (0011's
  -- doctrine: deliberate deletion is never resurrected); a live one keeps
  -- its own weight, whatever the template now says.
  and not exists (
    select 1 from ingredient_measure x
    where x.ingredient_id = di.id
      and x.label = t.label
  );
-- <<< rollout_measure_refresh.sql
$rollout$;

select lives_ok(
  $$ select pg_temp.rollout_measure_refresh() $$,
  'the rollout runs'
);

-- ---------------------------------------------------------------------------
-- The insert.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from ingredient_measure im
     join ingredient i on i.id = im.ingredient_id
    where im.household_id = '00000000-0000-0000-0000-00000000b0b0'
      and i.match_text = 'rollout tin test' and i.deleted_at is null
      and im.label = 'can (test)' and im.deleted_at is null),
  1,
  'the template measure the household lacked is inserted on its matching ingredient'
);
select is(
  (select basis_amount from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'can (test)'),
  400::numeric,
  'with the template basis_amount'
);
select is(
  (select sort_order from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'can (test)'),
  3,
  'the template sort_order'
);
select is(
  (select source from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'can (test)'),
  'seed:typical',
  'and the template provenance source (0010)'
);
select is(
  (select updated_at from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'can (test)'),
  now(),
  'a fresh row carries updated_at = now(), so PowerSync replicates it'
);

-- ---------------------------------------------------------------------------
-- Never overwrite, never touch the household's own rows, never resurrect.
-- ---------------------------------------------------------------------------
select is(
  (select basis_amount from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'shared label'),
  99::numeric,
  'an existing live measure keeps its own weight where the template differs'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'shared label'),
  1,
  'and is not duplicated'
);
select is(
  (select basis_amount from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'my scoop'
      and deleted_at is null),
  30::numeric,
  'a measure the household created itself is untouched'
);
select is(
  (select basis_amount from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'ladle'
      and deleted_at is null),
  50::numeric,
  'as is a measure on an ingredient with no template counterpart'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'old can'
      and deleted_at is null),
  0,
  'a label the household soft-deleted is never resurrected'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'old can'),
  1,
  'nor re-inserted beside its tombstone'
);

-- ---------------------------------------------------------------------------
-- What never crosses.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'dead template'),
  0,
  'a soft-deleted template measure does not cross'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'secret scoop'),
  0,
  'a measure on a manual template ingredient does not cross (ensure_onboarded parity)'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'carton'),
  0,
  'a measure whose basis disagrees with the household row is skipped, not misread'
);
select is(
  (select count(*)::int from ingredient_measure im
     join ingredient i on i.id = im.ingredient_id
    where im.household_id = '00000000-0000-0000-0000-00000000b0b0'
      and i.deleted_at is not null),
  0,
  'a soft-deleted household ingredient gains nothing'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000dead'),
  0,
  'a soft-deleted household gains nothing'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-0000000000aa'),
  current_setting('test.tpl_rows')::int,
  'the template itself is never written'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and deleted_at is null),
  4,
  'net effect: exactly one new live measure in the household'
);

-- ---------------------------------------------------------------------------
-- Idempotent: a second run changes nothing.
-- ---------------------------------------------------------------------------
do $$ begin
  perform set_config('test.hh_rows',
    (select count(*)::text from ingredient_measure
      where household_id = '00000000-0000-0000-0000-00000000b0b0'), true);
end $$;

select lives_ok(
  $$ select pg_temp.rollout_measure_refresh() $$,
  'the rollout runs a second time'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0'),
  current_setting('test.hh_rows')::int,
  'a second run is a no-op (row count unchanged, tombstones included)'
);
select is(
  (select count(*)::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and label = 'can (test)'),
  1,
  'the rolled-out measure is not duplicated by the second run'
);
select is(
  (select (count(*) - count(distinct (ingredient_id, label)))::int from ingredient_measure
    where household_id = '00000000-0000-0000-0000-00000000b0b0' and deleted_at is null),
  0,
  'every live (ingredient, label) in the household is unique afterwards'
);

select * from finish();
rollback;
