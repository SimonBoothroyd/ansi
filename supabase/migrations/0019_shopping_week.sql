-- 0019_shopping_week.sql — the shopping overlay gains a week (week redesign D3).
--
-- Cook and Shop now derive from the week you are LOOKING AT, not the week
-- containing today (design board "Week · v2", D3 = B): you plan next week on a
-- Sunday, so you must be able to shop for it on a Sunday. The derived half of
-- the list was always week-parameterised (`watchShoppingList(weekStart)` runs
-- the cook plan for that Monday). The stored half — the thin overlay of ADR-0007
-- — was not: `shopping_list_entry` is one row per ingredient per household, full
-- stop. Under D3 that means ticking "Flour" while looking at next week ticks it
-- on this week's list too, and a check that lies about which list it belongs to
-- is exactly what invariant 3 exists to stop.
--
-- So the entry gains the week it was made against.
--
--   * an INGREDIENT entry (a check-off, a top-up) belongs to ONE week —
--     `week_start_date` is that Monday, the same key `week_plan` is addressed by;
--   * a FREE-TEXT entry ("paper towels") stays GLOBAL — `week_start_date` is
--     null. You are out of paper towels regardless of which week is on screen,
--     and free-text staples work with no plan at all (that is why the Shop
--     screen keeps `Add an item` even on an empty week).
--
-- `shopping_list_contribution` needs NOTHING: a manual top-up hangs off its
-- entry (`entry_id`, on delete cascade), so it inherits the entry's week for
-- free. Adding a second copy of the week there would be two places to keep in
-- step for no read that wants it.
--
-- No unique index, deliberately — the same reason there has never been one
-- (0006): two offline devices must each be able to create an entry for the same
-- ingredient and converge later; a unique index would make the second device's
-- upload fail and lose its data. The app converges on the oldest live row
-- instead (`_findOrCreateIngredientEntry`), now within a week.
--
-- NO BACKFILL. Dev data is ephemeral through the roadmap, so existing rows are
-- simply left as they are: an ingredient row with a null week belonged to no
-- week and is no longer read by any week (a free-text row with a null week is
-- global and reads on every week, which is the rule above, not an accident).
-- Writing a backfill would be migration machinery for data nobody keeps.
--
-- RLS, grants and the publication are UNTOUCHED: the boundary is still
-- `household_id`, and a new column on a table already in the `powersync`
-- publication ships with it (the sync rules select *).

alter table shopping_list_entry
  add column week_start_date date;   -- the Monday this tick belongs to;
                                     -- null = a global free-text staple

comment on column shopping_list_entry.week_start_date is
  'The Monday of the week this entry was touched on (matches week_plan.week_start_date). Null for a global free-text staple, which belongs to no week.';

-- The list read is always "this household, this week", so index the pair.
create index shopping_list_entry_week_idx
  on shopping_list_entry (household_id, week_start_date);
