-- 0059_plan_entry_leftover_of.sql — a meal planned from a cooked batch's
-- leftover (exec plan 0059, phase 1).
--
-- A cooked batch is derived (there is no cook-session table), so a leftover
-- is named by the batch's key: its first covered meal, the same key
-- `batch_leftover` (0057) is keyed to. A meal eaten from it is an ordinary
-- recipe `plan_entry` whose `leftover_of` names that meal.
--
-- **It is eaten, never cooked again.** The cook plan, the shop and the week's
-- cost read `leftover_of is null`: the food was cooked, bought and costed in
-- its own week. Ticks, macros and Health Connect count it like any meal. The
-- batch's leftover falls by the meal's demand.
--
-- A hard delete of the batch's meal leaves the leftover meal standing as a
-- plain recipe meal (set null); a soft delete needs nothing, since the meal
-- still names a row that exists.

alter table plan_entry
  add column leftover_of uuid references plan_entry(id) on delete set null,
  add constraint plan_entry_leftover_of_not_self
    check (leftover_of is null or leftover_of <> id),
  add constraint plan_entry_leftover_of_is_a_recipe
    check (leftover_of is null or recipe_id is not null);

comment on column plan_entry.leftover_of is
  'The cooked batch (its first covered meal) this recipe meal is eaten from. '
  'Null on every meal that is cooked. A leftover meal is never cooked, bought '
  'or costed again (exec plan 0059).';

create index plan_entry_leftover_of_idx on plan_entry (leftover_of)
  where leftover_of is not null;
