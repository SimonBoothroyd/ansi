-- pgTAP: the template vocab is reseedable (migration 0020).
--
-- Defends: the two TEMPLATE-ONLY unique indexes exist and bite (a second live
-- template row for a match_text is refused; a second live alias for one
-- template ingredient is refused) — and, load-bearing the other way, that a
-- HOUSEHOLD can still hold two live rows with the same match_text, because two
-- offline devices may each mint the same stub and both uploads must land
-- (the 0006 shopping-entry precedent). After the seed, the template holds
-- exactly one live row per match_text.
begin;
select plan(7);

select has_index('public', 'ingredient', 'ingredient_template_match_text_uq',
  '0020: the template match_text unique index exists');
select has_index('public', 'ingredient_alias', 'ingredient_alias_template_uq',
  '0020: the template alias unique index exists');

select is(
  (select count(*) - count(distinct match_text) from ingredient
    where household_id = '00000000-0000-0000-0000-0000000000aa'
      and deleted_at is null),
  0::bigint,
  'the seeded template has one live row per match_text');

-- A duplicate live template ingredient is refused.
select throws_ok($$
  insert into ingredient (household_id, canonical_name, default_unit, status, source, match_text)
  values ('00000000-0000-0000-0000-0000000000aa', 'Olive Oil again', 'tbsp', 'stub', 'seed', 'olive oil')
$$, '23505', null, 'a second live template row for a match_text is refused');

-- A tombstoned duplicate is fine (the index is partial on deleted_at).
select lives_ok($$
  insert into ingredient (household_id, canonical_name, default_unit, status, source, match_text, deleted_at)
  values ('00000000-0000-0000-0000-0000000000aa', 'Olive Oil (dead)', 'tbsp', 'stub', 'seed', 'olive oil', now())
$$, 'a tombstoned duplicate in the template is allowed');

-- A HOUSEHOLD may hold two live rows with one match_text (offline devices).
insert into household (id, name) values ('00000000-0000-0000-0000-00000000c0de', 'Two phones');
select lives_ok($$
  insert into ingredient (household_id, canonical_name, default_unit, status, source, match_text)
  values ('00000000-0000-0000-0000-00000000c0de', 'Tofu', 'g', 'stub', 'manual', 'tofu'),
         ('00000000-0000-0000-0000-00000000c0de', 'Tofu', 'g', 'stub', 'manual', 'tofu')
$$, 'a household can hold two live rows with the same match_text — the index is template-only');

-- A duplicate live template alias is refused.
select throws_ok($$
  insert into ingredient_alias (household_id, ingredient_id, alias_text, match_text, source)
  select '00000000-0000-0000-0000-0000000000aa', i.id, 'x', a.match_text, 'seed'
    from ingredient_alias a join ingredient i on i.id = a.ingredient_id
   where a.household_id = '00000000-0000-0000-0000-0000000000aa' and a.deleted_at is null
   limit 1
$$, '23505', null, 'a second live template alias for one ingredient is refused');

select * from finish();
rollback;
