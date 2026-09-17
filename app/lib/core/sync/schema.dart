/// PowerSync client-side schema — the local SQLite mirror.
///
/// Every table here is **synced**: the session controller connects the database
/// with `AnsiConnector` once a user is signed in, so local writes queue for
/// upload and the server's rows stream down. Each table mirrors its migration
/// and is scoped to the household (the sync rules in `docker/powersync.yaml`
/// filter every bucket to the JWT's `household_id`).
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
    Column.text('steps'), // JSON: step token arrays (step 8) / legacy text
    Column.integer('keeps_for_days'),
    Column.integer('freezable'), // 0/1
    Column.integer('freezer_days'),
    Column.integer('cook_time_seconds'), // printed cook time (step 8)
    Column.integer('total_time_seconds'), // printed total time (step 8)
    Column.text('book_id'), // → book.id (nullable)
    Column.text(
      'section_id',
    ), // → book_section.id (nullable; null = Unsectioned)
    Column.integer('favorite'), // 0/1 — the picker's Favorites tab (step 7.7)
    // What one batch MAKES (step 8.6 / 0017) — "makes 1 cup", "makes 8 piece".
    // Nullable and independent of servings_base; the optional second pair
    // states the same batch in a DIFFERENT unit family ("250 g · 16 tbsp"),
    // which is the only mass↔volume bridge a recipe has.
    Column.real('yield_qty'),
    Column.text('yield_unit'),
    Column.real('yield_qty_2'),
    Column.text('yield_unit_2'),
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
    // → recipe.id (nullable, step 8.6 / 0017). A line is an ingredient OR a
    // sub-recipe component, never both and never neither (the server's XOR
    // check); a component line never carries a measure_id.
    Column.text('sub_recipe_id'),
    Column.real('quantity'),
    Column.text('unit'),
    Column.text('measure_id'), // → ingredient_measure.id (nullable, step 7.6)
    Column.text('note'),
    Column.integer('sort_order'),
    // 0/1: the recipe says this line may be left out. Excluded from macros and
    // the shop list and NAMED there; the cook plan ignores it. Same 0/1 shape
    // as `favorite` and `freezable`.
    Column.integer('optional'),
    ..._audit,
  ]),

  // Week planning (step 4). The active week and its planned meals.
  Table('week_plan', [
    Column.text('household_id'),
    // ISO date of the day this week begins on — the household's own first
    // day (`household.week_starts_on`), not always a Monday.
    Column.text('week_start_date'),
    Column.text('label'),
    ..._audit,
  ]),
  Table('plan_entry', [
    Column.text('household_id'),
    Column.text('week_plan_id'),
    Column.integer('day_of_week'), // offset from week_start_date, 0..6
    Column.text('meal_slot'), // free text, not a preset enum
    // A meal is a recipe, a bare ingredient OR words eaten out — never two of
    // them and never none (the server's three-way XOR check). All three
    // columns are nullable here, so every reader must branch on the KIND: a
    // null `recipe_id` means "look at the other two", never "skip".
    Column.text('recipe_id'),
    Column.text('ingredient_id'), // → ingredient.id
    Column.text('label'), // the words a meal eaten out IS
    // The amount of ONE portion of an ingredient meal; null on a recipe meal,
    // whose amount is its `portions`, and on a meal eaten out, which states
    // its macros instead.
    Column.real('quantity'),
    Column.text('unit'),
    Column.text('measure_id'), // → ingredient_measure.id (nullable)
    // Macros of ONE portion of a meal eaten out, as stated — the vocabulary's
    // `{kcal, protein, carb, fat}` shape, per portion rather than per 100.
    // Null means not stated, and the week names the refusal.
    Column.text('macros'),
    Column.text('eaters'), // JSON array of household_member ids
    Column.integer('portions'), // null → defaults to |eaters|
    Column.integer('sort_order'),
    ..._audit,
  ]),
  // One delta against a recipe line for ONE planned week (0040). Keyed on
  // (week_plan, recipe) — every day that plans the recipe that week cooks the
  // same lines, so the cook plan still batches them into one pot. Amounts are
  // absolute: the recipe moving later leaves this week where it was put.
  Table('week_recipe_line_override', [
    Column.text('household_id'),
    Column.text('week_plan_id'), // → week_plan.id
    Column.text('recipe_id'), // → recipe.id
    // → recipe_line_item.id, null exactly when `action` is 'add'.
    Column.text('recipe_line_item_id'),
    // 'include' | 'exclude' | 'replace' | 'add'.
    Column.text('action'),
    Column.text('ingredient_id'),
    // Ships as a column only in v1 — the component graph knows no week.
    Column.text('sub_recipe_id'),
    Column.real('quantity'),
    Column.text('unit'),
    Column.text('measure_id'),
    Column.text('note'),
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
    // The first day of the week this entry belongs to — every entry carries
    // one, a free-text non-food item included. Null is only a legacy row an
    // older client wrote; the server stamps those onto the week they were
    // created in.
    Column.text('week_start_date'),
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
    Column.text('macros_basis'), // 'g' | 'ml' — the per-100 basis (step 7.7)
    // Explicit allowed-unit list (JSON array of unit ids, ADR-0008 / 0012);
    // null → the client derives the same defaults.
    Column.text('allowed_units'),
    // What ONE of this row weighs, in the basis unit (0039 / ADR-0015) — the
    // count fact the way `density_g_per_ml` is the volume fact; `piece` is
    // sayable only while it is set. `piece_source` says where it came from
    // ('manual' / 'borrowed from <label>' / 'seed:typical').
    Column.real('piece_basis_amount'),
    Column.text('piece_source'),
    Column.text('status'),
    Column.text('source'),
    // The USDA food a prefill copied from, and how much of the query its
    // description covered (0027) — written beside `source` by the prefill
    // writers so the form can name the match offline. Null where nothing filled
    // the row or the fill predates 0027.
    Column.text('source_label'),
    Column.real('source_score'),
    // 0/1 (0034): a human has overridden the numbers the lookup filled —
    // macros, basis or density. Only a write that touches one of those sets
    // it; a rename never does, and a fresh pick clears it.
    Column.integer('source_edited'),
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
  // Named per-ingredient measures ("potato, large = 299 g") — the honest
  // count↔basis bridge (step 7.6; basis-aware amounts since 7.8/0012: the
  // amount is in the ingredient's macros_basis unit). Synced with the vocab.
  Table('ingredient_measure', [
    Column.text('household_id'),
    Column.text('ingredient_id'),
    Column.text('label'),
    Column.real('basis_amount'),
    Column.integer('sort_order'),
    Column.text('source'), // amount provenance ("usda_fdc:…", "manual", …)
    ..._audit,
  ]),

  // Household members — synced (step 7). Created server-side at onboarding
  // (`ensure_onboarded`, migration 0007); the client reads them (eaters on a
  // plan_entry reference these ids) and writes exactly one column,
  // `portion_factor` (0026 — the Household sheet; the server grants UPDATE on
  // that column alone). `auth_user_id` stays server-only: the sync rule for
  // this table selects an explicit column list that excludes it
  // (docker/powersync.yaml) — what a rule SELECTs is exactly what ships to the
  // device, so omitting the column here alone would not keep it off the wire.
  Table('household_member', [
    Column.text('household_id'),
    Column.text('display_name'),
    Column.integer('sort_order'),
    Column.real('portion_factor'), // a usual portion, ×1 by default (0026)
    ..._audit,
  ]),

  // The household itself — synced so its name is available offline. The
  // server-only columns its `select *` sync rule ships (`is_template`,
  // `backfilled_at`) are simply not declared here: the client view exposes
  // exactly the declared columns and ignores the rest of the row JSON.
  //
  // `week_starts_on` is the ISO weekday the household's week begins on
  // (1=Mon..7=Sun). The phone only ever READS it: flipping it re-homes every
  // week the household has planned, which is one server transaction
  // (`set_household_week_start`), so a local write would put this device's
  // keys out of step with its own rows.
  Table('household', [
    Column.text('name'),
    Column.integer('week_starts_on'),
    ..._audit,
  ]),
]);
