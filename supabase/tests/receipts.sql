-- pgTAP: the price fact — receipts and their lines (0044).
--
-- A price is an event, not a column: cents paid for a stated pack, at a store,
-- on a day. What is defended here:
--
--   * the SHAPE — the two tables exist with the columns the app reads, the
--     enumerations are closed (`source`, `kind`), a pack amount must be
--     positive, and a discount is stated as a non-negative deduction;
--   * the FENCE — only a food line can be about an ingredient or carry a
--     pack. A tax line with a pack weight would be a price nobody can read;
--   * the LEDGER — a hand-typed price really is a one-line `manual` receipt,
--     so the derivation a screen reads is the same arithmetic over a scanned
--     line and a typed one;
--   * the RETIRE — a receipt line is deliberately NOT one of the lines
--     `ingredient_live_line_uses()` counts (history does not block a prune),
--     and it never dangles either: on a retire it follows the single live
--     twin where there is one and otherwise loses its ingredient, keeping the
--     paper whole.
--
-- Household isolation for both tables is asserted data-driven in
-- `rls_household_isolation.sql`. Run by `supabase test db`.

begin;
select plan(22);

-- ---------------------------------------------------------------------------
-- Fixtures: one household, a duplicate vocab pair (so the twin leg has a twin
-- to find), and one unrelated row with no twin at all.
-- ---------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','receipt-a@x.com');

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A');

insert into household_member (household_id, display_name, auth_user_id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','A1','11111111-1111-1111-1111-111111111111');

-- 401 and 402 normalize to the same text — the duplicate pair a de-dup leaves
-- behind. 403 is on its own: retiring it strands nothing to follow.
insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000401','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Bananas, organic','piece','bananas organic'),
 ('aaaaaaaa-0000-0000-0000-000000000402','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Bananas, organic','piece','bananas organic'),
 ('aaaaaaaa-0000-0000-0000-000000000403','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Sauerkraut','g','sauerkraut');

insert into ingredient_measure (id, household_id, ingredient_id, label, basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000411','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000401','bag',454);

insert into receipt (id, household_id, store, purchased_at, subtotal_cents, source) values
 ('aaaaaaaa-0000-0000-0000-000000000501','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','TJ''s','2026-09-13T17:20:00Z',349,'manual');

-- ---------------------------------------------------------------------------
-- 1 · The shape.
-- ---------------------------------------------------------------------------

select has_table('public', 'receipt', 'receipt exists');
select has_table('public', 'receipt_line', 'receipt_line exists');
select col_not_null('public', 'receipt', 'store', 'a receipt names its store');
select col_not_null('public', 'receipt', 'purchased_at',
  'a receipt is dated by the shop, not the scan');
select col_is_null('public', 'receipt', 'subtotal_cents',
  'the printed subtotal is optional — the lines are not re-derived into it');
select has_column('public', 'receipt_line', 'pack_basis_amount',
  'a line states what the cents bought, in the row''s basis unit');

select throws_ok(
  $$ insert into receipt (household_id, store, purchased_at, source)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','TJ''s','2026-09-13T17:20:00Z','scribbled') $$,
  '23514', null,
  'source is a closed set — manual or photo'
);

select throws_ok(
  $$ insert into receipt_line (household_id, receipt_id, cents, kind)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501',100,'groceries') $$,
  '23514', null,
  'kind is a closed set — item, not_food, tax, fee'
);

select throws_ok(
  $$ insert into receipt_line (household_id, receipt_id, ingredient_id, cents, kind, pack_basis_amount)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501',
             'aaaaaaaa-0000-0000-0000-000000000401',349,'item',0) $$,
  '23514', null,
  'a pack of nothing is refused — it would price everything at once'
);

select throws_ok(
  $$ insert into receipt_line (household_id, receipt_id, cents, discount_cents, kind)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501',349,-50,'item') $$,
  '23514', null,
  'a discount is stated as the amount taken away, never a negative one'
);

-- A fee line MAY be negative: that is how a discount the scanner could not
-- attach to an item still lets the reconcile close.
select lives_ok(
  $$ insert into receipt_line (id, household_id, receipt_id, printed_text, cents, kind)
     values ('aaaaaaaa-0000-0000-0000-000000000599','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'aaaaaaaa-0000-0000-0000-000000000501','COUPON',-100,'fee') $$,
  'an unattached discount is a fee line with negative cents'
);

-- ---------------------------------------------------------------------------
-- 2 · The fence: only a food line is about an ingredient or carries a pack.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into receipt_line (household_id, receipt_id, ingredient_id, cents, kind)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501',
             'aaaaaaaa-0000-0000-0000-000000000401',199,'not_food') $$,
  '23514', null,
  'a not_food line is about no ingredient — it never becomes a price'
);

