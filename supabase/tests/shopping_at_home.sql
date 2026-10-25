-- pgTAP: what is already at home (0058, exec plan 0055).
--
-- The amount sits on the entry: positive, with a unit, on an ingredient entry
-- only, and a measure never stands without an amount. Run by
-- `supabase test db`.

begin;
select plan(8);

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');
insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-0000000005a1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Onion','piece','onion');
insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('aaaaaaaa-0000-0000-0000-0000000005a2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000005a1','onion, medium',110);
insert into shopping_list_entry (id, household_id, ingredient_id, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-0000000006a1','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-0000000005a1','2026-10-19');
insert into shopping_list_entry (id, household_id, free_text, week_start_date) values
 ('aaaaaaaa-0000-0000-0000-0000000006a2','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Paper towels','2026-10-19');

select has_column('shopping_list_entry', 'at_home_quantity', 'the entry carries an amount at home');
select has_column('shopping_list_entry', 'at_home_measure_id', 'and the measure it was counted in');

select is(
  (select at_home_quantity from shopping_list_entry where id = 'aaaaaaaa-0000-0000-0000-0000000006a1'),
  null,
  'nothing is at home until somebody says so'
);

select lives_ok(
  $$ update shopping_list_entry
        set at_home_quantity = 2, at_home_unit = 'piece',
            at_home_measure_id = 'aaaaaaaa-0000-0000-0000-0000000005a2'
      where id = 'aaaaaaaa-0000-0000-0000-0000000006a1' $$,
  'an ingredient entry takes an amount counted in its measure'
);

select throws_ok(
  $$ update shopping_list_entry set at_home_quantity = 0
      where id = 'aaaaaaaa-0000-0000-0000-0000000006a1' $$,
  '23514', null,
  'a zero amount is refused — nothing at home is null, not 0'
);

select throws_ok(
  $$ update shopping_list_entry set at_home_unit = null
      where id = 'aaaaaaaa-0000-0000-0000-0000000006a1' $$,
  '23514', null,
  'an amount without a unit is refused'
);

select throws_ok(
  $$ update shopping_list_entry set at_home_quantity = 1, at_home_unit = 'piece'
      where id = 'aaaaaaaa-0000-0000-0000-0000000006a2' $$,
  '23514', null,
  'a free-text item cannot be at home — it has no need to take it from'
);

select throws_ok(
  $$ update shopping_list_entry
        set at_home_quantity = null, at_home_unit = null
      where id = 'aaaaaaaa-0000-0000-0000-0000000006a1' $$,
  '23514', null,
  'a measure never stands without an amount — clearing clears all three'
);

select * from finish();
rollback;
