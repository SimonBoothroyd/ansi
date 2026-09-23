-- pgTAP: a row's base price (0051) and the store it is paid at (0052).
--
-- A price typed on an ingredient page lives on the row, not on a receipt.
-- What is defended here:
--
--   * the SHAPE — the six columns exist and are nullable, so a build that
--     predates them writes an ingredient exactly as before;
--   * the WHOLE — cents, the basis pack and the date travel together, a pack
--     unit needs an amount, and neither the cents nor either pack amount can
--     be zero;
--   * the STORE — optional, and only on a row that states a base price;
--   * the WORDS — the pack as entered and the basis figure may disagree, as
--     a receipt line's may (0046);
--   * the OLD DOOR — a `manual` receipt is still accepted, so the last
--     shipped build can go on saving a typed price without an error.
--
-- The backfill (newest manual line → base price, manual receipts retired) runs
-- once at migration time over production rows; it is proven by replaying 0051
-- over rows seeded at 0050, not here, where the tables start empty.

begin;
select plan(17);

insert into household (id, name) values
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('bbbbbbbb-0000-0000-0000-000000000401','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Parsley','g','parsley');

insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('bbbbbbbb-0000-0000-0000-000000000411','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000401','bunch',60);

-- 1 · The shape.

select col_is_null('public', 'ingredient', 'base_price_cents',
  'a row need not state a base price');
select col_is_null('public', 'ingredient', 'base_price_pack_basis_amount',
  'nor what it bought');
select has_column('public', 'ingredient', 'base_price_pack_amount',
  'the pack as entered');
select has_column('public', 'ingredient', 'base_price_pack_unit',
  'the unit it was entered in');
select has_column('public', 'ingredient', 'base_price_measure_id',
  'or the measure it was named as');
select has_column('public', 'ingredient', 'base_price_set_at',
  'and when it was set');

-- 2 · The whole.

select throws_ok(
  $$ update ingredient set base_price_cents = 199
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  '23514', null,
  'cents without a pack is refused — it would price nothing'
);

select throws_ok(
  $$ update ingredient set base_price_cents = 199,
            base_price_pack_basis_amount = 60
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  '23514', null,
  'a base price carries its date'
);

select throws_ok(
  $$ update ingredient set base_price_cents = 0,
            base_price_pack_basis_amount = 60, base_price_set_at = now()
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  '23514', null,
  'a base price of nothing is refused — unpriced is not free'
);

select throws_ok(
  $$ update ingredient set base_price_cents = 199,
            base_price_pack_basis_amount = 0, base_price_set_at = now()
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  '23514', null,
  'a pack of nothing is refused'
);

select throws_ok(
  $$ update ingredient set base_price_cents = 199,
            base_price_pack_basis_amount = 60, base_price_set_at = now(),
            base_price_pack_unit = 'g'
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  '23514', null,
  'a pack unit with no amount says nothing'
);

-- 3 · The words: one bunch, stored as a count of the measure AND as grams.

select lives_ok(
  $$ update ingredient set base_price_cents = 199,
            base_price_pack_basis_amount = 60, base_price_set_at = now(),
            base_price_pack_amount = 1,
            base_price_measure_id = 'bbbbbbbb-0000-0000-0000-000000000411'
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  'a bunch is stored as one bunch and the grams it came to'
);

select lives_ok(
  $$ update ingredient set base_price_cents = null,
            base_price_pack_basis_amount = null, base_price_set_at = null,
            base_price_pack_amount = null, base_price_measure_id = null
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  'a base price is taken back by clearing it whole'
);

-- 3b · The store (0052): optional, and only beside a price.

select col_is_null('public', 'ingredient', 'base_price_store',
  'a base price need not name a shop');

select throws_ok(
  $$ update ingredient set base_price_store = 'TJ''s'
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  '23514', null,
  'a store with no price names where nothing is paid'
);

select lives_ok(
  $$ update ingredient set base_price_cents = 199,
            base_price_pack_basis_amount = 60, base_price_set_at = now(),
            base_price_store = 'TJ''s'
      where id = 'bbbbbbbb-0000-0000-0000-000000000401' $$,
  'a base price names the shop it is paid at'
);

-- 4 · The old door stays open.

select lives_ok(
  $$ insert into receipt (household_id, store, purchased_at, subtotal_cents, source)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','TJ''s','2026-09-13T17:20:00Z',199,'manual') $$,
  'an older build''s typed price still saves'
);

select finish();
rollback;
