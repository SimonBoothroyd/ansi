-- 0013_recipe_times.sql — printed cook time + total time on recipes
-- (roadmap step 8, import foundation — exec plan 0014).
--
-- Import reads a page's printed "Cook time" / "Total time" banners and keeps
-- them (nutrition banners are ignored — we compute macros ourselves; a printed
-- number we can't verify would violate the never-invent invariant). These are
-- the ONE schema change the import foundation needs: everything else it needs
-- already exists (steps are jsonb, line-items carry UUIDs, ingredient.source
-- already allows 'import_stub', ingredient_alias.source allows
-- 'import_correction'), and the tokenized-step shape is a jsonb content change,
-- not a column change.
--
-- Both are nullable integer SECONDS. Extraction may carry a printed *range*
-- (import-and-matching §4.4); the recipe stores a single value (the low bound on
-- the rare ranged banner), consistent with how qty ranges resolve before commit.
-- No RLS/grant change: columns inherit the recipe table's policies, and recipe
-- is already in the powersync publication (0003).

alter table recipe
  add column cook_time_seconds  int check (cook_time_seconds  is null or cook_time_seconds  >= 0),
  add column total_time_seconds int check (total_time_seconds is null or total_time_seconds >= 0);