select throws_ok(
  $$ insert into receipt_line (household_id, receipt_id, cents, kind, pack_basis_amount)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501',
             88,'tax',454) $$,
  '23514', null,
  'a tax line carries no pack'
);

-- ---------------------------------------------------------------------------
-- 3 · A hand-typed price is a one-line manual receipt.
-- ---------------------------------------------------------------------------

insert into receipt_line (id, household_id, receipt_id, ingredient_id, cents, kind,
                          pack_basis_amount, measure_id) values
 ('aaaaaaaa-0000-0000-0000-000000000502','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaaaaaa-0000-0000-0000-000000000501','aaaaaaaa-0000-0000-0000-000000000401',
  349,'item',454,'aaaaaaaa-0000-0000-0000-000000000411');

select is(
  (select r.source from receipt r
    where r.id = 'aaaaaaaa-0000-0000-0000-000000000501'),
  'manual',
  'a typed price is a manual receipt'
);

select is(
  (select r.subtotal_cents from receipt r
    where r.id = 'aaaaaaaa-0000-0000-0000-000000000501'),
  349,
  'its subtotal is the line''s own cents'
);

-- The derivation the app reads, run here in SQL so the contract is pinned on
-- both sides: 349¢ for 454 g is 76.87…¢ per 100 g, which prints as 77¢.
select is(
  (select round((l.cents - l.discount_cents) * 100.0 / l.pack_basis_amount)
     from receipt_line l where l.id = 'aaaaaaaa-0000-0000-0000-000000000502'),
  77::numeric,
  '$3.49 for a 454 g bag is 77¢ / 100 g'
);

-- ---------------------------------------------------------------------------
-- 4 · The retire: history does not block a prune, and never dangles.
-- ---------------------------------------------------------------------------

select is(
  ingredient_live_line_uses('aaaaaaaa-0000-0000-0000-000000000401'),
  0::bigint,
  'a receipt line is not a live line — a shop that happened blocks nothing'
);

update ingredient set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000401';

select is(
  (select l.ingredient_id from receipt_line l
    where l.id = 'aaaaaaaa-0000-0000-0000-000000000502'),
  'aaaaaaaa-0000-0000-0000-000000000402'::uuid,
  'the line follows the retired row''s single live twin'
);

select is(
  (select l.measure_id from receipt_line l
    where l.id = 'aaaaaaaa-0000-0000-0000-000000000502'),
  null::uuid,
  'the pack''s WORD goes with the row it belonged to'
);

select is(
  (select l.pack_basis_amount from receipt_line l
    where l.id = 'aaaaaaaa-0000-0000-0000-000000000502'),
  454::numeric,
  'the pack''s NUMBER stays — it is still true about a purchase that happened'
);

-- Now the row with no twin: the line keeps the paper and loses the pointer.
insert into receipt_line (id, household_id, receipt_id, ingredient_id, printed_text,
                          cents, kind, pack_basis_amount) values
 ('aaaaaaaa-0000-0000-0000-000000000503','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaaaaaa-0000-0000-0000-000000000501','aaaaaaaa-0000-0000-0000-000000000403',
  'SAUERKRAUT 500G',499,'item',500);

update ingredient set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000403';

select is(
  (select l.ingredient_id from receipt_line l
    where l.id = 'aaaaaaaa-0000-0000-0000-000000000503'),
  null::uuid,
  'with no twin the line loses its ingredient rather than dangling'
);

select is(
  (select l.printed_text || ' ' || l.cents::text from receipt_line l
    where l.id = 'aaaaaaaa-0000-0000-0000-000000000503'),
  'SAUERKRAUT 500G 499',
  'the paper is kept as paid'
);

select finish();
rollback;
