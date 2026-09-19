-- pgTAP: household isolation + usda_food server-only (docs/SECURITY.md).
--
-- RLS keeps one household out of another's rows, and usda_food never reaches a
-- client role. Data-driven: `iso_case` lists EVERY household-scoped table with
-- a cross-household insert to reject, and the assertions fan out over it — a
-- new table costs one setup row + one case row (do add it: the sync rules in
-- docker/powersync.yaml mirror exactly these boundaries). Run by
-- `supabase test db`.

begin;
-- 17 tables x (select isolation + cross-household insert rejection)
-- + current_household_id + 4 recipe.favorite checks + 2 usda_food checks
-- + 2 household column-grant checks + 4 usda_search_* denials.
select plan(47);

-- Two households, one member each, and one row per household in every
-- household-scoped table (A-side ids aaaaaaaa-…, B-side bbbbbbbb-…).
insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','a@x.com'),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','b@x.com');
insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');
insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','B1','22222222-2222-2222-2222-222222222222');
insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Flour','g','flour'),
 ('bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Sugar','g','sugar');
insert into ingredient_alias (household_id, ingredient_id, alias_text, match_text, source) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000001','plain flour','plain flour','manual'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000001','caster sugar','caster sugar','manual');
insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000011','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000001','bag',1000),
 ('bbbbbbbb-0000-0000-0000-000000000011','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000001','bag',500);
insert into book (id, household_id, name) values
 ('aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Book A'),
 ('bbbbbbbb-0000-0000-0000-000000000002','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Book B');
insert into book_section (id, household_id, book_id, name) values
 ('aaaaaaaa-0000-0000-0000-000000000003','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000002','Weeknight'),
 ('bbbbbbbb-0000-0000-0000-000000000003','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000002','Weeknight');
