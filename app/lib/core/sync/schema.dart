/// PowerSync client-side schema — the local SQLite mirror.
///
/// Step 2 opens this database but never calls `.connect()` (see the step-2 exec
/// plan): recipes persist locally and nothing syncs yet. The tables are still
/// declared as they'll sync so step 7 only has to connect.
///
/// Two flavours here:
/// - **Synced tables** (`book`, `book_section`, `recipe`, `ingredient_group`,
///   `recipe_line_item`) mirror migrations 0003/0004. Local writes queue for
///   upload; harmless offline.
/// - **Local-only tables** (`ingredient`, `ingredient_alias`,
///   `household_member`) are bootstrap-seeded on first run (nothing syncs
///   them). `localOnly` keeps these fake reference rows OUT of the upload
///   queue. `ingredient*` come from the bundled vocab (migration 0002);
///   `household_member` is seeded with two local members because the real
///   table (migration 0001) has an `auth_user_id → auth.users` FK that cannot
///   exist before auth. Step 7 flips all three to synced tables fed by the
///   server and drops the seeders.
///
/// Every table gets an implicit `id` TEXT primary key — do not declare it.
/// `usda_food` and match indexes never live on-device (ADR-0004/0005).
library;

import 'package:powersync/powersync.dart';

/// Timestamp + soft-delete columns every synced domain row carries.
const _audit = [
  Column.text('created_at'),
  Column.text('updated_at'),
  Column.text('deleted_at'),
];

const schema = Schema([
  // A named collection of recipes ("Our Cookbook") holding user sections.
  Table('book', [
    Column.text('household_id'),
    Column.text('name'),
    Column.integer('sort_order'),
    ..._audit,
  ]),
  // A user-named section within a book ("Weeknight") — not a preset enum.
  Table('book_section', [
    Column.text('household_id'),
    Column.text('book_id'),
    Column.text('name'),
    Column.integer('sort_order'),
    ..._audit,
  ]),
  Table('recipe', [
    Column.text('household_id'),
    Column.text('title'),
    Column.real('servings_base'),
    Column.text('steps'), // JSON array of step strings
    Column.integer('keeps_for_days'),
    Column.integer('freezable'), // 0/1
    Column.integer('freezer_days'),
    Column.text('book_id'), // → book.id (nullable)
    Column.text(
      'section_id',
    ), // → book_section.id (nullable; null = Unsectioned)
    ..._audit,
  ]),
  Table('ingredient_group', [
    Column.text('household_id'),
    Column.text('recipe_id'),
    Column.text('name'),
    Column.integer('sort_order'),
    ..._audit,
  ]),
  Table('recipe_line_item', [
    Column.text('household_id'),
    Column.text('group_id'),
    Column.text('ingredient_id'),
    Column.real('quantity'),
    Column.text('unit'),
    Column.text('note'),
    Column.integer('sort_order'),
    ..._audit,
  ]),

  // Week planning (step 4). The active week and its planned meals.
  Table('week_plan', [
    Column.text('household_id'),
    Column.text('week_start_date'), // ISO date of the Monday this week begins
    Column.text('label'),
    ..._audit,
  ]),
  Table('plan_entry', [
    Column.text('household_id'),
    Column.text('week_plan_id'),
    Column.integer('day_of_week'), // 0=Monday .. 6=Sunday
    Column.text('meal_slot'), // free text, not a preset enum
    Column.text('recipe_id'),
    Column.text('eaters'), // JSON array of household_member ids
    Column.integer('portions'), // null → defaults to |eaters|
    Column.integer('sort_order'),
    ..._audit,
  ]),

  // Vocab — local-only for step 2 (bundle-loaded; becomes synced in step 7).
  Table.localOnly('ingredient', [
    Column.text('household_id'),
    Column.text('canonical_name'),
    Column.text('category'),
    Column.text('default_unit'),
    Column.real('density_g_per_ml'),
    Column.text('status'),
    Column.text('source'),
    Column.text('match_text'),
  ]),
  Table.localOnly('ingredient_alias', [
    Column.text('ingredient_id'),
    Column.text('alias_text'),
    Column.text('match_text'),
  ]),

  // Household members — local-only for step 4 (bootstrap-seeded; becomes synced
  // in step 7 once auth exists, migration 0001). `eaters` on a plan_entry
  // references these ids. No `auth_user_id` here: local members carry none.
  Table.localOnly('household_member', [
    Column.text('household_id'),
    Column.text('display_name'),
    Column.integer('sort_order'),
  ]),
]);
