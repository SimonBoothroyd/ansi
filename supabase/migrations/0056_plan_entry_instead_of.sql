-- 0056_plan_entry_instead_of.sql — what a member had instead of a planned
-- meal (exec plan 0054, phase 2).
--
-- A substitute is an ordinary `plan_entry` of any of the three kinds — a
-- recipe, a bare ingredient, a meal eaten out — whose `instead_of` names the
-- planned meal it replaced, and whose `eaters` is the one member who had it.
-- Being an ordinary entry, it reuses the picker, the kind switch and every
-- macro rule there is.
--
-- **It is eaten, never planned.** The app keeps substitutes out of the week's
-- planned meals, so they cook nothing, buy nothing and cost nothing: the cook
-- plan and the shop read `instead_of is null`, and the week attaches each
-- substitute to the meal it replaced. It counts only in what its member ate.
-- The planned meal is untouched, so its batch still knows a portion went
-- uneaten.
--
-- Cascades for a hard delete of the planned meal; a soft delete needs none,
-- since nothing reads a substitute without its live meal — and undoing a
-- removal brings both back.

alter table plan_entry
  add column instead_of uuid references plan_entry(id) on delete cascade,
  add constraint plan_entry_instead_of_not_self
    check (instead_of is null or instead_of <> id);

comment on column plan_entry.instead_of is
  'The planned meal this entry was eaten INSTEAD of, by its one eater. Null '
  'for every planned meal. A substitute is never cooked, bought or costed; it '
  'counts only in what its member ate (exec plan 0054).';

create index plan_entry_instead_of_idx on plan_entry (instead_of)
  where instead_of is not null;
