-- 0040_week_recipe_line_override.sql — a recipe cooked differently for ONE
-- planned week (exec plan 0043).
--
-- The row is a DELTA against a recipe line, not a copy of it: a swap, an
-- amount, an addition, an exclusion, or an optional line ticked back in. The
-- recipe is untouched, so the Library, the recipe page and every other week
-- keep reading exactly what they read before.
--
-- One variant per (week_plan, recipe) — the owner's ruling, "one variant of
-- each recipe per week, all days use it". That key is what keeps the cook plan
-- whole: a session is one pot, one scale, one line set, so two meals of the
-- same dish in one week that disagreed about what goes in could not share it.
--
-- Amounts are ABSOLUTE, never a factor against the recipe. The recipe moving
-- 400 g to 500 g later leaves this week at the 400 g somebody asked for.
--
-- The shape is `recipe_line_item`'s, one table over: the ingredient /
-- sub-recipe XOR of 0017 for the target, and the amount-pair and
-- measure-needs-amount checks of 0033. `sub_recipe_id` ships as a column only
-- — the component graph is read household-wide with no week, so swapping in a
-- sub-recipe for one week would make that graph week-dependent. The picker
-- suppresses its "Your recipes" section in week mode; the column is here so
-- unsuppressing it is a client change.

create table week_recipe_line_override (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references household(id) on delete cascade,

  -- Cascades: an override is ABOUT a line in a week, so with either gone
  -- there is nothing left for it to be about. A soft delete needs no cascade
  -- — the derivation joins `deleted_at is null`, finds no base line, skips
  -- the row, and the next save drops it.
  week_plan_id uuid not null references week_plan(id) on delete cascade,
  recipe_id    uuid not null references recipe(id)    on delete cascade,

  -- The recipe line this row is about. NULL exactly when the row ADDS a line
  -- that the recipe has not got (`week_recipe_line_override_action_shape`).
  recipe_line_item_id uuid references recipe_line_item(id) on delete cascade,

  action text not null
    check (action in ('include', 'exclude', 'replace', 'add')),

  -- The target, when the row carries one. 0017's XOR, stated on the two
  -- actions that name a thing to cook with.
  ingredient_id  uuid references ingredient(id),
  sub_recipe_id  uuid references recipe(id),

  quantity   numeric check (quantity is null or quantity > 0),
  unit       text,
  measure_id uuid references ingredient_measure(id),
  note       text,
  -- Where an added line sits within the recipe's last group. Ignored on every
  -- other action: reordering the recipe's own lines is not storable this week
  -- (0043 D3), so the editor does not offer it.
  sort_order integer,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  -- One row per (week, recipe, line). NULLs compare DISTINCT in a unique
  -- index, so many `add` rows are legal while a base line can be overridden
  -- exactly once — which is what makes the set recomputable whole on save.
  constraint week_recipe_line_override_one_per_line
    unique (week_plan_id, recipe_id, recipe_line_item_id),

  -- `include` / `exclude` are statements ABOUT a recipe line and carry no
  -- values of their own; `replace` / `add` name exactly one target. An `add`
  -- has no base line, everything else has one.
  constraint week_recipe_line_override_action_shape check (
    case action
      when 'include' then recipe_line_item_id is not null
        and num_nonnulls(ingredient_id, sub_recipe_id, quantity, unit,
                         measure_id, note) = 0
      when 'exclude' then recipe_line_item_id is not null
        and num_nonnulls(ingredient_id, sub_recipe_id, quantity, unit,
                         measure_id, note) = 0
      when 'replace' then recipe_line_item_id is not null
        and num_nonnulls(ingredient_id, sub_recipe_id) = 1
      when 'add' then recipe_line_item_id is null
        and num_nonnulls(ingredient_id, sub_recipe_id) = 1
    end
  ),

  -- A component override carries no measure — 0017's rule, because a measure
  -- counts an ingredient's things and a sub-recipe has none.
  constraint week_recipe_line_override_component_has_no_measure
    check (sub_recipe_id is null or measure_id is null),

  -- Both-or-neither (0033): "400" and "g" are each half a fact, and half a
  -- fact is what the never-invent invariant forbids downstream from
  -- completing.
  constraint week_recipe_line_override_amount_pair
    check (num_nonnulls(quantity, unit) <> 1),

  -- A measure counts THINGS, so it only means something beside a number.
  constraint week_recipe_line_override_measure_needs_amount
    check (measure_id is null or quantity is not null)
);

create index week_recipe_line_override_week_idx
  on week_recipe_line_override (week_plan_id);
create index week_recipe_line_override_line_idx
  on week_recipe_line_override (recipe_line_item_id);
create index week_recipe_line_override_household_idx
  on week_recipe_line_override (household_id);

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (the 0005 trio, verbatim).
alter table week_recipe_line_override enable row level security;

create policy week_recipe_line_override_read on week_recipe_line_override
  for select using (household_id = current_household_id());
create policy week_recipe_line_override_write on week_recipe_line_override
  for insert with check (household_id = current_household_id());
create policy week_recipe_line_override_update on week_recipe_line_override
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Privileges mirror the policies (no DELETE — soft delete). RLS filters,
-- GRANTs gate: without this the table is invisible to the app.
grant select, insert, update on week_recipe_line_override to authenticated;
grant all on week_recipe_line_override to service_role;

alter publication powersync add table week_recipe_line_override;

comment on table week_recipe_line_override is
  'One delta against a recipe line for ONE planned week (exec plan 0043). '
  'Keyed on (week_plan, recipe): all days that plan the recipe that week '
  'cook the same lines, so the cook plan still batches them into one pot.';

comment on column week_recipe_line_override.action is
  'include = keep an optional recipe line this week; exclude = leave a recipe '
  'line out; replace = cook the line with these ABSOLUTE values; add = a line '
  'the recipe has not got. A line edited back to the recipe''s own value '
  'leaves no row at all — the set is recomputed whole on save.';

comment on column week_recipe_line_override.sub_recipe_id is
  'Ships as a column only in v1: the component graph is read household-wide '
  'with no week, so a sub-recipe swap for one week would make it '
  'week-dependent. The picker suppresses its recipes section in week mode.';
