<!-- GENERATED FILE — do not edit. Regenerate with `make docs` (scripts/gen_docs.sh). -->
# Database schema (generated)

Parsed from `supabase/migrations/*.sql` (16 migrations, 15 tables). Per table: columns from `create table` plus later `alter table add column`s, whether RLS is enabled, whether the table is in the `powersync` publication, and the migration that introduced it.

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
| `ingredient_id` | `uuid` | no | not null references ingredient(id) |
| `quantity` | `numeric` | yes |  |
| `unit` | `text` | no | not null |
| `note` | `text` | yes |  |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `measure_id` | `uuid` | yes | references ingredient_measure(id) *(added in `0009_ingredient_measures.sql`)* |

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
| `recipe_id` | `uuid` | no | not null references recipe(id) |
| `eaters` | `jsonb` | no | not null default '[]'::jsonb |
| `portions` | `int` | yes |  |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |

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
| `grams` | `numeric` | no | not null check (grams > 0) |
| `sort_order` | `int` | no | not null default 0 |
| `created_at` | `timestamptz` | no | not null default now() |
| `updated_at` | `timestamptz` | no | not null default now() |
| `deleted_at` | `timestamptz` | yes |  |
| `source` | `text` | yes | *(added in `0010_measure_provenance.sql`)* |
| `basis_amount` | `numeric` | yes | *(added in `0012_unit_admission.sql`)* |
