/// [ShoppingRepository] over the local PowerSync SQLite (offline in step 6).
///
/// The read derives cook contributions live from the batch cook plan (spec §4):
/// it reads the week's planned meals, runs the same pure [buildCookPlan] the
/// Cook screen uses, then multiplies each covered recipe's line items by its
/// session scale factor. It overlays the persisted check-off + manual/free-text
/// rows and hands everything to the pure [buildShoppingList].
///
/// The watch query references every source table AND selects a column from
/// each — including the two shopping tables via a `LEFT JOIN … ON 1=1` — so
/// PowerSync's `EXPLAIN`-based detection registers all of them as triggers.
/// An unselected LEFT JOIN would be dropped and its table silently missed
/// ([[mise-powersync-watch-left-join]]); selecting a column from each keeps it.
///
/// Writes go through the local VIEWS, so no UPSERT (a view rejects
/// `ON CONFLICT`): entry creation is a find-or-create with a plain INSERT.
library;

import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/dev_household.dart';
import '../../../core/units/units.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../planning/domain/planning.dart' show mondayOf;
import '../domain/shopping.dart';
import '../domain/shopping_repository.dart';

/// Mon..Sun short labels for the derived provenance labels ("· cook Mon").
/// Kept here (not imported from presentation) so the data layer doesn't depend
/// upwards; [buildShoppingList] takes the list so the domain stays formatless.
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _uuid = Uuid();

class SqliteShoppingRepository implements ShoppingRepository {
  const SqliteShoppingRepository(
    this._db, {
    String householdId = kDevHouseholdId,
  }) : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (dev default for tests).
  final String _householdId;

