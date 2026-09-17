-- 0045_plan_entry_out.sql — a plan slot takes a meal eaten out: a label, its
-- eaters, and the macros the canteen printed when it printed any.
--
-- The third kind of planned meal, beside a recipe (0005) and a bare ingredient
-- (0033). An office lunch is neither cooked nor bought, so dressing it up as a
-- one-line recipe or as a stub ingredient nobody will flesh out puts a thing
-- in the Library or the vocabulary that the household does not own. It is a
-- meal, so it fills its slot, carries eaters and multiplies; it is nothing
-- else, so the cook plan and the shopping list pass over it by name.
--
-- The entry XOR becomes THREE-way. 0033's `num_nonnulls(recipe_id,
-- ingredient_id) = 1` is dropped and replaced rather than added to, because a
-- row that names a label satisfies neither half of the old check — the
-- constraint is the one place the "never both and never neither" promise
-- lives, and two checks arguing about it is how a hole opens.
--
-- What this migration is NOT:
--
--   * **Not a vocabulary row** (owner-ruled). A meal out is a label and its
--     figures, not a thing the household owns, so nothing is minted anywhere:
--     no `ingredient`, no measure, no alias.
--   * **Not a recurrence.** Copy last week is the repeat, and it carries these
--     columns like every other (the copy takes `plan_entry` columns).
--   * **Not a sync-rule change.** Both stream YAMLs select `*` from
--     `plan_entry`, so `docker/powersync.yaml` and
--     `docker/powersync-cloud.streams.yaml` carry these columns without an
--     edit (the 0017 / 0033 precedent). No RLS, grant or publication change
--     either: the table already carries household-scoped policies and is in
--     the `powersync` publication (0005).
--
-- `macros` is the `{kcal, protein, carb, fat}` shape the vocabulary stores,
-- with the same optional `fiber` key — one macro shape in the schema, so the
-- client parses it with the parser it already has. It is PER PORTION, not per
-- 100 of anything: a canteen prints what the plate was, and the week
-- multiplies it by the portions the entry plans, exactly as it multiplies a
-- recipe's per-serving figure.

alter table plan_entry
  -- The words themselves, when the meal IS its words. Blank is not a label:
  -- `num_nonnulls` counts an empty string, so an entry could otherwise satisfy
  -- the XOR while naming nothing.
  add column label text check (label is null or length(btrim(label)) > 0),

  -- Per-portion macros, as stated. NULL means NOT STATED — never zero
  -- (invariant 3): the week counts a meal out only from figures somebody
  -- typed, and names the refusal otherwise.
  add column macros jsonb;

alter table plan_entry
  drop constraint plan_entry_target_xor;

alter table plan_entry
  -- The three-way XOR. A reader that finds none of the three has nothing to
  -- eat; one that finds two has two answers to the same question.
  add constraint plan_entry_target_xor
    check (num_nonnulls(recipe_id, ingredient_id, label) = 1),

  -- Figures without a meal they describe are a fact with no subject. A
  -- recipe's macros are its lines' and an ingredient's are its row's, so this
  -- column speaks on the label side only.
  add constraint plan_entry_macros_is_for_label
    check (label is not null or macros is null);

comment on column plan_entry.label is
  'The words a meal eaten out IS — "Office lunch" — when the meal is neither '
  'a recipe nor a bare ingredient. Exactly one of recipe_id / ingredient_id / '
  'label is set (plan_entry_target_xor). It fills its slot and carries eaters '
  'like any entry; the cook plan and the shopping list ignore it, because '
  'nothing about it is cooked or bought.';

comment on column plan_entry.macros is
  'Macros of ONE portion of a meal eaten out, in ingredient.macros'' shape '
  '({kcal, protein, carb, fat}, with the optional fiber key) — but per '
  'portion, not per 100. NULL means the figures were not stated: the week '
  'names the meal as uncounted rather than weighing it at zero.';

comment on column plan_entry.recipe_id is
  'The dish this meal is, or NULL when the meal is a bare ingredient or one '
  'eaten out. Exactly one of recipe_id / ingredient_id / label is set — '
  'plan_entry_target_xor. Every derivation branches on the KIND explicitly: '
  'the cook plan ignores an ingredient and a meal out (nothing is cooked), '
  'the shopping list ignores a meal out (nothing is bought), and the week''s '
  'macros weigh each kind in its own way.';
