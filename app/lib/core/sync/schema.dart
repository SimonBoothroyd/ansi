/// PowerSync client-side schema: the local SQLite mirror.
///
/// Every table is synced and household-scoped (sync rules in
/// `docker/powersync.yaml`), and mirrors its migration. Each gets an implicit
/// `id` TEXT primary key; do not declare it. `usda_food` and the match
/// indexes never live on-device (ADR-0004, ADR-0005).
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
    // What one batch makes ("makes 1 cup"). Nullable and independent of
    // servings_base. The optional second pair states the same batch in a
    // different unit family, the recipe's only mass↔volume bridge.
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
  // A household word for one of what a recipe makes ("blob" = 15 g), so a
  // component line can say "3 blob". `unit` is a units.dart id; the amount is
  // absolute. Duplicate labels are legal and merge on read, oldest canonical,
  // so an offline duplicate never fails upload.
  Table('recipe_measure', [
    Column.text('household_id'),
    Column.text('recipe_id'),
    Column.text('label'),
    Column.real('amount'),
    Column.text('unit'),
    Column.integer('sort_order'),
    ..._audit,
  ]),
  Table('recipe_line_item', [
    Column.text('household_id'),
    Column.text('group_id'),
    Column.text('ingredient_id'),
    // → recipe.id. A line is an ingredient XOR a sub-recipe component (server
    // check); a component line never carries a measure_id.
    Column.text('sub_recipe_id'),
    Column.real('quantity'),
    // A units.dart id; null exactly when `recipe_measure_id` is set.
    Column.text('unit'),
    Column.text('measure_id'), // → ingredient_measure.id (nullable, step 7.6)
    // → recipe_measure.id: the sub-recipe's own word this component is
    // counted in. A line whose measure is tombstoned is unresolved, never
    // re-read as a count of the yield.
    Column.text('recipe_measure_id'),
    Column.text('note'),
    Column.integer('sort_order'),
    // 0/1: may be left out. Excluded from macros and the shop list and named
    // there; the cook plan ignores it.
    Column.integer('optional'),
    ..._audit,
  ]),

  // The active week and its planned meals.
  Table('week_plan', [
    Column.text('household_id'),
    // ISO date of the week's first day (`household.week_starts_on`), not
    // always a Monday.
    Column.text('week_start_date'),
    Column.text('label'),
    ..._audit,
  ]),
  Table('plan_entry', [
    Column.text('household_id'),
    Column.text('week_plan_id'),
    Column.integer('day_of_week'), // offset from week_start_date, 0..6
    Column.text('meal_slot'), // free text, not a preset enum
    // A meal is a recipe, a bare ingredient or words eaten out: exactly one
    // (server XOR check). All three are nullable, so readers branch on kind.
    Column.text('recipe_id'),
    Column.text('ingredient_id'), // → ingredient.id
    Column.text('label'), // the words a meal eaten out IS
    // The amount of one portion of an ingredient meal; null otherwise.
    Column.real('quantity'),
    Column.text('unit'),
    Column.text('measure_id'), // → ingredient_measure.id (nullable)
    // Macros of one portion of a meal eaten out, `{kcal, protein, carb,
    // fat}`. Null means not stated.
    Column.text('macros'),
    Column.text('eaters'), // JSON array of household_member ids
    Column.integer('portions'), // null → defaults to |eaters|
    Column.integer('sort_order'),
    ..._audit,
  ]),
  // One delta against a recipe line for one planned week, keyed on
  // (week_plan, recipe). Amounts are absolute.
  Table('week_recipe_line_override', [
    Column.text('household_id'),
    Column.text('week_plan_id'), // → week_plan.id
    Column.text('recipe_id'), // → recipe.id
    // → recipe_line_item.id, null exactly when `action` is 'add'.
    Column.text('recipe_line_item_id'),
    // 'include' | 'exclude' | 'replace' | 'add'.
    Column.text('action'),
    Column.text('ingredient_id'),
    // Stored only: the component graph knows no week.
    Column.text('sub_recipe_id'),
    Column.real('quantity'),
    Column.text('unit'),
    Column.text('measure_id'),
    // → recipe_measure.id, under the recipe line's rules.
    Column.text('recipe_measure_id'),
    Column.text('note'),
    Column.integer('sort_order'),
    ..._audit,
  ]),

  // Only what cannot be re-derived from the cook plan: check-off state and
  // manual/free-text entries. `cook_session` contributions are derived live.
  Table('shopping_list_entry', [
    Column.text('household_id'),
    Column.text('ingredient_id'), // null for a free-text (non-food) item
    Column.text('free_text'), // null for an ingredient
    Column.text('category'), // aisle group for a free-text item
    Column.integer('checked'), // 0/1 — check-off is on the entry
    Column.text('unit'), // preferred display unit (nullable)
    // The first day of the entry's week. Null only on a legacy row, which
    // the server stamps onto the week it was created in.
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

  // The price ledger. A hand-typed price is a `manual` receipt with one
  // line. Money is integer cents, USD; per-basis figures are derived.
  Table('receipt', [
    Column.text('household_id'),
    Column.text('store'), // a chip word, not a row: there is no store table
    Column.text('purchased_at'), // the SHOP's date, never the scan's
    // As printed; null on a hand-typed price. Never re-derived from the
    // lines: the review reconciles against it.
    Column.integer('subtotal_cents'),
    Column.integer('tax_cents'),
    Column.integer('total_cents'),
    Column.text('source'), // 'manual' | 'photo'
    ..._audit,
  ]),
  Table('receipt_line', [
    Column.text('household_id'),
    Column.text('receipt_id'),
    // → ingredient.id. Null on a non-food line, a tax line, and a line whose
    // ingredient was retired.
    Column.text('ingredient_id'),
    Column.text('printed_text'), // what the paper said; null when typed
    // The paper's words for the thing, figures off. Never a vocabulary word.
    Column.text('name_printed'),
    Column.integer('cents'), // paid, after the discount; a fee may be negative
    Column.integer('discount_cents'),
    // How many rang up ("8 @ $2.99"); 1 unless printed. `cents` includes
    // them all; a price divides by the count and the pack.
    Column.integer('count'),
    Column.text('kind'), // 'item' | 'not_food' | 'tax' | 'fee'
    // What the cents bought, in the ingredient's basis unit (g or ml). Null
    // means the line is not a price yet. Every derived figure reads this.
    Column.real('pack_basis_amount'),
    // The pack as entered, for display: an amount in `pack_unit` (a
    // units.dart id), or a count of `measure_id` when `pack_unit` is null.
    // Nothing is derived from it.
    Column.real('pack_amount'),
    Column.text('pack_unit'),
    Column.text('measure_id'), // → ingredient_measure.id — the pack's WORD
    Column.integer('sort_order'),
    ..._audit,
  ]),

  // Household vocabulary. `macros` is the server's JSONB serialized to text.
  // `usda_food` is never here (ADR-0005).
  Table('ingredient', [
    Column.text('household_id'),
    Column.text('canonical_name'),
    Column.text('category'),
    Column.text('default_unit'),
    Column.real('density_g_per_ml'),
    Column.text('macros'), // JSON {kcal, protein, carb, fat}; null when stub
    Column.text('macros_basis'), // 'g' | 'ml' — the per-100 basis (step 7.7)
    // JSON array of unit ids (ADR-0008); null → the client derives defaults.
    Column.text('allowed_units'),
    // What one of this row weighs, in the basis unit (ADR-0015); `piece` is
    // sayable only while set. `piece_source` is 'manual', 'borrowed from
    // <label>' or 'seed:typical'.
    Column.real('piece_basis_amount'),
    Column.text('piece_source'),
    Column.text('status'),
    Column.text('source'),
    // The USDA food a prefill copied from, and how much of the query its
    // description covered, so the form can name the match offline.
    Column.text('source_label'),
    Column.real('source_score'),
    // 0/1: a human overrode the looked-up macros, basis or density. A rename
    // never sets it; a fresh pick clears it.
    Column.integer('source_edited'),
    Column.text('match_text'),
    // The row's base price (0051): what was paid for a pack, typed on the
    // ingredient page. The pack is kept as entered and in the basis unit, as a
    // receipt line keeps it; a cost reads it only when no receipt prices the
    // row.
    Column.integer('base_price_cents'),
    Column.real('base_price_pack_basis_amount'),
    Column.real('base_price_pack_amount'),
    Column.text('base_price_pack_unit'),
    Column.text('base_price_measure_id'),
    Column.text('base_price_set_at'),
    // Where it is paid, as a store word (0052). Optional.
    Column.text('base_price_store'),
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
  // Named per-ingredient measures ("potato, large = 299 g"). The amount is
  // in the ingredient's macros_basis unit.
  Table('ingredient_measure', [
    Column.text('household_id'),
    Column.text('ingredient_id'),
    Column.text('label'),
    Column.real('basis_amount'),
    Column.integer('sort_order'),
    Column.text('source'), // amount provenance ("usda_fdc:…", "manual", …)
    ..._audit,
  ]),

  // Created server-side at onboarding. The client writes one column,
  // `portion_factor`. `auth_user_id` stays off the wire because the sync
  // rule's column list excludes it; omitting it here alone would not.
  Table('household_member', [
    Column.text('household_id'),
    Column.text('display_name'),
    Column.integer('sort_order'),
    Column.real('portion_factor'), // a usual portion, ×1 by default (0026)
    ..._audit,
  ]),

  // Server-only columns the `select *` sync rule ships are not declared, so
  // the client view ignores them.
  //
  // `week_starts_on` is the ISO weekday (1=Mon..7=Sun). Read-only here:
  // changing it re-homes every planned week in one server transaction
  // (`set_household_week_start`).
  Table('household', [
    Column.text('name'),
    Column.integer('week_starts_on'),
    ..._audit,
  ]),
]);
