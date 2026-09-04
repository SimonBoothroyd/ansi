-- 0033_plan_ingredient.sql — a plan slot takes an ingredient, not only a
-- recipe (roadmap step 8.14, exec plan 0038, decision B-D1).
--
-- Something you simply *eat* — a protein bar, a yoghurt, an apple — is planned
-- as itself rather than dressed up as a one-line recipe. The shape is the one
-- `recipe_line_item` already wears one table over (0017 / D1): the row names a
-- recipe **or** an ingredient, never both and never neither, and the amount
-- columns ride the ingredient side.
--
-- What this migration is NOT:
--
--   * **Not a new slot.** `meal_slot` is free text, not an enum (0005), so the
--     `snacks` slot the week grows costs nothing here.
--   * **Not a new demand model** (A-D3, owner-ruled). An ingredient entry keeps
--     the `eaters` array and the `portions` override it already has, and demand
--     is the same Σ of portion factors every other entry uses — multiple people
--     can have the same snack. The stated amount is what ONE portion is; the
--     week's arithmetic multiplies it exactly as it multiplies a serving.
--   * **Not a sync-rule change.** Both stream YAMLs select `*` from
--     `plan_entry`, so `docker/powersync.yaml` and
--     `docker/powersync-cloud.streams.yaml` carry these columns without an edit
--     (the 0017 precedent). No RLS/grant/publication change either: the table
--     already carries household-scoped policies and is in the `powersync`
--     publication (0005), and a new column on a published table needs no
--     republication.
--
-- No household fence trigger, deliberately. `recipe_line_item.ingredient_id`
-- has carried a plain (global) FK since 0003 with RLS guarding the row's own
-- household, and this column is the same fact one table over. 0017's trigger
-- exists for `sub_recipe_id` because a component link can also close a CYCLE,
-- which poisons every derivation walk; an ingredient reference cannot.

alter table plan_entry
  -- Relaxed exactly as `recipe_line_item.ingredient_id` was in 0017: the
  -- column stays load-bearing, the XOR below is what makes it total.
  alter column recipe_id drop not null,
  add column ingredient_id uuid references ingredient(id),
  -- The amount of ONE portion of the snack. Nullable as a pair with `unit`:
  -- an entry that states no amount contributes nothing and says so (invariant
  -- 3), rather than being completed by a guess.
  add column quantity numeric check (quantity is null or quantity > 0),
  add column unit text,
  -- → ingredient_measure.id. Set when the amount is counted in a named measure
  -- ("1 bar"), in which case `unit` carries the honest count fallback the rest
  -- of the app stores beside a measure (`piece`).
  add column measure_id uuid references ingredient_measure(id),

  -- The XOR (B-D1) — 0006/0017's shape. A reader that finds neither has
  -- nothing to eat; one that finds both has two answers to the same question.
  add constraint plan_entry_target_xor
    check (num_nonnulls(recipe_id, ingredient_id) = 1),

  -- A recipe entry's amount is its `portions`; a second amount beside it would
  -- be a fact with two sources. So the amount columns belong to the ingredient
  -- side only.
  add constraint plan_entry_amount_is_for_ingredients
    check (
      ingredient_id is not null
      or num_nonnulls(quantity, unit, measure_id) = 0
    ),

  -- Both-or-neither, like `recipe.yield_qty`/`yield_unit` (0017): "1" and
  -- "bar" are each half a fact, and half a fact is what the never-invent
  -- invariant forbids downstream from completing.
  add constraint plan_entry_amount_pair
    check (num_nonnulls(quantity, unit) <> 1),

  -- A measure counts THINGS, so it only means something beside a number.
  add constraint plan_entry_measure_needs_amount
    check (measure_id is null or quantity is not null);

comment on column plan_entry.recipe_id is
  'The dish this meal is, or NULL when the meal is a bare ingredient '
  '(step 8.14 / B-D1). Exactly one of recipe_id / ingredient_id is set — '
  'plan_entry_target_xor. Every derivation branches on this explicitly: the '
  'cook plan ignores an ingredient entry (nothing is cooked), week macros and '
  'the shopping list include it.';

comment on column plan_entry.ingredient_id is
  'The thing this meal IS when it is not a recipe — a protein bar, a yoghurt '
  '(step 8.14 / B-D1). Carries eaters and multiplies like any other entry '
  '(A-D3): the amount below is one portion of it.';

comment on column plan_entry.quantity is
  'The amount of ONE portion of the ingredient this entry names — "1" of a '
  'measure, or "170" of a unit. Set with `unit` or not at all; an entry with '
  'no amount contributes nothing to macros or the shopping list and says so.';

comment on column plan_entry.measure_id is
  'The named measure the amount is counted in ("1 bar"), when it is (step '
  '8.14 / A-D2 — the shipped quantity sheet, seeded from the row''s stated '
  'default measure). `unit` then holds the honest count fallback, as every '
  'other measure-quantified row in the schema does.';

create index plan_entry_ingredient_idx on plan_entry (ingredient_id);
create index plan_entry_measure_idx on plan_entry (measure_id);
