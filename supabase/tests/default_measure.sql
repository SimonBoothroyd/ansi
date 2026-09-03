-- pgTAP: the curated default count measure (0023, plan 0024 seam D1).
--
-- `ingredient.default_measure_id` says what a bare count of a row MEANS ("2
-- onions" = 2 × `onion, medium`). It is a stated per-row fact, so what needs
-- defending is that it cannot tell a lie and cannot be taken away:
--   * the column is a nullable FK onto `ingredient_measure` with ON DELETE
--     SET NULL — a hard-deleted measure clears the default rather than
--     leaving it dangling;
--   * the own-measure trigger refuses a measure from another ingredient or
--     another household;
--   * the backfill (`ingredient_default_measure_backfill()`) fills a NULL by
--     (match_text, measure label), per household, and NEVER overwrites a
--     household's own choice — ADR-0009 rule 3's posture, and what makes the
--     function safe to re-run after `rollout_measure_refresh.sql`;
--   * the seeded template carries the curation, and the nine fragment-set
--     rows carry NO default (asserted BY NAME, so a regenerated seed cannot
--     quietly rule on one of them — the same job the `piece` guard in
--     unit_admission.sql does for ADR-0010);
--   * `ensure_onboarded()` carries the default into a new household by
--     LABEL, because every household holds its own measure rows.
--
-- Runs against the seeded local DB (the template "Home" household 0000…aa).
-- Run by `supabase test db`.

begin;
select plan(23);

-- Isolate: the backfill visits EVERY household, and a live dev session or a
-- `make test-sim` run leaves onboarded strays behind. Tombstone them
-- (everything rolls back at the end); the assertions below read only the
-- template and the fixtures.
delete from household_member;
update household set deleted_at = now() where not is_template;

-- ---------------------------------------------------------------------------
-- 1. The column and its FK.
-- ---------------------------------------------------------------------------
select has_column('ingredient', 'default_measure_id',
  'ingredient carries default_measure_id');
select col_type_is('ingredient', 'default_measure_id', 'uuid',
  'default_measure_id is a uuid');
select col_is_null('ingredient', 'default_measure_id',
  'default_measure_id is nullable — "no honest default" is a real answer');
select col_is_fk('ingredient', 'default_measure_id',
  'default_measure_id is a foreign key onto ingredient_measure');

-- ---------------------------------------------------------------------------
-- 2. Fixtures: one household with two measured ingredients.
-- ---------------------------------------------------------------------------
insert into household (id, name, backfilled_at)
values ('00000000-0000-0000-0000-00000000d001', 'Default (test)', now());

insert into ingredient (household_id, canonical_name, default_unit, source, match_text) values
  ('00000000-0000-0000-0000-00000000d001', 'Onion (test)',    'piece', 'seed', 'onion test'),
  ('00000000-0000-0000-0000-00000000d001', 'Broccoli (test)', 'piece', 'seed', 'broccoli test');

insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, sort_order, source)
select '00000000-0000-0000-0000-00000000d001', id, m.label, m.amount, m.ord, 'seed:typical'
from ingredient i
join (values
  ('onion test',    'onion, medium', 110::numeric, 0),
  ('onion test',    'onion, large',  150::numeric, 1),
  ('broccoli test', 'spear',          31::numeric, 0),
  ('broccoli test', 'crown',         150::numeric, 1)
) as m(match_text, label, amount, ord) on m.match_text = i.match_text
where i.household_id = '00000000-0000-0000-0000-00000000d001';

-- ---------------------------------------------------------------------------
-- 3. The own-measure trigger: the one way this column could tell a lie.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update ingredient set default_measure_id = (
       select id from ingredient_measure
       where household_id = '00000000-0000-0000-0000-00000000d001'
         and label = 'spear')
     where household_id = '00000000-0000-0000-0000-00000000d001'
       and match_text = 'onion test' $$,
  'P0001',
  null,
  'a measure of ANOTHER ingredient is refused (a "1 onion" counted as a spear)'
);

select throws_ok(
  $$ update ingredient set default_measure_id = (
       select id from ingredient_measure
       where household_id = '00000000-0000-0000-0000-0000000000aa'
         and label = 'onion, medium'
       limit 1)
     where household_id = '00000000-0000-0000-0000-00000000d001'
       and match_text = 'onion test' $$,
  'P0001',
  null,
  'a measure of another HOUSEHOLD is refused'
);

