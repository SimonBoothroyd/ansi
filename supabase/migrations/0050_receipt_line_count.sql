-- 0050_receipt_line_count.sql — how many of the thing the line rang up.
--
-- The owner's two real receipts, on one shop: on both the Whole Foods and the
-- Trader Joe's strip a COUNT SUB-ROW under an item is the RULE, not the
-- exception —
--
--   TOFU SPR FRM HGH PRTN OR   $23.92
--   8 @ $2.99
--
-- and until now the line above kept the whole $23.92 against ONE pack. Eight
-- blocks of tofu priced as one block is eight times too dear, on the
-- ingredient page, in every recipe that uses it and in what a week cost — and
-- nothing downstream could tell, because $23.92 really was paid and one block
-- really is the pack.
--
-- ---------------------------------------------------------------------------
-- The count is not part of the pack
-- ---------------------------------------------------------------------------
--
-- `pack_basis_amount` stays what ONE of them is, in the row's basis unit, and
-- that is the owner's own ruling: a pack is what the thing comes in, and how
-- many you happened to buy is a fact about one shop. Keeping them apart is
-- what lets the pack carry to the next receipt (the same 16 oz block) while
-- the count arrives fresh from the paper every time.
--
-- So the price a line states becomes:
--
--   (cents - discount_cents) / (count * pack_basis_amount)
--
-- per unit of the row's basis — one derivation, in `ingredients/domain/price
-- .dart`, that every reader goes through.
--
-- ---------------------------------------------------------------------------
-- The column
-- ---------------------------------------------------------------------------
--
-- Additive, over production data, with a default that is true of every row
-- already written: a line with no count sub-row under it rang up one thing,
-- which is what every stored line meant when it was stored. There is no
-- backfill beyond that default and there is nothing to re-read.

alter table receipt_line
  add column count integer not null default 1 check (count >= 1);

comment on column receipt_line.count is
  'How many of the thing this line rang up — the count printed on the sub-row '
  'under it ("Qty 4  $2.39 ea", "8 @ $2.99"). 1 unless the paper said '
  'otherwise. `cents` already includes them all; the count is what the PRICE '
  'is divided by: (cents - discount_cents) / (count * pack_basis_amount). It '
  'is never part of the pack — the pack is what one of them comes in, and it '
  'carries between shops while the count arrives fresh from the paper.';

-- Only a food line is ever counted, for the reason only a food line carries a
-- pack (0044's own fence): the count exists to divide a price, and a tax line,
-- a bag fee and a box of paper towels price nothing. The paper still adds up
-- either way — `cents` is the line's whole printed figure, counted or not.
alter table receipt_line
  add constraint receipt_line_only_items_are_counted check (
    kind = 'item' or count = 1
  );

-- Grants, RLS and the PowerSync publication are unchanged: all three are on
-- the TABLE (0044), so the new column arrives under what the table already
-- has. Both receipt sync rules are `select *`, so it reaches a device once the
-- sync container is recreated from a checkout holding this migration.
