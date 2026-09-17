-- 0046_receipt_line_pack_as_entered.sql — a price keeps the pack in the words
-- it was bought in.
--
-- 0044 stores what the cents bought in the row's basis unit
-- (`pack_basis_amount`, g or ml) and that is still the number every price is
-- DERIVED from. What it lost on the way in was the sentence the person said:
-- a pound of butter went in as `1 lb` and came back out of the ledger as
-- `454 g`, which is the same weight and a different fact. A price is an event,
-- and the event was a pound.
--
-- So the line now keeps both, and they answer different questions:
--
--   * `pack_amount` / `pack_unit` — what was ENTERED. It is what the Price
--     group prints (`$3.49 for 1 lb`) and what the price sheet reopens on, and
--     nothing is derived from it.
--   * `pack_basis_amount` — what it CAME TO, in the row's basis unit, resolved
--     once at entry through the density gate. Every figure a screen reads
--     (77¢ / 100 g) is still derived from this and this alone.
--
-- The split is deliberate and is the same one `ingredient_measure` already
-- makes between its `label` and its `basis_amount`: a shop that has already
-- happened must not re-price itself. A household that re-weighs its `bag` from
-- 454 g to 500 g is stating what a bag is TODAY; last month's $3.49 bought
-- last month's bag, and `pack_basis_amount` is the only reason that stays true.
--
-- ---------------------------------------------------------------------------
-- The two shapes, and there is no third
-- ---------------------------------------------------------------------------
--
-- A pack was said in one of exactly two ways, and `pack_unit` is what tells
-- them apart:
--
--   * **a plain amount in a unit** — `pack_unit` is a units.dart canonical unit
--     id (`'lb'`, `'g'`, `'l'`, the same ids `recipe_line.unit` holds) and
--     `pack_amount` is the number said in it;
--   * **a count of one of the row's own measures** — `measure_id` names the
--     measure, `pack_amount` is HOW MANY of them (almost always 1), and
--     `pack_unit` is null. The measure's own `label` is the word, so storing
--     `'bag'` in `pack_unit` too would be a second copy of it to drift.
--
-- `pack_unit` is therefore read first and decides how `pack_amount` is read.
-- Both are null on a line nobody has said the pack of — the honest state 0044
-- already describes — and on a line written by a client that predates them.
--
-- The backfill below is the one place the two can disagree, and it says so
-- rather than guessing: every existing line is given the pack it was STORED
-- with, in the basis unit, because that is the only pack the database ever
-- knew. A line that named a measure keeps its `measure_id`, so it goes on
-- printing that word; its `pack_amount` is the basis figure rather than a
-- count, which is why the reader prefers the measure's label where there is
-- one and falls back to the amount only where there is not.

alter table receipt_line
  add column pack_amount numeric check (pack_amount > 0),
  add column pack_unit   text;

comment on column receipt_line.pack_amount is
  'What the person said the pack was, as a number. Read through pack_unit: '
  'with a unit it is an amount in that unit, and with pack_unit null and a '
  'measure_id set it is a COUNT of that measure. Never derived from — '
  'pack_basis_amount is the number a price is read from.';

comment on column receipt_line.pack_unit is
  'The units.dart canonical unit id the pack was entered in (''lb'', ''g'', '
  '''l'' — the same ids recipe_line.unit holds), or null when the pack was '
  'tapped as one of the row''s own measures, whose label is the word and '
  'whose count is pack_amount.';

-- Only a food line can carry a pack, in 0044's own fence: a tax line stating
-- `1 lb` would be a price nobody could read, in either denomination.
alter table receipt_line
  add constraint receipt_line_only_items_state_a_pack check (
    kind = 'item' or (pack_amount is null and pack_unit is null)
  ),
  -- A unit with no number says nothing. (The reverse is a real state: a count
  -- of a measure has an amount and no unit.)
  add constraint receipt_line_a_pack_unit_needs_an_amount check (
    pack_unit is null or pack_amount is not null
  );

-- ---------------------------------------------------------------------------
-- Backfill: the pack every existing line really was stated in.
-- ---------------------------------------------------------------------------
--
-- The only pack these rows have ever held is the basis figure, so that is what
-- they are given — the amount as stored, in the ingredient's own basis unit.
-- Nothing is reconstructed: a pound bought before this migration stays `454 g`,
-- because `454 g` is genuinely all the database was told.
--
-- A line whose ingredient was detached by 0044's retire trigger has no basis to
-- name, so it keeps its number and states no unit: the amount is still true and
-- the dimension is honestly unknown.
update receipt_line l
   set pack_amount = l.pack_basis_amount,
       pack_unit   = i.macros_basis
  from ingredient i
 where i.id = l.ingredient_id
   and l.pack_basis_amount is not null
   and l.pack_amount is null;
