/// PowerSync client-side schema — the local SQLite mirror.
///
/// Every table here is **synced** (step 7): `bootstrap` calls `db.connect()`
/// with the `MiseConnector` once a user is signed in, so local writes queue for
/// upload and the server's rows stream down. Each table mirrors its migration
/// and is scoped to the household (the sync rules in `docker/powersync.yaml`
/// filter every bucket to the JWT's `household_id`).
///
/// `ingredient`/`ingredient_alias`/`household_member`/`household` used to be
/// `Table.localOnly` (bootstrap-seeded before auth existed); step 7 flipped
/// them to synced, fed by the server (`ensure_onboarded` seeds the vocab),
/// and dropped the seeders. The vocab now carries server-resolved macros.
///
/// Every table gets an implicit `id` TEXT primary key — do not declare it.
/// `usda_food` and the match indexes never live on-device (ADR-0004/0005).
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
    Column.text('measure_id'), // → ingredient_measure.id (nullable, step 7.6)
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

  // Shopping list (step 6). Only the parts of the list that can't be re-derived
  // from the cook plan: check-off state + manual/free-text contributions. The
  // `cook_session` contributions are derived live (spec §4), never stored.
  Table('shopping_list_entry', [
    Column.text('household_id'),
    Column.text('ingredient_id'), // null for a free-text (non-food) item
    Column.text('free_text'), // null for an ingredient
    Column.text('category'), // aisle group for a free-text item
    Column.integer('checked'), // 0/1 — check-off is on the entry
    Column.text('unit'), // preferred display unit (nullable)
    ..._audit,
  ]),
  Table('shopping_list_contribution', [
    Column.text('household_id'),
    Column.text('entry_id'),
    Column.text('source_type'), // 'manual' | 'cook_session' (v1 stores manual)
    Column.text('source_cook_session_id'), // null in v1 (cook plan is derived)
    Column.real('quantity'), // nullable (a bare non-food item)
    Column.text('unit'),
    Column.text('measure_id'), // → ingredient_measure.id (nullable, step 7.6)
    Column.text('note'),
    ..._audit,
  ]),

  // Vocab — synced from the server (step 7). Owned by the household; the server
  // holds USDA-resolved macros/density, which now ride down. `macros` is the
  // server's JSONB serialized to text. `usda_food` is never here (ADR-0005).
  Table('ingredient', [
    Column.text('household_id'),
    Column.text('canonical_name'),
    Column.text('category'),
    Column.text('default_unit'),
    Column.real('density_g_per_ml'),
    Column.text('macros'), // JSON {kcal, protein, carb, fat}; null when stub
    Column.text('status'),
    Column.text('source'),
    Column.text('match_text'),
    ..._audit,
  ]),
  Table('ingredient_alias', [
    Column.text('household_id'),
    Column.text('ingredient_id'),
    Column.text('alias_text'),
    Column.text('match_text'),
    Column.text('source'),
    ..._audit,
  ]),
  // Named per-ingredient measures with gram weights ("potato, large = 299 g")
  // — the honest count↔mass bridge (step 7.6). Synced with the vocab.
  Table('ingredient_measure', [
    Column.text('household_id'),
    Column.text('ingredient_id'),
    Column.text('label'),
    Column.real('grams'),
    Column.integer('sort_order'),
    ..._audit,
  ]),

  // Household members — synced (step 7). Created server-side at onboarding
  // (`ensure_onboarded`, migration 0007); the client reads them (eaters on a
  // plan_entry reference these ids) but never writes them. `auth_user_id`
  // stays server-only: the sync rule for this table selects an explicit
  // column list that excludes it (docker/powersync.yaml) — what a rule
  // SELECTs is exactly what ships to the device, so omitting the column here
  // alone would not keep it off the wire.
  Table('household_member', [
    Column.text('household_id'),
    Column.text('display_name'),
    Column.integer('sort_order'),
    ..._audit,
  ]),

  // The household itself — synced so its name is available offline.
  Table('household', [Column.text('name'), ..._audit]),
]);
