<!-- GENERATED FILE — do not edit. Regenerate with `make docs` (scripts/gen_docs.sh). -->
# Database schema (generated)

Parsed from `supabase/migrations/*.sql` (47 migrations, 22 tables). Per table: columns from `create table` plus later `alter table add column`s, whether RLS is enabled, whether the table is in the `powersync` publication, and the migration that introduced it.

**Limitations (honest 90% parse):** indexes, RLS policy bodies, grants,
functions, triggers, and seed data are not listed — read the migration for
those. Column types/details are shown as written, not introspected from a
live database.

## `household`

introduced in `0001_household.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `name` | `text` | no | not null |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `is_template` | `boolean` | no | not null default false *(added in `0008_onboarding_hardening.sql`)* |
| `backfilled_at` | `timestamptz` | yes | *(added in `0011_picker_uplift.sql`)* |
| `week_starts_on` | `smallint` | no | not null default 1 check (week_starts_on between 1 and 7) *(added in `0043_household_week_start.sql`)* |

## `household_member`

introduced in `0001_household.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `display_name` | `text` | no | not null |
| `auth_user_id` | `uuid` | no | not null references auth.users(id) |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `sort_order` | `int` | no | not null default 0 *(added in `0007_sync.sql`)* |
| `portion_factor` | `numeric(4,2)` | no | not null default 1 constraint household_member_portion_factor_range check (portion_factor >= 0.25 and portion_factor <= 3) *(added in `0026_portion_factor.sql`)* |

Table constraints: `unique (household_id, auth_user_id)`

## `ingredient`

introduced in `0002_ingredients.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `canonical_name` | `text` | no | not null |
| `category` | `text` | yes |  |
| `default_unit` | `text` | no | not null |
| `density_g_per_ml` | `numeric` | yes |  |
| `macros` | `jsonb` | yes |  |
| `status` | `text` | no | not null default 'stub' check (status in ('complete', 'stub')) |
| `source` | `text` | yes |  |
| `match_text` | `text` | no | not null |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `macros_basis` | `text` | no | not null default 'g' check (macros_basis in ('g', 'ml')) *(added in `0011_picker_uplift.sql`)* |
| `allowed_units` | `jsonb` | yes | *(added in `0012_unit_admission.sql`)* |
| `source_label` | `text` | yes | *(added in `0027_usda_source_label.sql`)* |
| `source_score` | `real` | yes | *(added in `0027_usda_source_label.sql`)* |
| `source_edited` | `boolean` | no | not null default false *(added in `0034_source_edited.sql`)* |
| `piece_basis_amount` | `numeric` | yes | *(added in `0039_piece_weight.sql`)* |
| `piece_source` | `text` | yes | *(added in `0039_piece_weight.sql`)* |

## `ingredient_alias`

introduced in `0002_ingredients.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `ingredient_id` | `uuid` | no | not null references ingredient(id) on delete cascade |
| `alias_text` | `text` | no | not null |
| `match_text` | `text` | no | not null |
| `source` | `text` | no | not null check (source in ('seed', 'import_correction', 'manual')) |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

## `usda_food`

introduced in `0002_ingredients.sql` · RLS enabled

| Column | Type | Nullable | Details |
|---|---|---|---|
| `fdc_id` | `int` | no | primary key |
| `description` | `text` | no | not null |
| `category` | `text` | yes |  |
| `density_g_per_ml` | `numeric` | yes |  |
| `macros` | `jsonb` | yes |  |
| `match_text` | `text` | no | not null |

## `recipe`

introduced in `0003_recipes.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `title` | `text` | no | not null |
| `servings_base` | `numeric` | no | not null default 1 check (servings_base > 0) |
| `steps` | `jsonb` | no | not null default '[]'::jsonb |
| `keeps_for_days` | `int` | yes |  |
| `freezable` | `boolean` | no | not null default false |
| `freezer_days` | `int` | yes |  |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `book_id` | `uuid` | yes | references book(id) *(added in `0004_books.sql`)* |
| `section_id` | `uuid` | yes | references book_section(id) *(added in `0004_books.sql`)* |
| `favorite` | `boolean` | no | not null default false *(added in `0011_picker_uplift.sql`)* |
| `cook_time_seconds` | `int` | yes | check (cook_time_seconds is null or cook_time_seconds >= 0) *(added in `0013_recipe_times.sql`)* |
| `total_time_seconds` | `int` | yes | check (total_time_seconds is null or total_time_seconds >= 0) *(added in `0013_recipe_times.sql`)* |
| `yield_qty` | `numeric` | yes | check (yield_qty is null or yield_qty > 0) *(added in `0017_nested_recipes.sql`)* |
| `yield_unit` | `text` | yes | *(added in `0017_nested_recipes.sql`)* |
| `yield_qty_2` | `numeric` | yes | check (yield_qty_2 is null or yield_qty_2 > 0) *(added in `0017_nested_recipes.sql`)* |
| `yield_unit_2` | `text` | yes | *(added in `0017_nested_recipes.sql`)* |

## `ingredient_group`

introduced in `0003_recipes.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `recipe_id` | `uuid` | no | not null references recipe(id) on delete cascade |
| `name` | `text` | yes |  |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

