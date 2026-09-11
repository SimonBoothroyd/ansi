/// [PlanningRepository] over the local PowerSync SQLite (offline in step 4).
///
/// Reads assemble `week_plan` / `plan_entry` / `recipe` rows into the
/// [WeekPlan] aggregate and react to local writes via `watch`. Writes are
/// small, targeted INSERT/UPDATE: never `INSERT ... ON CONFLICT`, which
/// PowerSync's view-backed local tables reject (a regression test under
/// `test/core/sync/` pins that). Deletes are soft (tombstone), spec §3. The one
/// write to a server-owned table is `household_member.portion_factor` — the
/// column the server grants UPDATE on, and nothing else on that row.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../domain/planning.dart';
import '../domain/planning_repository.dart';

const _uuid = Uuid();

class SqlitePlanningRepository implements PlanningRepository {
  const SqlitePlanningRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (injected — the app passes
  /// the signed-in household, tests pass their own).
  final String _householdId;

  /// The ISO date (YYYY-MM-DD) a week is addressed by — its Monday.
  String _weekKey(DateTime weekStart) => weekKeyOf(weekStart);

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) {
    final key = _weekKey(weekStart);
    // Reference every table [_loadWeek] reads so PowerSync re-fires on any
    // change — including `plan_entry` and `recipe`. Each joined table must
    // contribute a *selected* column: SQLite omits a LEFT JOIN whose columns go
    // unused, and an omitted join is an undetected table (the stale-breadcrumb
    // class, see docs). The rows are ignored; each fire re-assembles the week.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.title, i.canonical_name, im.label '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
          // A meal can be a bare ingredient (step 8.14), so its vocab row and
          // its measure are read by [_assembleWeek] too — and an unselected
          // LEFT JOIN is an undetected table, so both contribute a column.
          'LEFT JOIN ingredient i ON i.id = pe.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = pe.measure_id '
          'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
          parameters: [key],
        )
        .asyncMap((_) => _loadWeek(key));
  }

  Future<WeekPlan?> _loadWeek(String weekKey) async {
    final wp = await _db.getOptional(
      'SELECT id, week_start_date, label FROM week_plan '
      'WHERE week_start_date = ? AND deleted_at IS NULL LIMIT 1',
      [weekKey],
    );
    if (wp == null) return null;
    return _assembleWeek(wp);
  }

  /// Loads a week's entries (with recipe titles) and builds the aggregate.
  Future<WeekPlan> _assembleWeek(Row wp) async {
    final id = wp['id'] as String;
    final entryRows = await _db.getAll(
      'SELECT pe.id, pe.day_of_week, pe.meal_slot, pe.recipe_id, pe.eaters, '
      'pe.portions, pe.ingredient_id, pe.quantity, pe.unit, pe.measure_id, '
      'r.title AS recipe_title, i.canonical_name AS ingredient_name, '
      'i.macros, i.density_g_per_ml, i.piece_basis_amount, '
      'im.label AS measure_label, im.basis_amount AS measure_amount, '
      'i.macros_basis AS measure_basis, im.sort_order AS measure_sort, '
      'im.source AS measure_source '
      'FROM plan_entry pe '
      'LEFT JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
      // The other half of the XOR (step 8.14): a meal that names an
      // ingredient instead of a dish, with the measure its amount is counted
      // in. A row that has not synced (or was deleted) leaves the name null —
      // a real answer the surfaces print their own words for.
      'LEFT JOIN ingredient i '
      'ON i.id = pe.ingredient_id AND i.deleted_at IS NULL '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = pe.measure_id AND im.deleted_at IS NULL '
      'WHERE pe.week_plan_id = ? AND pe.deleted_at IS NULL '
      'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
      [id],
    );
    return WeekPlan(
      id: id,
      // The key is a bare 'YYYY-MM-DD'; parse it as a UTC date-only value so it
      // round-trips equal to mondayOf's output (which is UTC).
      weekStart: DateTime.parse('${wp['week_start_date']}T00:00:00Z'),
      label: wp['label'] as String?,
      entries: [for (final e in entryRows) _entryFrom(e)],
    );
  }

  /// One [PlanEntry] from a row of [_assembleWeek]'s SELECT.
  ///
  /// An unknown persisted unit id stays NULL rather than falling back to
  /// `pieces` — a fallback would let a total sum an invented unit (invariant
  /// 3), exactly as the recipe line reader refuses to.
  PlanEntry _entryFrom(Row e) => PlanEntry(
    id: e['id'] as String,
    dayOfWeek: e['day_of_week'] as int,
    mealSlot: e['meal_slot'] as String,
    recipeId: e['recipe_id'] as String?,
    recipeTitle: e['recipe_title'] as String?,
    ingredientId: e['ingredient_id'] as String?,
    ingredientName: e['ingredient_name'] as String?,
    quantity: (e['quantity'] as num?)?.toDouble(),
    unit: unitById(e['unit'] as String? ?? ''),
    measureId: e['measure_id'] as String?,
    measure: _toMeasure(e),
    // Gated on the JOINED row, not on `pe.ingredient_id`: a vocab row this
    // device cannot see (deleted, or not yet synced) leaves the nutrition
    // null, which the week names as "not in your ingredients yet" — a
    // different answer from a row that is present but a stub.
    nutrition: e['ingredient_name'] == null
        ? null
        : (
            // `tryParse` returns null for absent OR malformed macros, which is
            // the same answer either way: the row is a stub, and the week says
            // so rather than inventing the missing keys.
            macros: Macros.tryParse(e['macros'] as String?),
            basis: MacrosBasis.fromDb(e['measure_basis'] as String?),
            densityGPerMl: (e['density_g_per_ml'] as num?)?.toDouble(),
            pieceBasisAmount: (e['piece_basis_amount'] as num?)?.toDouble(),
          ),
    eaterIds: (jsonDecode(e['eaters'] as String? ?? '[]') as List)
        .cast<String>(),
    portions: e['portions'] as int?,
  );

  /// The resolved [Measure] of a row selected with the measure aliases, or
  /// null when the entry has none (or its measure row is missing — an honest
  /// degradation to the stored count unit, never invented grams). The basis is
  /// the MEASURED ingredient's own `macros_basis` (ADR-0008).
  Measure? _toMeasure(Row row) {
    final id = row['measure_id'] as String?;
    final label = row['measure_label'] as String?;
    final amount = (row['measure_amount'] as num?)?.toDouble();
    if (id == null || label == null || amount == null) return null;
    return Measure(
      id: id,
      label: label,
      amount: amount,
      basis: MacrosBasis.fromDb(row['measure_basis'] as String?),
      sortOrder: (row['measure_sort'] as int?) ?? 0,
      source: row['measure_source'] as String?,
    );
  }

  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async {
    final wp = await _db.getOptional(
      'SELECT id, week_start_date, label FROM week_plan '
      'WHERE week_start_date < ? AND deleted_at IS NULL '
      'ORDER BY week_start_date DESC LIMIT 1',
      [_weekKey(weekStart)],
    );
    if (wp == null) return null;
    final week = await _assembleWeek(wp);
    // Skip empty weeks — an earlier week worth copying/showing has meals.
    return week.entries.isEmpty ? null : week;
  }

  // The same SELECT as [loadMembers], written out rather than shared through
  // a constant: the watch-coverage structural test reads the literal after
  // `.watch(` to learn which tables this stream is triggered by.
  @override
  Stream<List<Member>> watchMembers() => _db
      .watch(
        'SELECT id, display_name, portion_factor FROM household_member '
        'WHERE deleted_at IS NULL '
        'ORDER BY sort_order, display_name',
      )
      .map(_membersFrom);

  @override
  Future<void> setPortionFactor(String memberId, double factor) async {
    await _db.execute(
      'UPDATE household_member SET portion_factor = ?, updated_at = ? '
      'WHERE id = ?',
      [factor, _now(), memberId],
    );
  }

  @override
  Stream<Map<String, DateTime>> watchLastPlanned() => _db
      .watch(
        'SELECT pe.recipe_id, '
        "MAX(date(wp.week_start_date, '+' || pe.day_of_week || ' days')) AS d "
        'FROM plan_entry pe '
        'JOIN week_plan wp ON wp.id = pe.week_plan_id '
        'AND wp.deleted_at IS NULL '
        // The explicit branch (step 8.14 / B-D2): this map is the RECIPE
        // picker's "last planned" recency, so an ingredient meal is filtered
        // out by name rather than by grouping silently under a null key.
        'WHERE pe.deleted_at IS NULL AND pe.recipe_id IS NOT NULL '
        'GROUP BY pe.recipe_id',
      )
      .map(
        (rows) => {
          for (final r in rows)
            if (r['d'] != null)
              // Bare 'YYYY-MM-DD' → a UTC date-only value, like _weekKey.
              r['recipe_id'] as String: DateTime.parse('${r['d']}T00:00:00Z'),
        },
      );

  /// Returns the id of the week beginning [weekKey], creating it if absent.
  Future<String> _getOrCreateWeek(SqliteWriteContext tx, String weekKey) =>
      getOrCreateWeekPlan(tx, weekKey: weekKey, householdId: _householdId);

  @override
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  }) => _insertEntry(
    weekStart: weekStart,
    dayOfWeek: dayOfWeek,
    mealSlot: mealSlot,
    recipeId: recipeId,
    eaterIds: eaterIds,
    portions: portions,
  );

  @override
  Future<String> addIngredientEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String ingredientId,
    required List<String> eaterIds,
    double? quantity,
    Unit? unit,
    String? measureId,
    int? portions,
  }) => _insertEntry(
    weekStart: weekStart,
    dayOfWeek: dayOfWeek,
    mealSlot: mealSlot,
    ingredientId: ingredientId,
    eaterIds: eaterIds,
    portions: portions,
    quantity: quantity,
    unit: unit?.id,
    measureId: measureId,
  );

  /// The one INSERT both add paths share. Exactly one of [recipeId] /
  /// [ingredientId] is set — the server's `plan_entry_target_xor` refuses
  /// anything else, and this is where the app keeps its side of that bargain.
  Future<String> _insertEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required List<String> eaterIds,
    String? recipeId,
    String? ingredientId,
    double? quantity,
    String? unit,
    String? measureId,
    int? portions,
  }) async {
    assert(
      (recipeId == null) != (ingredientId == null),
      'a plan entry names a recipe OR an ingredient (0033 XOR)',
    );
    final key = _weekKey(weekStart);
    final id = _uuid.v4();
    final now = _now();
    await _db.writeTransaction((tx) async {
      final weekId = await _getOrCreateWeek(tx, key);
      final orderRow = await tx.get(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM plan_entry '
        'WHERE week_plan_id = ? AND day_of_week = ?',
        [weekId, dayOfWeek],
      );
      final order = (orderRow['m'] as int) + 1;
      await tx.execute(
        'INSERT INTO plan_entry (id, household_id, week_plan_id, day_of_week, '
        'meal_slot, recipe_id, ingredient_id, quantity, unit, measure_id, '
        'eaters, portions, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _householdId,
          weekId,
          dayOfWeek,
          mealSlot.trim(),
          recipeId,
          ingredientId,
          quantity,
          unit,
          measureId,
          jsonEncode(eaterIds),
          portions,
          order,
          now,
          now,
        ],
      );
    });
    return id;
  }

  @override
  Future<void> setEaters(String entryId, List<String> eaterIds) async {
    await _db.execute(
      'UPDATE plan_entry SET eaters = ?, updated_at = ? WHERE id = ?',
      [jsonEncode(eaterIds), _now(), entryId],
    );
  }

  @override
  Future<void> setPortions(String entryId, int? portions) async {
    await _db.execute(
      'UPDATE plan_entry SET portions = ?, updated_at = ? WHERE id = ?',
      [portions, _now(), entryId],
    );
  }

  @override
  Future<void> removeEntry(String entryId) async {
    final now = _now();
    await _db.execute(
      'UPDATE plan_entry SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, entryId],
    );
  }

  @override
  Future<CopyLastWeekResult> copyLastWeek(DateTime weekStart) async {
    final source = await mostRecentWeekBefore(weekStart);
    if (source == null) {
      return (meals: 0, variantsLeftBehind: const <VariantLeftBehind>[]);
    }
    final key = _weekKey(weekStart);
    final now = _now();
    await _db.writeTransaction((tx) async {
      final weekId = await _getOrCreateWeek(tx, key);
      final entries = source.entries;
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        // Copies the whole meal, whichever kind it is (step 8.14): a snack is
        // an ordinary entry, so it is copied with its amount rather than
        // dropped for having no recipe.
        await tx.execute(
          'INSERT INTO plan_entry (id, household_id, week_plan_id, '
          'day_of_week, meal_slot, recipe_id, ingredient_id, quantity, unit, '
          'measure_id, eaters, portions, sort_order, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            _uuid.v4(),
            _householdId,
            weekId,
            e.dayOfWeek,
            e.mealSlot,
            e.recipeId,
            e.ingredientId,
            e.quantity,
            e.unit?.id,
            e.measureId,
            jsonEncode(e.eaterIds),
            e.portions,
            i,
            now,
            now,
          ],
        );
      }
    });
    return (
      meals: source.entries.length,
      variantsLeftBehind: await _variantsLeftBehind(source.id),
    );
  }

  /// The variants the copy did not bring: one row per recipe the SOURCE week
  /// varied, named and counted. Nothing is written for them — not copying is
  /// already the behaviour, and this is the saying of it.
  Future<List<VariantLeftBehind>> _variantsLeftBehind(String weekPlanId) async {
    final rows = await _db.getAll(
      'SELECT r.title, COUNT(*) AS n '
      'FROM week_recipe_line_override wro '
      'JOIN recipe r ON r.id = wro.recipe_id AND r.deleted_at IS NULL '
      'WHERE wro.week_plan_id = ? AND wro.deleted_at IS NULL '
      'GROUP BY r.id, r.title ORDER BY r.title',
      [weekPlanId],
    );
    return [
      for (final r in rows)
        (recipeTitle: r['title'] as String, changes: r['n'] as int),
    ];
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}

