-- 0049_recipe_measure_unit_family.sql — a recipe measure's unit is a unit.
--
-- 0048's check on `recipe_measure.unit` only refused `batch` and the imprecise
-- words, so an id the catalog has never held ('blorp') passed. `unit_family`
-- knows every mass, volume and count id in `units.dart` (`pt` and `qt` since
-- 0024), so the rule is said positively here. The `coalesce` matters: an
-- unknown id has a NULL family, and a check passes on NULL.
--
-- The previous client only ever writes catalog ids, so it never meets the new
-- refusal. Validation reads existing rows and fails the migration, changing
-- nothing, if one breaks the rule. Read-only pre-check, expecting no rows:
--
--   select id, unit from recipe_measure
--    where coalesce(unit_family(unit) in ('mass','volume','count'), false)
--          is false;
--
-- The catalog comments are restated to stand on their own for a reader who
-- has the database and not the source.

alter table recipe_measure
  drop constraint recipe_measure_unit_can_measure;
alter table recipe_measure
  add constraint recipe_measure_unit_can_measure check (
    coalesce(unit_family(unit) in ('mass', 'volume', 'count'), false)
  );

comment on table recipe_measure is
  'A household word for one of what a recipe makes ("blob", "ladle"), so a '
  'component line in another recipe can say "3 blob". A named amount, like '
  'ingredient_measure: amount + unit. No unique index on (recipe_id, label), '
  'so two offline devices coining the same word both upload; duplicates merge '
  'on read, oldest row canonical.';

comment on column recipe_measure.label is
  'The word as the household typed it. Free text; nothing parses it.';

comment on column recipe_measure.amount is
  'What one of this measure comes to, in `unit` (a blob is 15 g). Absolute: '
  're-stating the recipe''s yield changes the share of a batch it is, never '
  'this number.';

comment on column recipe_measure.unit is
  'A unit id as recipe_line_item.unit holds them, in a mass, volume or count '
  'family (unit_family). The app also requires the recipe to state a yield in '
  'that family.';

comment on column recipe_measure.sort_order is
  'Display order. The first measure leads the choices on a component line.';

comment on column recipe_line_item.recipe_measure_id is
  'The sub-recipe''s own measure this component line is counted in '
  '("3 blob"). Needs sub_recipe_id and quantity, excludes unit, and must be a '
  'measure of that sub-recipe (recipe_line_item_recipe_measure_guard). A line '
  'whose measure is tombstoned is unresolved, never re-read as a count.';

comment on column week_recipe_line_override.recipe_measure_id is
  'The sub-recipe''s own measure this week''s amount is counted in. Same '
  'rules and trigger as recipe_line_item.recipe_measure_id.';
