-- pgTAP: ingredient.source_edited (0034, exec plan 0040 front B).
--
-- The column is the row's answer to "are these numbers still the source's?".
-- Two things are pinned here, and they are the two ways it could quietly stop
-- being true:
--
--   * **It round-trips.** A row that never heard of the flag reads `false` —
--     every pre-0034 row is, correctly, un-edited — and a row the app flags
--     reads `true` back, so the client's one write is the whole mechanism.
--   * **Nothing on the server sets or clears it.** B-D1's fence says only a
--     write that touches macros, basis or density may set it; a rename does
--     not contradict the source. There is deliberately no trigger, so this is
--     the guard against a later migration adding one — the same shape of guard
--     `usda_search.sql` keeps over the prefill trigger 0029 removed.
--
-- Run by `supabase test db`.

begin;
select plan(9);

-- --------------------------------------------------------------------------
-- The column, as declared.
-- --------------------------------------------------------------------------

select has_column('public', 'ingredient', 'source_edited',
  'ingredient carries source_edited');
select col_type_is('public', 'ingredient', 'source_edited', 'boolean',
  'source_edited is a boolean, not a string state machine on source');
select col_not_null('public', 'ingredient', 'source_edited',
  'source_edited is never null — a row always answers the question');
select col_default_is('public', 'ingredient', 'source_edited', 'false',
  'it defaults to false: a row nobody edited is not edited');

-- No trigger may own this fact. The app's three write paths do.
select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'ingredient'::regclass
      and not tgisinternal
      and pg_get_triggerdef(oid) ilike '%source_edited%'),
  0,
  'no trigger writes source_edited');

insert into household (id, name) values
 ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Edited House');

-- A row filled from USDA, exactly as `applyUsdaPick` + Save leaves one.
insert into ingredient
  (id, household_id, canonical_name, match_text, status, default_unit,
   source, source_label, source_score, density_g_per_ml, macros)
values
  ('eeeeeeee-0000-0000-0000-000000000001','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   'Chex Cereal','chex cereal','stub','g',
   'usda_fdc:168930','Cereals ready-to-eat, GENERAL MILLS, Corn CHEX',0.91,
   0.13,'{"kcal":379,"protein":7.1,"carb":84,"fat":2.5}'::jsonb);

-- --------------------------------------------------------------------------
-- Round-trip.
-- --------------------------------------------------------------------------

select is(
  (select source_edited from ingredient
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  false,
  'a freshly filled row is not edited');

-- What the app writes when a human types their own density over the prefill.
update ingredient set source_edited = true, density_g_per_ml = 0.2
  where id = 'eeeeeeee-0000-0000-0000-000000000001';

select is(
  (select source_edited from ingredient
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  true,
  'the flag round-trips: the row says its numbers are its owner''s now');

-- --------------------------------------------------------------------------
-- A rename does not touch it, in either direction.
-- --------------------------------------------------------------------------

update ingredient
   set canonical_name = 'Corn Chex', match_text = 'corn chex'
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select is(
  (select source_edited from ingredient
    where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  true,
  'a rename does not clear the flag — the numbers did not change');

-- ... and on an un-edited row it does not set it either. A second row, so the
-- assertion is about the rename and not about the update above.
insert into ingredient
  (id, household_id, canonical_name, match_text, status, default_unit,
   source, source_label, source_score, macros)
values
  ('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   'Kale','kale','stub','g',
   'usda_fdc:168421','Kale, raw',0.88,
   '{"kcal":35,"protein":2.9,"carb":4.4,"fat":1.5}'::jsonb);

update ingredient
   set canonical_name = 'Curly Kale', match_text = 'curly kale'
 where id = 'eeeeeeee-0000-0000-0000-000000000002';

select is(
  (select source_edited from ingredient
    where id = 'eeeeeeee-0000-0000-0000-000000000002'),
  false,
  'renaming a USDA-filled row does NOT flag it as edited (B-D1''s fence)');

select * from finish();
rollback;