insert into recipe (id, household_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Bread A'),
 ('bbbbbbbb-0000-0000-0000-000000000004','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Bread B');
insert into ingredient_group (id, household_id, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000005','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000004'),
 ('bbbbbbbb-0000-0000-0000-000000000005','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000004');
insert into recipe_line_item (id, household_id, group_id, ingredient_id, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000006','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000001','g'),
 ('bbbbbbbb-0000-0000-0000-000000000006','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000005','bbbbbbbb-0000-0000-0000-000000000001','g');
insert into recipe_measure (id, household_id, recipe_id, label, per_batch) values
 ('aaaaaaaa-0000-0000-0000-000000000014','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000004','loaf',1),
 ('bbbbbbbb-0000-0000-0000-000000000014','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000004','roll',12);
insert into week_plan (id, household_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-000000000007','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-01-05'),
 ('bbbbbbbb-0000-0000-0000-000000000007','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','2026-01-05');
insert into plan_entry (id, household_id, week_plan_id, day_of_week, meal_slot, recipe_id) values
 ('aaaaaaaa-0000-0000-0000-000000000008','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000007',0,'Dinner','aaaaaaaa-0000-0000-0000-000000000004'),
 ('bbbbbbbb-0000-0000-0000-000000000008','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000007',0,'Dinner','bbbbbbbb-0000-0000-0000-000000000004');
insert into shopping_list_entry (id, household_id, ingredient_id) values
 ('aaaaaaaa-0000-0000-0000-000000000009','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000001'),
 ('bbbbbbbb-0000-0000-0000-000000000009','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000001');
insert into shopping_list_contribution (id, household_id, entry_id, quantity, unit) values
 ('aaaaaaaa-0000-0000-0000-000000000010','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000009',1,'g'),
 ('bbbbbbbb-0000-0000-0000-000000000010','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000009',1,'g');
insert into receipt (id, household_id, store, purchased_at, source) values
 ('aaaaaaaa-0000-0000-0000-000000000012','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','TJ''s','2026-01-06T10:00:00Z','manual'),
 ('bbbbbbbb-0000-0000-0000-000000000012','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Whole Foods','2026-01-06T10:00:00Z','manual');
insert into receipt_line (id, household_id, receipt_id, ingredient_id, cents, kind, pack_basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000013','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000012','aaaaaaaa-0000-0000-0000-000000000001',349,'item',454),
 ('bbbbbbbb-0000-0000-0000-000000000013','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000012','bbbbbbbb-0000-0000-0000-000000000001',329,'item',454);
insert into usda_food (fdc_id, description, match_text) values
 (1,'Flour, all purpose','flour all purpose');

-- The cases: every household-scoped table, with the cross-household insert A
-- will attempt (targeting House B, using B's own FK rows so ONLY the household
-- boundary can reject it). household / household_member have no client insert
-- path at all — no grant, no policy — so they fail on the grant, not RLS.
create table iso_case (ord int primary key, tbl text, cross_insert text, errmsg text);
insert into iso_case values
 (1,  'household',
      $$ insert into household (name) values ('Intruder House') $$,
      'permission denied for table household'),
 (2,  'household_member',
      $$ insert into household_member (household_id, display_name, auth_user_id)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Intruder','11111111-1111-1111-1111-111111111111') $$,
      'permission denied for table household_member'),
 (3,  'ingredient',
      $$ insert into ingredient (household_id, canonical_name, default_unit, match_text)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Contraband','g','contraband') $$,
      'new row violates row-level security policy for table "ingredient"'),
 (4,  'ingredient_alias',
      $$ insert into ingredient_alias (household_id, ingredient_id, alias_text, match_text, source)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000001','x','x','manual') $$,
      'new row violates row-level security policy for table "ingredient_alias"'),
 (5,  'book',
      $$ insert into book (household_id, name)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Contraband Book') $$,
      'new row violates row-level security policy for table "book"'),
 (6,  'book_section',
      $$ insert into book_section (household_id, book_id, name)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000002','x') $$,
      'new row violates row-level security policy for table "book_section"'),
 (7,  'recipe',
      $$ insert into recipe (household_id, title)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Contraband Bread') $$,
      'new row violates row-level security policy for table "recipe"'),
 (8,  'ingredient_group',
      $$ insert into ingredient_group (household_id, recipe_id)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000004') $$,
      'new row violates row-level security policy for table "ingredient_group"'),
 (9,  'recipe_line_item',
      $$ insert into recipe_line_item (household_id, group_id, ingredient_id, unit)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000005','bbbbbbbb-0000-0000-0000-000000000001','g') $$,
      'new row violates row-level security policy for table "recipe_line_item"'),
 (10, 'week_plan',
      $$ insert into week_plan (household_id, week_start_date)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','2026-01-12') $$,
      'new row violates row-level security policy for table "week_plan"'),
 (11, 'plan_entry',
      $$ insert into plan_entry (household_id, week_plan_id, day_of_week, meal_slot, recipe_id)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000007',1,'Lunch','bbbbbbbb-0000-0000-0000-000000000004') $$,
      'new row violates row-level security policy for table "plan_entry"'),
 (12, 'shopping_list_entry',
      $$ insert into shopping_list_entry (household_id, free_text)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','paper towels') $$,
      'new row violates row-level security policy for table "shopping_list_entry"'),
 (13, 'shopping_list_contribution',
      $$ insert into shopping_list_contribution (household_id, entry_id, quantity, unit)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000009',1,'g') $$,
      'new row violates row-level security policy for table "shopping_list_contribution"'),
 (14, 'ingredient_measure',
      $$ insert into ingredient_measure (household_id, ingredient_id, label, basis_amount)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000001','sack',2000) $$,
      'new row violates row-level security policy for table "ingredient_measure"'),
 (15, 'receipt',
      $$ insert into receipt (household_id, store, purchased_at, source)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Contraband Market','2026-01-07T10:00:00Z','manual') $$,
      'new row violates row-level security policy for table "receipt"'),
 (16, 'receipt_line',
      $$ insert into receipt_line (household_id, receipt_id, ingredient_id, cents, kind)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000012','bbbbbbbb-0000-0000-0000-000000000001',199,'item') $$,
      'new row violates row-level security policy for table "receipt_line"'),
 (17, 'recipe_measure',
      $$ insert into recipe_measure (household_id, recipe_id, label, per_batch)
         values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000004','contraband',4) $$,
      'new row violates row-level security policy for table "recipe_measure"');
grant select on iso_case to authenticated;

-- Row-count helper. Invoker rights, so when called as `authenticated` the
-- count is what RLS lets that role see. Rolled back with everything else.
create function iso_visible_rows(tbl text) returns int
language plpgsql as $fn$
declare n int;
begin
  execute format('select count(*) from %I', tbl) into n;
  return n;
end
$fn$;
grant execute on function iso_visible_rows(text) to authenticated;

-- Act as authenticated user A.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  current_household_id(),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'current_household_id() resolves A from membership'
);

-- Select isolation: exactly one visible row per table — A's own. (Seeded
-- template rows don't count either: the template household has no members.)
select is(
  iso_visible_rows(tbl), 1,
  tbl || ': A sees exactly one row — its own (RLS filters everything else)'
) from iso_case order by ord;

-- Write isolation: A cannot insert into House B (nor create households or
-- memberships at all — those are onboarding-only, SECURITY DEFINER paths).
select throws_ok(cross_insert, '42501', errmsg,
  tbl || ': cross-household insert is rejected'
) from iso_case order by ord;

-- recipe.favorite (0011) is client-writable through the existing recipe
-- update policy — the app's Favorites star writes it directly…
select lives_ok(
  $$ update recipe set favorite = true
     where id = 'aaaaaaaa-0000-0000-0000-000000000004' $$,
  'A can favorite their own recipe (0011)'
);
select is(
  (select favorite from recipe
     where id = 'aaaaaaaa-0000-0000-0000-000000000004'),
  true,
  'the favorite flag round-trips'
);
-- …and RLS keeps A's stars off B's recipes: the update runs without error
-- but matches no rows (verified from outside RLS further down).
select lives_ok(
  $$ update recipe set favorite = true
     where id = 'bbbbbbbb-0000-0000-0000-000000000004' $$,
  'favoriting another household''s recipe does not error (RLS filters it)'
);

-- The household column grants (0008). `authenticated` may rename its own
-- household and soft-delete it, and nothing else: a household that could flip
-- its own `is_template` would become the clone source every future onboarder
-- copies from, and one that could rewrite its `id` could walk into another's
-- rows. Both are refused by the column grant, not by RLS, so they raise 42501
-- rather than filtering to zero rows — which is why they need naming here: a
-- single later `grant update on household` reopens both in silence.
select throws_ok(
  $$ update household set is_template = true
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '42501',
  'permission denied for table household',
  'a household cannot mark itself a template (the onboarding clone source)'
);
select throws_ok(
  $$ update household set id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '42501',
  'permission denied for table household',
  'a household cannot rewrite its own id'
);

-- usda_food is server-side only (ADR-0005): denied to clients…
select throws_ok(
  $$ select count(*) from usda_food $$,
  '42501',
  'permission denied for table usda_food',
  'usda_food is denied to the authenticated (client) role'
);

-- …and so is the search index derived from it (0029, RLS added in 0030): same
-- reference set in a different shape, so the same posture — no grant, no
-- policy, reached only through the security-definer probe.
select throws_ok(
  format('select count(*) from %I', tbl),
  '42501',
  'permission denied for table ' || tbl,
  tbl || ' is denied to the authenticated (client) role'
) from (values ('usda_search_doc'), ('usda_search_stats'),
               ('usda_search_term'), ('usda_search_token')) as s(tbl)
  order by tbl;

-- …but reachable server-side.
reset role;
-- Seen from outside RLS: A's cross-household favorite update matched no rows.
select is(
  (select favorite from recipe
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'),
  false,
  'the cross-household favorite never landed (RLS matched no rows)'
);
set local role service_role;
select is(
  (select count(*) from usda_food where fdc_id = 1)::int, 1,
  'service_role can read usda_food'
);

select * from finish();
rollback;