## `recipe_line_item`

introduced in `0003_recipes.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `group_id` | `uuid` | no | not null references ingredient_group(id) on delete cascade |
| `ingredient_id` | `uuid` | yes | references ingredient(id) *(nullable since `0017_nested_recipes.sql`)* |
| `quantity` | `numeric` | yes |  |
| `unit` | `text` | no | not null |
| `note` | `text` | yes |  |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `measure_id` | `uuid` | yes | references ingredient_measure(id) *(added in `0009_ingredient_measures.sql`)* |
| `sub_recipe_id` | `uuid` | yes | references recipe(id) *(added in `0017_nested_recipes.sql`)* |
| `optional` | `boolean` | no | not null default false *(added in `0025_optional_line.sql`)* |

## `book`

introduced in `0004_books.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `name` | `text` | no | not null |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

## `book_section`

introduced in `0004_books.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `book_id` | `uuid` | no | not null references book(id) on delete cascade |
| `name` | `text` | no | not null |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

## `week_plan`

introduced in `0005_planning.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `week_start_date` | `date` | no | not null |
| `label` | `text` | yes |  |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

Table constraints: `unique (household_id, week_start_date)`

## `plan_entry`

introduced in `0005_planning.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `week_plan_id` | `uuid` | no | not null references week_plan(id) on delete cascade |
| `day_of_week` | `int` | no | not null check (day_of_week between 0 and 6) |
| `meal_slot` | `text` | no | not null |
| `recipe_id` | `uuid` | yes | references recipe(id) *(nullable since `0033_plan_ingredient.sql`)* |
| `eaters` | `jsonb` | no | not null default '[]'::jsonb |
| `portions` | `int` | yes |  |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `ingredient_id` | `uuid` | yes | references ingredient(id) *(added in `0033_plan_ingredient.sql`)* |
| `quantity` | `numeric` | yes | check (quantity is null or quantity > 0) *(added in `0033_plan_ingredient.sql`)* |
| `unit` | `text` | yes | *(added in `0033_plan_ingredient.sql`)* |
| `measure_id` | `uuid` | yes | references ingredient_measure(id) *(added in `0033_plan_ingredient.sql`)* |
| `label` | `text` | yes | check (label is null or length(btrim(label)) > 0) *(added in `0045_plan_entry_out.sql`)* |
| `macros` | `jsonb` | yes | *(added in `0045_plan_entry_out.sql`)* |

## `shopping_list_entry`

introduced in `0006_shopping.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `ingredient_id` | `uuid` | yes | references ingredient(id) |
| `free_text` | `text` | yes |  |
| `category` | `text` | yes |  |
| `checked` | `boolean` | no | not null default false |
| `unit` | `text` | yes |  |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `week_start_date` | `date` | yes | *(added in `0019_shopping_week.sql`)* |

Table constraints: `check ((ingredient_id is not null) <> (free_text is not null))`

## `shopping_list_contribution`

introduced in `0006_shopping.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `entry_id` | `uuid` | no | not null references shopping_list_entry(id) on delete cascade |
| `source_type` | `text` | no | not null default 'manual' check (source_type in ('cook_session', 'manual')) |
| `source_cook_session_id` | `text` | yes |  |
| `quantity` | `numeric` | yes |  |
| `unit` | `text` | yes |  |
| `note` | `text` | yes |  |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `measure_id` | `uuid` | yes | references ingredient_measure(id) *(added in `0009_ingredient_measures.sql`)* |

## `ingredient_measure`

introduced in `0009_ingredient_measures.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `ingredient_id` | `uuid` | no | not null references ingredient(id) on delete cascade |
| `label` | `text` | no | not null |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `source` | `text` | yes | *(added in `0010_measure_provenance.sql`)* |
| `basis_amount` | `numeric` | no | not null *(added in `0012_unit_admission.sql`)* |

## `usda_search_token`

introduced in `0029_usda_search_ranking.sql` · RLS enabled

| Column | Type | Nullable | Details |
|---|---|---|---|
| `fdc_id` | `int` | no | not null references usda_food(fdc_id) on delete cascade |
| `tok` | `text` | no | not null |
| `pos` | `int` | no | not null |