-- ---------------------------------------------------------------------------
-- 4. The backfill: fills a null by label, per household; never overwrites.
-- ---------------------------------------------------------------------------
-- The household made its own call on the onion first — `onion, large`. The
-- curation says `onion, medium`, and must not win.
update ingredient set default_measure_id = (
  select id from ingredient_measure
  where household_id = '00000000-0000-0000-0000-00000000d001'
    and label = 'onion, large')
where household_id = '00000000-0000-0000-0000-00000000d001'
  and match_text = 'onion test';

-- A second household on the same vocabulary, with nothing chosen.
insert into household (id, name, backfilled_at)
values ('00000000-0000-0000-0000-00000000d002', 'Default 2 (test)', now());
insert into ingredient (household_id, canonical_name, default_unit, source, match_text)
values ('00000000-0000-0000-0000-00000000d002', 'Onion (test)', 'piece', 'seed', 'onion test');
insert into ingredient_measure (household_id, ingredient_id, label, basis_amount, sort_order, source)
select '00000000-0000-0000-0000-00000000d002', id, 'onion, medium', 110, 0, 'seed:typical'
from ingredient
where household_id = '00000000-0000-0000-0000-00000000d002' and match_text = 'onion test';

-- The fixtures use test match_texts the shipped curation does not name, so
-- the shipped list would fill nothing here. Stand in a curation of our own by
-- calling the same statement the function runs, against the same key.
create or replace function default_measure_backfill_fixture()
returns integer language plpgsql as $$
declare filled integer;
begin
  update ingredient i
     set default_measure_id = m.id,
         updated_at = now()
    from (values ('onion test', 'onion, medium'),
                 ('broccoli test', null)) as c(match_text, label),
         ingredient_measure m
   where i.match_text = c.match_text
     and i.deleted_at is null
     and i.default_measure_id is null
     and m.ingredient_id = i.id
     and m.household_id = i.household_id
     and m.deleted_at is null
     and lower(btrim(m.label)) = lower(btrim(c.label));
  get diagnostics filled = row_count;
  return filled;
end $$;

select is(
  default_measure_backfill_fixture(),
  1,
  'the backfill fills exactly the household that had chosen nothing'
);
select is(
  (select m.label from ingredient i join ingredient_measure m on m.id = i.default_measure_id
    where i.household_id = '00000000-0000-0000-0000-00000000d002'),
  'onion, medium',
  'a null default is filled from the curation, by measure label'
);
select is(
  (select m.label from ingredient i join ingredient_measure m on m.id = i.default_measure_id
    where i.household_id = '00000000-0000-0000-0000-00000000d001'
      and i.match_text = 'onion test'),
  'onion, large',
  'a household''s own choice is never overwritten (union, never replace)'
);
select is(
  (select default_measure_id from ingredient
    where household_id = '00000000-0000-0000-0000-00000000d001'
      and match_text = 'broccoli test'),
  null,
  'a `null` ruling writes nothing — the backfill never REMOVES either'
);
select is(
  default_measure_backfill_fixture(),
  0,
  'a second run is a no-op'
);

-- The shipped function is the same statement over the shipped list: on the
-- already-seeded template every curated row is filled, so it fills nothing.
select is(
  ingredient_default_measure_backfill(),
  0,
  'the shipped backfill is idempotent against the seeded template'
);

-- ---------------------------------------------------------------------------
-- 5. ON DELETE SET NULL — a hard-deleted measure clears the default.
-- ---------------------------------------------------------------------------
delete from ingredient_measure
where household_id = '00000000-0000-0000-0000-00000000d002' and label = 'onion, medium';
select is(
  (select default_measure_id from ingredient
    where household_id = '00000000-0000-0000-0000-00000000d002'),
  null,
  'hard-deleting the measure sets the default null rather than dangling it'
);

-- ---------------------------------------------------------------------------
-- 6. The seeded template carries the curation.
-- ---------------------------------------------------------------------------
select ok(
  (select count(*) from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and default_measure_id is not null) >= 130,
  'the seeded template carries the curated defaults (132 as of 2026-09-03)'
);

