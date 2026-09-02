-- 0017_nested_recipes.sql — a recipe as an ingredient (roadmap step 8.6,
-- exec plan 0021, decisions D1/D2/D5).
--
-- Three concerns, all on tables that already exist:
--
-- 1. **`recipe_line_item.sub_recipe_id`** (D1) — a component ("¼ cup Romesco
--    Aioli") is an ORDINARY line, not a second table: it inherits group
--    membership, sort order, quantity/unit/note, soft delete and sync for
--    free, and every surface keeps walking `group → line_item` once. The cost
--    is two CHECKs: exactly one of `ingredient_id` / `sub_recipe_id` is set
--    (XOR — `ingredient_id` relaxes to nullable here), and `measure_id` stays
--    NULL on a component line (a measure is an *ingredient* concept —
--    "potato, medium = 213 g" says nothing about a recipe).
--
-- 2. **`recipe.yield_qty/yield_unit` (+ a second denomination)** (D2) — what
--    the component's amount counts. "Makes 1 cup" is what turns `¼ cup` into
--    ¼ of a batch; without it the link, the view and scaling still work and
--    every derived number honestly says it can't (never `1×`). Nullable, and
--    independent of `servings_base` (portions are a different fact).
--
--    The **second denomination** (owner amendment, 2026-09-01) states a
--    second printed fact in a DIFFERENT unit family — "makes 250 g · 16
--    tbsp" — which bridges mass↔volume for this recipe only, the way an
--    `ingredient_measure` bridges count↔mass, without giving recipes a
--    density. Capped at two: a third family is a curiosity no printed page
--    states. `unit_family()` below is the SQL mirror of `UnitFamily` in
--    `app/lib/core/units/units.dart` (change one, change both; the vectors
--    are pinned in `supabase/tests/nested_recipes.sql`), following the
--    `default_allowed_units()` precedent from 0012/0014. An id the mirror
--    does not know becomes its own singleton family, so two unknown ids are
--    "different" only when they actually differ.
--
-- 3. **The cycle guard** (D5, ruled into v1) — a link A→B is refused when B
--    (transitively, over LIVE links) already reaches A. A cycle poisons every
--    derivation walk (cook plan, shopping, macros), so the device-side check
--    gets a server mirror rather than the one-rule-behind debt 8.5 accepted.
--    The same trigger enforces the D1 fence that a link never leaves the
--    household: `sub_recipe_id` has a plain FK to `recipe(id)`, which is
--    global, and RLS on `recipe_line_item` only guards the ROW's own
--    household — nothing in the schema stops a client from pointing at
--    another household's recipe id, so the trigger does.
--
-- NOT here, deliberately:
--   * **Delete refusal** ("used in 2 recipes") is a CLIENT rule, exactly as
--     8.5 ruled it for ingredients — one count query, two uses (the refusal
--     and the "Used in · N" tab). No server gate, no RPC.
--   * `yield_raw` prefill parsing — client-side Dart (`buildCommit`), lane I.
--
-- No RLS/grant change: both tables already carry household-scoped policies
-- and are in the `powersync` publication (0003), and a new column on a
-- published table needs no republication. The sync rules select `*` from
-- both, so `docker/powersync.yaml` and `docker/powersync-cloud.streams.yaml`
-- carry these columns without an edit.

-- ---------------------------------------------------------------------------
-- 1. Component lines (D1).
-- ---------------------------------------------------------------------------

alter table recipe_line_item
  alter column ingredient_id drop not null,
  add column sub_recipe_id uuid references recipe(id),
  add constraint line_item_identity_xor
    check (num_nonnulls(ingredient_id, sub_recipe_id) = 1),
  add constraint line_item_component_has_no_measure
    check (sub_recipe_id is null or measure_id is null);

comment on column recipe_line_item.sub_recipe_id is
  'The recipe this line is a COMPONENT of another recipe by (step 8.6 / D1). '
  'Exactly one of ingredient_id / sub_recipe_id is set; a component line '
  'never carries a measure_id. Same-household only — enforced by the '
  'recipe_line_item_sub_recipe_guard trigger, not by the (global) FK.';

create index line_item_sub_recipe_idx on recipe_line_item (sub_recipe_id);

-- ---------------------------------------------------------------------------
-- 2. Yield — one or two denominations (D2).
-- ---------------------------------------------------------------------------

-- SQL mirror of `UnitFamily` / the `Unit` table in
-- app/lib/core/units/units.dart. IMMUTABLE so it can be used in a CHECK.
-- Returns NULL for an id the vocabulary does not know; callers that need a
-- total function fall back to the id itself (see the different-family CHECK).
create or replace function unit_family(p_unit text) returns text
language sql
immutable
as $$
  select case
    when p_unit in ('g', 'kg', 'mg', 'oz', 'lb') then 'mass'
    when p_unit in ('ml', 'l', 'tsp', 'tbsp', 'fl_oz', 'cup') then 'volume'
    when p_unit = 'piece' then 'count'
    when p_unit in ('pinch', 'dash', 'handful', 'to_taste') then 'imprecise'
    else null
  end;
$$;

comment on function unit_family(text) is
  'The unit family (mass|volume|count|imprecise) of a units.dart Unit id, or '
  'NULL when the id is unknown. SQL mirror of UnitFamily in '
  'app/lib/core/units/units.dart — change one, change both; the vectors are '
  'pinned in supabase/tests/nested_recipes.sql.';

alter table recipe
  add column yield_qty    numeric check (yield_qty   is null or yield_qty   > 0),
  add column yield_unit   text,
  add column yield_qty_2  numeric check (yield_qty_2 is null or yield_qty_2 > 0),
  add column yield_unit_2 text,
  -- Both-or-neither, per denomination: "makes 1" and "makes cup" are each
  -- half a fact, and half a fact is exactly what the never-invent invariant
  -- forbids downstream from completing.
  add constraint recipe_yield_pair
    check (num_nonnulls(yield_qty, yield_unit) <> 1),
  add constraint recipe_yield_2_pair
    check (num_nonnulls(yield_qty_2, yield_unit_2) <> 1),
  -- The second denomination is a SECOND statement of the same batch — there
  -- is no second without a first.
  add constraint recipe_yield_2_needs_first
    check (yield_qty_2 is null or yield_qty is not null),
  -- …and it must bridge, not repeat: a different family (D2). Unknown ids
  -- become their own singleton family so the rule stays total.
  add constraint recipe_yield_2_other_family
    check (
      yield_unit_2 is null
      or coalesce(unit_family(yield_unit_2), 'unit:' || yield_unit_2)
         is distinct from
         coalesce(unit_family(yield_unit),   'unit:' || yield_unit)
    );

comment on column recipe.yield_qty is
  'What one batch MAKES ("makes 1 cup", "makes 8 piece") — step 8.6 / D2. '
  'Nullable and independent of servings_base (portions are a different '
  'fact). Set with yield_unit or not at all. No yield ⇒ a component line of '
  'this recipe is honestly UNRESOLVED; nothing downstream assumes 1 batch.';
comment on column recipe.yield_qty_2 is
  'The optional SECOND denomination of the same batch ("makes 250 g · 16 '
  'tbsp"). Requires the first pair, and its unit must be a DIFFERENT family '
  '— two stated facts that bridge mass↔volume for this recipe only.';

-- ---------------------------------------------------------------------------
-- 3. The cycle + household guard (D5).
-- ---------------------------------------------------------------------------
--
-- Fires only for LIVE component lines (the WHEN clause), so ordinary
-- ingredient lines and tombstones pay nothing. Reads are the invoker's, so
-- under `authenticated` every query is already RLS-narrowed to the caller's
-- household; the explicit household comparison covers the service_role path
-- too (edge functions bypass RLS).
--
-- The walk is depth-BOUNDED, not just cycle-free by construction: if a bad
-- cycle ever exists (a two-device race that beat the guard, a hand-edited
-- row), a plain recursive CTE over it would spin forever and wedge the
-- writer. It stops and lets the write through rather than hanging — the
-- domain walkers carry their own visited-set guard (D3) for that case.
create or replace function recipe_line_item_sub_recipe_guard()
returns trigger
language plpgsql
as $$
declare
  parent_recipe uuid;
  target_household uuid;
  reaches boolean;
begin
  -- The household fence. Under RLS a foreign household's recipe simply isn't
  -- visible, so this reads NULL and refuses; as service_role it is visible
  -- and the comparison refuses. Either way the link stays inside (D1).
  select r.household_id into target_household
  from recipe r
  where r.id = new.sub_recipe_id and r.deleted_at is null;

  if target_household is null or target_household <> new.household_id then
    raise exception
      'sub_recipe_id % is not a live recipe in this household', new.sub_recipe_id
      using errcode = '23503';
  end if;

  select g.recipe_id into parent_recipe
  from ingredient_group g
  where g.id = new.group_id;

  if parent_recipe is null then
    return new;  -- group not visible/known: RLS or FK will speak, not us
  end if;

  if parent_recipe = new.sub_recipe_id then
    raise exception 'a recipe cannot be a component of itself (%)', parent_recipe
      using errcode = '23514';
  end if;

  -- Can the target reach the parent over live component links?
  with recursive reachable(recipe_id, depth) as (
    select new.sub_recipe_id, 0
    union all
    select li.sub_recipe_id, rc.depth + 1
    from reachable rc
    join ingredient_group g
      on g.recipe_id = rc.recipe_id and g.deleted_at is null
    join recipe_line_item li
      on li.group_id = g.id and li.deleted_at is null
         and li.sub_recipe_id is not null
    where rc.depth < 32   -- bounded: a pre-existing cycle must not hang a write
  )
  select exists (select 1 from reachable where recipe_id = parent_recipe)
  into reaches;

  if reaches then
    raise exception
      'linking recipe % would create a component cycle', new.sub_recipe_id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger recipe_line_item_sub_recipe_guard
  before insert or update on recipe_line_item
  for each row
  when (new.sub_recipe_id is not null and new.deleted_at is null)
  execute function recipe_line_item_sub_recipe_guard();