/// The household's live members in display order, with their portion factors.
/// Shared with the cook-plan and shopping repositories, which derive the same
/// demand from the same rows — a factor read three ways would be three places
/// to drift.
///
/// A row without a factor (a local test insert; a device mid-sync before
/// `0026` reached it) reads `1`, the column's own default — never a zero that
/// would silently empty a meal.
/// The id of the `week_plan` row for [weekKey], creating it on first use.
///
/// A week costs nothing until something is written against it, so the row is
/// made lazily — by the first meal, and equally by the first line somebody
/// changes for that week.
Future<String> getOrCreateWeekPlan(
  SqliteWriteContext tx, {
  required String weekKey,
  required String householdId,
}) async {
  final existing = await tx.getOptional(
    'SELECT id FROM week_plan WHERE week_start_date = ? AND deleted_at IS NULL',
    [weekKey],
  );
  if (existing != null) return existing['id'] as String;
  final id = _uuid.v4();
  final now = DateTime.now().toUtc().toIso8601String();
  await tx.execute(
    'INSERT INTO week_plan (id, household_id, week_start_date, created_at, '
    'updated_at) VALUES (?, ?, ?, ?, ?)',
    [id, householdId, weekKey, now, now],
  );
  return id;
}

Future<List<Member>> loadMembers(SqliteConnection db) async => _membersFrom(
  await db.getAll(
    'SELECT id, display_name, portion_factor FROM household_member '
    'WHERE deleted_at IS NULL '
    'ORDER BY sort_order, display_name',
  ),
);

List<Member> _membersFrom(List<Row> rows) => [
  for (final r in rows)
    Member(
      id: r['id'] as String,
      displayName: r['display_name'] as String,
      portionFactor: (r['portion_factor'] as num?)?.toDouble() ?? 1,
    ),
];