Table constraints: `primary key (fdc_id, tok)`

## `usda_search_term`

introduced in `0029_usda_search_ranking.sql` · RLS enabled

| Column | Type | Nullable | Details |
|---|---|---|---|
| `tok` | `text` | no | primary key |
| `df` | `int` | no | not null |
| `idf` | `real` | no | not null |

## `usda_search_doc`

introduced in `0029_usda_search_ranking.sql` · RLS enabled

| Column | Type | Nullable | Details |
|---|---|---|---|
| `fdc_id` | `int` | no | primary key references usda_food(fdc_id) on delete cascade |
| `dl` | `int` | no | not null |

## `usda_search_stats`

introduced in `0029_usda_search_ranking.sql` · RLS enabled

| Column | Type | Nullable | Details |
|---|---|---|---|
| `only_row` | `bool` | no | primary key default true check (only_row) |
| `n_docs` | `int` | no | not null |
| `avg_doc_len` | `real` | no | not null |

## `week_recipe_line_override`

introduced in `0040_week_recipe_line_override.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) on delete cascade |
| `week_plan_id` | `uuid` | no | not null references week_plan(id) on delete cascade |
| `recipe_id` | `uuid` | no | not null references recipe(id) on delete cascade |
| `recipe_line_item_id` | `uuid` | yes | references recipe_line_item(id) on delete cascade |
| `action` | `text` | no | not null check (action in ('include', 'exclude', 'replace', 'add')) |
| `ingredient_id` | `uuid` | yes | references ingredient(id) |
| `sub_recipe_id` | `uuid` | yes | references recipe(id) |
| `quantity` | `numeric` | yes | check (quantity is null or quantity > 0) |
| `unit` | `text` | yes |  |
| `measure_id` | `uuid` | yes | references ingredient_measure(id) |
| `note` | `text` | yes |  |
| `sort_order` | `integer` | yes |  |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

Table constraints: `constraint week_recipe_line_override_one_per_line unique (week_plan_id, recipe_id, recipe_line_item_id)`; `constraint week_recipe_line_override_action_shape check ( case action when 'include' then recipe_line_item_id is not null and num_nonnulls(ingredient_id, sub_recipe_id, quantity, unit, measure_id, note) = 0 when 'exclude' then recipe_line_item_id is not null and num_nonnulls(ingredient_id, sub_recipe_id, quantity, unit, measure_id, note) = 0 when 'replace' then recipe_line_item_id is not null and num_nonnulls(ingredient_id, sub_recipe_id) = 1 when 'add' then recipe_line_item_id is null and num_nonnulls(ingredient_id, sub_recipe_id) = 1 end )`; `constraint week_recipe_line_override_component_has_no_measure check (sub_recipe_id is null or measure_id is null)`; `constraint week_recipe_line_override_amount_pair check (num_nonnulls(quantity, unit) <> 1)`; `constraint week_recipe_line_override_measure_needs_amount check (measure_id is null or quantity is not null)`

## `receipt`

introduced in `0044_receipts.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `store` | `text` | no | not null |
| `purchased_at` | `timestamptz` | no | not null |
| `subtotal_cents` | `int` | yes |  |
| `tax_cents` | `int` | yes |  |
| `total_cents` | `int` | yes |  |
| `source` | `text` | no | not null check (source in ('manual', 'photo')) |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

## `receipt_line`

introduced in `0044_receipts.sql` · RLS enabled · in the `powersync` publication

| Column | Type | Nullable | Details |
|---|---|---|---|
| `id` | `uuid` | no | primary key default gen_random_uuid() |
| `household_id` | `uuid` | no | not null references household(id) |
| `receipt_id` | `uuid` | no | not null references receipt(id) |
| `ingredient_id` | `uuid` | yes | references ingredient(id) |
| `printed_text` | `text` | yes |  |
| `cents` | `int` | no | not null |
| `discount_cents` | `int` | no | not null default 0 check (discount_cents >= 0) |
| `kind` | `text` | no | not null check (kind in ('item', 'not_food', 'tax', 'fee')) |
| `pack_basis_amount` | `numeric` | yes | check (pack_basis_amount > 0) |
| `measure_id` | `uuid` | yes | references ingredient_measure(id) |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `pack_amount` | `numeric` | yes | check (pack_amount > 0) *(added in `0046_receipt_line_pack_as_entered.sql`)* |
| `pack_unit` | `text` | yes | *(added in `0046_receipt_line_pack_as_entered.sql`)* |

Table constraints: `constraint receipt_line_only_items_are_priced check ( kind = 'item' or (ingredient_id is null and pack_basis_amount is null and measure_id is null) )`
