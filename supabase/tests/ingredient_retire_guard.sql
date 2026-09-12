-- pgTAP: an ingredient is retired only when nothing live names it, and what
-- is already broken is re-pointed (0041).
--
-- The incident: a hand statement on cloud retired a duplicate `sauerkraut`
-- row and left the one live `recipe_line_item` that named it pointing at a
-- tombstone. What is defended here:
--
--   * the REFUSAL — a row cannot gain a `deleted_at` while a live recipe
--     line, a live bare-ingredient meal (0033) or a live week override
--     (0040) names it, and the message carries the count;
--   * the WAY OUT — the same retire succeeds the moment the line is
--     re-pointed, or removed;
--   * the REACH — the guard counts exactly what the app's own delete door
--     counts, so a line inside a tombstoned recipe (unreachable, and
--     therefore not the app's business either) does not block a retire. A
--     server that refused more than the client checks would leave an upload
--     the sync queue can never drain;
--   * the REPAIR — a live line at a retired row is re-pointed to the single
--     live row of the same `(household_id, match_text)`, and a line with no
--     single live twin is left alone and counted rather than guessed at.
--
-- Run by `supabase test db`.

begin;
select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures: one household, a duplicate vocab pair, a recipe, a week.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','retire-a@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111');

-- 301 is the row a line names; 302 is an unrelated row to re-point onto.
insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000301','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sauerkraut','g','sauerkraut'),
 ('aaaaaaaa-0000-0000-0000-000000000302','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Kimchi','g','kimchi');

insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Smashed Edamame Toast'),
 ('aaaaaaaa-0000-0000-0000-000000000102','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A Retired Recipe');

insert into ingredient_group (id, household_id, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000101'),
 ('aaaaaaaa-0000-0000-0000-000000000602','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000102');

insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-09-14');

-- ---------------------------------------------------------------------------
-- 1 · A recipe line refuses the retire, by the count.
-- ---------------------------------------------------------------------------
--
-- The incident's exact line: live, `to_taste`, no quantity.
insert into recipe_line_item (id, household_id, group_id, ingredient_id, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000701','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000301','to_taste');

select is(
  ingredient_live_line_uses('aaaaaaaa-0000-0000-0000-000000000301'),
  1::bigint,
  'one live recipe line names the row'
);

select throws_ok(
  $$ update ingredient set deleted_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000301' $$,
  '23503',
  'retire refused: 1 live line still uses this ingredient; re-point it first',
  'the statement that caused the incident is now refused, and says why'
);

-- The count is the message: two lines read as two, and the sentence agrees
-- with itself.
insert into recipe_line_item (id, household_id, group_id, ingredient_id, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000702','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000301',50,'g');

select throws_ok(
  $$ update ingredient set deleted_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000301' $$,
  '23503',
  'retire refused: 2 live lines still use this ingredient; re-point them first',
  'the refusal names the count, in the plural it has earned'
);

-- An edit that is not a retire is untouched — the guard is about one column
-- going from null to a time, not about writing to the row at all.
select lives_ok(
  $$ update ingredient set canonical_name = 'Sauerkraut, jarred'
     where id = 'aaaaaaaa-0000-0000-0000-000000000301' $$,
  'a rename is not a retire'
);

-- ---------------------------------------------------------------------------
-- 2 · The two ways out: re-point the line, or remove it.
-- ---------------------------------------------------------------------------

update recipe_line_item
   set ingredient_id = 'aaaaaaaa-0000-0000-0000-000000000302'
 where id = 'aaaaaaaa-0000-0000-0000-000000000702';

update recipe_line_item set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000701';

select is(
  ingredient_live_line_uses('aaaaaaaa-0000-0000-0000-000000000301'),
  0::bigint,
  'a re-pointed line and a removed line both stop counting'
);

select lives_ok(
  $$ update ingredient set deleted_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000301' $$,
  'the retire goes through once nothing live names the row'
);

-- Retiring an already-retired row is not a second retire: the WHEN clause
-- fires on null → not-null only, so a reseed re-touching a tombstone is
-- never refused.
insert into recipe_line_item (id, household_id, group_id, ingredient_id, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000703','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000301','to_taste');

select lives_ok(
  $$ update ingredient set deleted_at = now(), updated_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000301' $$,
  'a row that is already retired can be re-stamped'
);

update recipe_line_item set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000703';

-- ---------------------------------------------------------------------------
-- 3 · The other two carriers of an ingredient_id, each on its own.
-- ---------------------------------------------------------------------------
--
-- The re-pointed recipe line is cleared first, so each count below is about
-- one carrier and the refusal cannot be read as the recipe line's.
update recipe_line_item set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000702';

insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, ingredient_id, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000901','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201',2,'snack','aaaaaaaa-0000-0000-0000-000000000302',1,'piece');

select throws_ok(
  $$ update ingredient set deleted_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000302' $$,
  '23503',
  'retire refused: 1 live line still uses this ingredient; re-point it first',
  'a bare-ingredient meal is a line too (0033) — the week loses the meal '
  'silently otherwise'
);

update plan_entry set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000901';

insert into week_recipe_line_override
  (id, household_id, week_plan_id, recipe_id, recipe_line_item_id, action,
   ingredient_id, quantity, unit)
values
 ('aaaaaaaa-0000-0000-0000-000000000801','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000702','replace','aaaaaaaa-0000-0000-0000-000000000302',60,'g');

select throws_ok(
  $$ update ingredient set deleted_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000302' $$,
  '23503',
  'retire refused: 1 live line still uses this ingredient; re-point it first',
  'a this-week swap is a line too (0040) — the variant reads as the recipe '
  'again otherwise'
);

update week_recipe_line_override set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000801';

-- ---------------------------------------------------------------------------
-- 4 · Reach: unreachable lines do not block, because the app cannot see them.
-- ---------------------------------------------------------------------------

update recipe set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000102';

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000303','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Nori','g','nori');

insert into recipe_line_item (id, household_id, group_id, ingredient_id, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000704','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000602','aaaaaaaa-0000-0000-0000-000000000303','g');

select is(
  ingredient_live_line_uses('aaaaaaaa-0000-0000-0000-000000000303'),
  0::bigint,
  'a line in a tombstoned recipe belongs to nothing a user can open'
);

select lives_ok(
  $$ update ingredient set deleted_at = now()
     where id = 'aaaaaaaa-0000-0000-0000-000000000303' $$,
  'so it does not block the retire — the server refuses exactly what the '
  'app refuses'
);

-- ---------------------------------------------------------------------------
-- 5 · The repair: the incident's own shape, re-pointed.
-- ---------------------------------------------------------------------------
--
-- The broken pair is seeded the way it arose: a duplicate row created by an
-- import, retired, with a live line left pointing at it. Retired rows are
-- INSERTed already-retired here, because the guard above is precisely what
-- makes this state unreachable through an UPDATE now.
--
-- The unreachable line from section 4 is cleared first, so the two counts
-- below are about this section's rows and nothing else.
update recipe_line_item set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000704';
insert into ingredient (id, household_id, canonical_name, default_unit, match_text, deleted_at) values
 ('aaaaaaaa-0000-0000-0000-000000000311','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sauerkraut','g','sauerkraut',now());

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000312','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sauerkraut','g','sauerkraut');

insert into recipe_line_item (id, household_id, group_id, ingredient_id, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000711','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000311','to_taste');

insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, ingredient_id, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000911','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201',3,'snack','aaaaaaaa-0000-0000-0000-000000000311',1,'piece');

-- …and a line this week's variant added, so all three carriers are repaired
-- by the one statement rather than two of them and a hope.
insert into week_recipe_line_override
  (id, household_id, week_plan_id, recipe_id, action, ingredient_id,
   quantity, unit)
values
 ('aaaaaaaa-0000-0000-0000-000000000811','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-0000-0000-0000-000000000101','add','aaaaaaaa-0000-0000-0000-000000000311',1,'g');

-- A second broken line with NO live twin at all: nothing to infer, so the
-- repair must leave it and say so.
insert into ingredient (id, household_id, canonical_name, default_unit, match_text, deleted_at) values
 ('aaaaaaaa-0000-0000-0000-000000000313','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Yuzu Kosho','g','yuzu kosho',now());

insert into recipe_line_item (id, household_id, group_id, ingredient_id, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000712','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000601','aaaaaaaa-0000-0000-0000-000000000313','tsp');

select results_eq(
  $$ select repointed, stranded from repair_lines_at_retired_ingredients() $$,
  $$ values (3::bigint, 1::bigint) $$,
  'all three carriers re-pointed onto the single live twin; the one line '
  'with no twin is left and counted'
);

select is(
  (select ingredient_id from recipe_line_item
    where id = 'aaaaaaaa-0000-0000-0000-000000000711'),
  'aaaaaaaa-0000-0000-0000-000000000312'::uuid,
  'the recipe line now names the row that survived the de-duplication'
);

select is(
  (select ingredient_id from plan_entry
    where id = 'aaaaaaaa-0000-0000-0000-000000000911'),
  'aaaaaaaa-0000-0000-0000-000000000312'::uuid,
  'and so does the bare-ingredient meal'
);

select is(
  (select ingredient_id from week_recipe_line_override
    where id = 'aaaaaaaa-0000-0000-0000-000000000811'),
  'aaaaaaaa-0000-0000-0000-000000000312'::uuid,
  'and so does the line this week added'
);

select is(
  (select ingredient_id from recipe_line_item
    where id = 'aaaaaaaa-0000-0000-0000-000000000712'),
  'aaaaaaaa-0000-0000-0000-000000000313'::uuid,
  'a line with no live twin keeps its id — guessing is not repairing'
);

-- Idempotent: run again and only the stranded line is still reported.
select results_eq(
  $$ select repointed, stranded from repair_lines_at_retired_ingredients() $$,
  $$ values (0::bigint, 1::bigint) $$,
  'a second run re-points nothing — the repair is safe to re-run'
);

-- Two live twins is ambiguity, not a repair: the line is left for a person.
insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000314','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Yuzu Kosho','g','yuzu kosho'),
 ('aaaaaaaa-0000-0000-0000-000000000315','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Yuzu Kosho (red)','g','yuzu kosho');

select results_eq(
  $$ select repointed, stranded from repair_lines_at_retired_ingredients() $$,
  $$ values (0::bigint, 1::bigint) $$,
  'two live candidates leave the line exactly where it was'
);

select finish();
rollback;
