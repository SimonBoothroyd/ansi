-- 0058_shopping_at_home.sql — what is already at home (exec plan 0055).
--
-- Before a trip, either of us goes down the Shop list and says what is already
-- in the cupboard: all of a row, or an amount of it. The list subtracts it:
-- a part-have shortens the row to what is left to buy, and a whole-have leaves
-- the aisles. It cannot be re-derived from the week or the recipes, so by
-- ADR-0007's rule it joins the thin overlay — beside the tick and the top-ups.
--
-- **Three columns on the entry, not a contribution row.** An entry has ONE
-- amount at home, not a list of them, so the write is an update in place, and
-- `shopping_list_contribution` stays "manual top-ups only". The entry is
-- already per week (0019), so the amount belongs to that week's list: next
-- week starts clean, and the week-start flip (0043) re-keys it with its entry.
--
-- **An amount, never "all".** "Got all of it" stores the need as it stood, so
-- a week that grows brings the row back for the difference. The amount is
-- stored as it was said — quantity, a units.dart id, and the measure it was
-- counted in, exactly like a top-up — so the subtraction is the app's to do
-- honestly (invariant 3), never a number pre-converted here.
--
-- RLS, grants and the publication are untouched: the boundary is still
-- `household_id`, and both stream files select `*`.

alter table shopping_list_entry
  add column at_home_quantity   numeric,
  add column at_home_unit       text,
  add column at_home_measure_id uuid references ingredient_measure(id),
  -- An amount is positive, carries a unit, and sits only on an ingredient
  -- entry: a free-text item ("paper towels") has no need to take it from.
  add constraint shopping_list_entry_at_home_amount
    check (
      at_home_quantity is null
      or (at_home_quantity > 0
          and at_home_unit is not null
          and ingredient_id is not null)
    ),
  -- A measure counts the amount; it never stands without one.
  add constraint shopping_list_entry_at_home_measure
    check (at_home_measure_id is null or at_home_quantity is not null);

create index shopping_list_entry_at_home_measure_idx
  on shopping_list_entry (at_home_measure_id)
  where at_home_measure_id is not null;

comment on column shopping_list_entry.at_home_quantity is
  'How much of this ingredient is already at home for this week''s list, as '
  'said (with at_home_unit and at_home_measure_id). Null when nothing was '
  'said. Subtracted from the derived need by the app (exec plan 0055).';