select is(
  (select count(*)::int from ingredient i
    join ingredient_measure m on m.id = i.default_measure_id
   where i.household_id = '00000000-0000-0000-0000-0000000000aa'
     and (m.ingredient_id <> i.id or m.household_id <> i.household_id
          or m.deleted_at is not null)),
  0,
  'every seeded default points at a live measure of its OWN row'
);

-- The nine fragment sets, BY NAME. Two or more KINDS of countable thing with
-- no dominant one: the flag stands and the user picks, which is ADR-0010's
-- own answer. Naming them is what stops a regenerated seed quietly ruling on
-- one of them.
select is(
  (select array_agg(i.match_text order by i.match_text) from ingredient i
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.deleted_at is null
      and i.default_measure_id is null
      and exists (select 1 from ingredient_measure m
                  where m.ingredient_id = i.id and m.deleted_at is null)),
  array['broccoli', 'cabbage', 'iceberg lettuce', 'mint', 'red cabbage',
        'red leaf lettuce', 'romaine lettuce', 'spinach', 'vegetable broth'],
  'exactly the nine fragment-set rows carry no default'
);

-- The counter-case one row down, and the argument for a curated fact over a
-- rule: `napa cabbage` carries a single `head` measure, so it DOES get a
-- default while plain `cabbage` (head vs leaf) gets none. Same food, two
-- answers, because the vocabulary differs.
select is(
  (select m.label from ingredient i join ingredient_measure m on m.id = i.default_measure_id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.match_text = 'napa cabbage'),
  'head',
  'napa cabbage (one measure) gets a default where cabbage (head vs leaf) does not'
);

-- The seed gap the pass turned up: `yellow bell pepper` carried only
-- `pepper, large` where the other three bells carry a 119 g medium, so the
-- medium is borrowed and the default lands on it.
select is(
  (select m.label || ' @ ' || m.basis_amount
     from ingredient i join ingredient_measure m on m.id = i.default_measure_id
    where i.household_id = '00000000-0000-0000-0000-0000000000aa'
      and i.match_text = 'yellow bell pepper'),
  'pepper, medium @ 119',
  'yellow bell pepper counts as the borrowed 119 g medium, like the other bells'
);

-- ---------------------------------------------------------------------------
-- 7. The onboarding clone carries the default across, BY LABEL.
-- ---------------------------------------------------------------------------
-- Both fixture households have empty seats, and `ensure_onboarded()` fills an
-- open seat before it ever clones. Tombstone them so the user below takes the
-- create path; their assertions are all above this line.
update household set deleted_at = now()
where id in ('00000000-0000-0000-0000-00000000d001',
             '00000000-0000-0000-0000-00000000d002');

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000',
  'df111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated',
  'dm@x.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"df111111-1111-1111-1111-111111111111","role":"authenticated","email":"dm@x.com"}';
select isnt(ensure_onboarded(), '00000000-0000-0000-0000-0000000000aa'::uuid,
  'the clone user gets a fresh household');
reset role;

do $$ begin
  perform set_config('test.hh_dm',
    (select household_id::text from household_member
      where auth_user_id = 'df111111-1111-1111-1111-111111111111'), true);
end $$;

select is(
  (select m.label from ingredient i join ingredient_measure m on m.id = i.default_measure_id
    where i.household_id = current_setting('test.hh_dm')::uuid
      and i.match_text = 'onion'),
  'onion, medium',
  'a cloned household counts "2 onions" as the template does'
);
select is(
  (select count(*)::int from ingredient i
    join ingredient_measure m on m.id = i.default_measure_id
   where i.household_id = current_setting('test.hh_dm')::uuid
     and (m.ingredient_id <> i.id or m.household_id <> i.household_id)),
  0,
  'the clone re-keys onto its OWN measure rows, never the template''s'
);
select is(
  (select count(*)::int from ingredient
    where household_id = current_setting('test.hh_dm')::uuid
      and deleted_at is null and default_measure_id is not null),
  (select count(*)::int from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null and default_measure_id is not null),
  'every curated default crosses — none is lost to a label mismatch'
);
select is(
  (select default_measure_id from ingredient
    where household_id = current_setting('test.hh_dm')::uuid
      and match_text = 'broccoli'),
  null,
  'a fragment set arrives with no default, exactly as the template holds it'
);

select finish();
rollback;