  String _weekKey(DateTime weekStart) {
    final m = mondayOf(weekStart);
    final mm = m.month.toString().padLeft(2, '0');
    final dd = m.day.toString().padLeft(2, '0');
    return '${m.year}-$mm-$dd';
  }

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) {
    final key = _weekKey(weekStart);
    // Reference every source table and select a column from each so all seven
    // become watch triggers (see the library doc). The shopping tables aren't
    // tied to the week, so they're cross-joined (`ON 1=1`) purely to be seen.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days, g.id, li.id, se.id, sc.id '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN shopping_list_entry se ON 1 = 1 '
          'LEFT JOIN shopping_list_contribution sc ON 1 = 1 '
          'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
          parameters: [key],
        )
        .asyncMap((_) => _load(key));
  }

  Future<ShoppingList> _load(String weekKey) async {
    final cook = await _deriveCookContributions(weekKey);
    final (entries, manual) = await _loadOverlay();
    final meta = await _loadIngredientMeta({
      ...cook.map((c) => c.ingredientId),
      ...entries.map((e) => e.ingredientId).whereType<String>(),
    });
    return buildShoppingList(
      cook: cook,
      entries: entries,
      manual: manual,
      meta: meta,
      weekdayShort: _weekdayShort,
    );
  }

  /// Runs the cook plan for the week, then expands each session's recipe line
  /// items scaled by the session's factor into per-ingredient contributions.
  Future<List<CookContributionInput>> _deriveCookContributions(
    String weekKey,
  ) async {
    final rows = await _db.getAll(
      'SELECT pe.day_of_week, pe.meal_slot, pe.eaters, pe.portions, '
      'r.id AS recipe_id, r.title, r.servings_base, r.keeps_for_days, '
      'r.freezable, r.freezer_days '
      'FROM week_plan wp '
      'JOIN plan_entry pe ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
      'JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
      'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL '
      'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
      [weekKey],
    );
    if (rows.isEmpty) return const [];

    final byRecipe = <String, PlannedRecipe>{};
    final meals = <String, List<CoveredMeal>>{};
    for (final row in rows) {
      final recipeId = row['recipe_id'] as String;
      final eaters = jsonDecode(row['eaters'] as String? ?? '[]') as List;
      final portions = (row['portions'] as int?) ?? eaters.length;
      byRecipe[recipeId] ??= PlannedRecipe(
        recipeId: recipeId,
        title: row['title'] as String,
        servingsBase: (row['servings_base'] as num).toDouble(),
        keepsForDays: row['keeps_for_days'] as int?,
        freezable: (row['freezable'] as int? ?? 0) == 1,
        freezerDays: row['freezer_days'] as int?,
      );
      (meals[recipeId] ??= []).add(
        CoveredMeal(
          dayOfWeek: row['day_of_week'] as int,
          mealSlot: row['meal_slot'] as String,
          portions: portions,
        ),
      );
    }
    final plan = buildCookPlan([
      for (final e in byRecipe.entries)
        e.value.copyWith(meals: meals[e.key] ?? const []),
    ]);

    // Line items per recipe, read once.
    final lineItems = await _loadLineItems(byRecipe.keys.toSet());

    final contributions = <CookContributionInput>[];
    for (final recipe in plan.recipes) {
      final batched = recipe.sessions.length > 1;
      final items = lineItems[recipe.recipeId] ?? const [];
      for (final session in recipe.sessions) {
        for (final item in items) {
          final scaled = item.quantity == null
              ? null
              : scale(Quantity(item.quantity!, item.unit), session.scaleFactor);
          contributions.add((
            ingredientId: item.ingredientId,
            quantity: scaled?.amount,
            unit: item.unit,
            recipeTitle: recipe.title,
            cookDay: session.cookDay,
            batched: batched,
          ));
        }
      }
    }
    return contributions;
  }

  Future<
    Map<String, List<({String ingredientId, double? quantity, Unit unit})>>
  >
  _loadLineItems(Set<String> recipeIds) async {
    if (recipeIds.isEmpty) return const {};
    final placeholders = List.filled(recipeIds.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT g.recipe_id, li.ingredient_id, li.quantity, li.unit '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
      'WHERE g.recipe_id IN ($placeholders) AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order, li.created_at',
      recipeIds.toList(),
    );
    final byRecipe =
        <String, List<({String ingredientId, double? quantity, Unit unit})>>{};
    for (final row in rows) {
      final ingredientId = row['ingredient_id'] as String?;
      if (ingredientId == null) continue;
      (byRecipe[row['recipe_id'] as String] ??= []).add((
        ingredientId: ingredientId,
        quantity: (row['quantity'] as num?)?.toDouble(),
        unit: unitById(row['unit'] as String? ?? '') ?? pieces,
      ));
    }
    return byRecipe;
  }

  Future<(List<ShoppingEntryInput>, Map<String, List<ManualContributionInput>>)>
  _loadOverlay() async {
    final entryRows = await _db.getAll(
      'SELECT id, ingredient_id, free_text, category, checked, unit '
      'FROM shopping_list_entry WHERE deleted_at IS NULL',
    );
    final entries = [
      for (final r in entryRows)
        (
          id: r['id'] as String,
          ingredientId: r['ingredient_id'] as String?,
          freeText: r['free_text'] as String?,
          category: r['category'] as String?,
          checked: (r['checked'] as int? ?? 0) == 1,
          unit: unitById(r['unit'] as String? ?? ''),
        ),
    ];

    final contribRows = await _db.getAll(
      'SELECT id, entry_id, quantity, unit, note '
      'FROM shopping_list_contribution '
      "WHERE deleted_at IS NULL AND source_type = 'manual' "
      'ORDER BY created_at',
    );
    final manual = <String, List<ManualContributionInput>>{};
    for (final r in contribRows) {
      final entryId = r['entry_id'] as String;
      (manual[entryId] ??= []).add((
        id: r['id'] as String,
        entryId: entryId,
        quantity: (r['quantity'] as num?)?.toDouble(),
        unit: unitById(r['unit'] as String? ?? ''),
        note: r['note'] as String?,
      ));
    }
    return (entries, manual);
  }

  Future<Map<String, IngredientMetaInput>> _loadIngredientMeta(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT id, canonical_name, category, density_g_per_ml, default_unit '
      'FROM ingredient WHERE id IN ($placeholders)',
      ids.toList(),
    );
    return {
      for (final r in rows)
        r['id'] as String: (
          name: r['canonical_name'] as String,
          category: r['category'] as String?,
          densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
          defaultUnit: unitById(r['default_unit'] as String? ?? '') ?? pieces,
        ),
    };
  }

  // --- Writes ----------------------------------------------------------------

  /// Finds the live entry for [ingredientId] or creates one, returning its id.
  Future<String> _findOrCreateIngredientEntry(
    SqliteWriteContext tx,
    String ingredientId,
  ) async {
    final existing = await tx.getOptional(
      'SELECT id FROM shopping_list_entry '
      'WHERE ingredient_id = ? AND deleted_at IS NULL LIMIT 1',
      [ingredientId],
    );
    if (existing != null) return existing['id'] as String;

    final id = _uuid.v4();
    final now = _now();
    await tx.execute(
      'INSERT INTO shopping_list_entry '
      '(id, household_id, ingredient_id, checked, created_at, updated_at) '
      'VALUES (?, ?, ?, 0, ?, ?)',
      [id, _householdId, ingredientId, now, now],
    );
    return id;
  }

  @override
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
  }) async {
    final flag = checked ? 1 : 0;
    await _db.writeTransaction((tx) async {
      final entryId = await _findOrCreateIngredientEntry(tx, ingredientId);
      await tx.execute(
        'UPDATE shopping_list_entry SET checked = ?, updated_at = ? '
        'WHERE id = ?',
        [flag, _now(), entryId],
      );
    });
  }

  @override
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  }) async {
    final flag = checked ? 1 : 0;
    await _db.execute(
      'UPDATE shopping_list_entry SET checked = ?, updated_at = ? WHERE id = ?',
      [flag, _now(), entryId],
    );
  }

  @override
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
  }) async {
    await _db.writeTransaction((tx) async {
      final entryId = await _findOrCreateIngredientEntry(tx, ingredientId);
      final now = _now();
      await tx.execute(
        'INSERT INTO shopping_list_contribution '
        '(id, household_id, entry_id, source_type, quantity, unit, '
        'created_at, updated_at) '
        "VALUES (?, ?, ?, 'manual', ?, ?, ?, ?)",
        [_uuid.v4(), _householdId, entryId, quantity, unit.id, now, now],
      );
    });
  }

  @override
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
  }) async {
    await _db.execute(
      'UPDATE shopping_list_contribution SET quantity = ?, unit = ?, '
      'updated_at = ? WHERE id = ?',
      [quantity, unit.id, _now(), contributionId],
    );
  }

  @override
  Future<void> removeContribution({required String contributionId}) async {
    final now = _now();
    await _db.execute(
      'UPDATE shopping_list_contribution SET deleted_at = ?, updated_at = ? '
      'WHERE id = ?',
      [now, now, contributionId],
    );
  }

  @override
  Future<void> addFreeTextItem({required String text, String? category}) async {
    final now = _now();
    await _db.execute(
      'INSERT INTO shopping_list_entry '
      '(id, household_id, free_text, category, checked, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, 0, ?, ?)',
      [_uuid.v4(), _householdId, text, category, now, now],
    );
  }

  @override
  Future<void> removeEntry({required String entryId}) async {
    final now = _now();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE shopping_list_entry SET deleted_at = ?, updated_at = ? '
        'WHERE id = ?',
        [now, now, entryId],
      );
      await tx.execute(
        'UPDATE shopping_list_contribution SET deleted_at = ?, updated_at = ? '
        'WHERE entry_id = ?',
        [now, now, entryId],
      );
    });
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
