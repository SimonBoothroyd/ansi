-- pgTAP: the USDA search (0029, plan 0029's server half).
--
-- Three things this pins, all of which were broken or absent before 0029:
--
--   * **Nothing matches silently.** The `ingredient_usda_prefill` trigger is
--     gone, so a bare stub stays bare. This is the whole point of the change
--     — a USDA fill now has a human pick in the middle of it — and a trigger
--     is exactly the kind of thing a later migration re-adds by accident.
--   * **The search answers.** The trigram probe it replaced returned NOTHING
--     for 97 of the 267 curated vocabulary names, `apple` among them. These
--     assertions are the regression guard on that.
--   * **The index is not optional.** A probe over an unbuilt index must raise,
--     not return an empty short-list — an empty sheet is indistinguishable
--     from "no such food", which is the silent failure this plan removes.
--
-- Run by `supabase test db`. Assumes the seeded reference set (seed_usda.sql
-- + seed_usda_index.sql).

begin;
select plan(11);

-- --------------------------------------------------------------------------
-- The silent prefill is gone.
-- --------------------------------------------------------------------------

select hasnt_function('public', 'ingredient_prefill_from_usda', '{}',
  'the prefill trigger function is dropped (0029)');

select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'ingredient'::regclass and tgname = 'ingredient_usda_prefill'),
  0,
  'no ingredient_usda_prefill trigger survives');

insert into household (id, name) values
 ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Search House');

-- A name that matched the old probe at similarity 1.0 and was silently
-- filled: `Broccoli, raw` / `broccoli raw`. It must now stay untouched.
insert into ingredient
  (id, household_id, canonical_name, match_text, status, source, category, default_unit)
values
  ('dddddddd-0000-0000-0000-000000000001','dddddddd-dddd-dddd-dddd-dddddddddddd',
   'Broccoli Raw','broccoli raw','stub','manual','produce','g');

select is(
  (select source from ingredient where id='dddddddd-0000-0000-0000-000000000001'),
  'manual',
  'a bare stub is not stamped by anything on insert');

select ok(
  (select density_g_per_ml is null and macros is null and source_label is null
     from ingredient where id='dddddddd-0000-0000-0000-000000000001'),
  'a bare stub is not filled on insert');

-- ... and a rename does not re-match it either (the old trigger fired on
-- `UPDATE OF canonical_name`, so renaming a stub silently re-probed it).
update ingredient set canonical_name = 'Kale', match_text = 'kale'
 where id='dddddddd-0000-0000-0000-000000000001';

select ok(
  (select density_g_per_ml is null and macros is null and source = 'manual'
     from ingredient where id='dddddddd-0000-0000-0000-000000000001'),
  'a rename does not re-match the row');

-- --------------------------------------------------------------------------
-- The search answers.
-- --------------------------------------------------------------------------

select cmp_ok(
  (select count(*)::int from probe_usda('apple', 5)), '=', 5,
  'a one-word query returns a full short-list (the trigram probe returned none)');

select is(
  (select description from probe_usda('kale', 1)),
  'Kale, raw',
  'kale finds the raw leaf, not a cooked or frozen variant');

-- The head-noun bonus and the processed-form penalty, each on the example
-- that motivated it.
select is(
  (select description from probe_usda('banana', 1)),
  'Bananas, raw',
  'a bare name prefers the raw form over "Bananas, dehydrated, or banana powder"');

select ok(
  (select description from probe_usda('black rice', 1)) like 'Rice, black%',
  'the head noun outranks rows that merely mention the word');

-- Reported score is the confidence figure ingredient.source_score stores
-- (0027), so it must stay inside the 0..1 the band word reads.
select ok(
  (select bool_and(score >= 0 and score <= 1) from probe_usda('olive oil', 10)),
  'the reported score stays on 0..1 for ingredient.source_score');

-- --------------------------------------------------------------------------
-- The index is not optional.
-- --------------------------------------------------------------------------

truncate usda_search_stats;
select throws_ok(
  $$ select * from probe_usda('apple', 5) $$,
  null,
  null,
  'an unbuilt index raises rather than returning an empty short-list');

select * from finish();
rollback;
