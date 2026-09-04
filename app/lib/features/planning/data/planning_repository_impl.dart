/// [PlanningRepository] over the local PowerSync SQLite (offline in step 4).
///
/// Reads assemble `week_plan` / `plan_entry` / `recipe` rows into the [WeekPlan]
/// aggregate and react to local writes via `watch`. Writes are small, targeted
/// INSERT/UPDATE: never `INSERT ... ON CONFLICT`, which PowerSync's view-backed
/// local tables reject (a regression test under `test/core/sync/` pins that).
/// Deletes are soft (tombstone), spec §3. The one write to a server-owned
/// table is `household_member.portion_factor` (plan 0027) — the column the
/// server grants UPDATE on, and nothing else on that row.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

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
  String _weekKey(DateTime weekStart) {
    final m = mondayOf(weekStart);
    final mm = m.month.toString().padLeft(2, '0');
    final dd = m.day.toString().padLeft(2, '0');
    return '${m.year}-$mm-$dd';
  }

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
          'SELECT wp.id, pe.id, r.title FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
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
      'pe.portions, r.title AS recipe_title '
      'FROM plan_entry pe '
      'LEFT JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
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
      entries: [
        for (final e in entryRows)
          PlanEntry(
            id: e['id'] as String,
            dayOfWeek: e['day_of_week'] as int,
            mealSlot: e['meal_slot'] as String,
            recipeId: e['recipe_id'] as String,
            recipeTitle: e['recipe_title'] as String?,
            eaterIds: (jsonDecode(e['eaters'] as String? ?? '[]') as List)
                .cast<String>(),
            portions: e['portions'] as int?,
          ),
      ],
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
        'WHERE pe.deleted_at IS NULL '
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
  Future<String> _getOrCreateWeek(SqliteWriteContext tx, String weekKey) async {
    final existing = await tx.getOptional(
      'SELECT id FROM week_plan '
      'WHERE week_start_date = ? AND deleted_at IS NULL',
      [weekKey],
    );
    if (existing != null) return existing['id'] as String;
    final id = _uuid.v4();
    final now = _now();
    await tx.execute(
      'INSERT INTO week_plan (id, household_id, week_start_date, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?)',
      [id, _householdId, weekKey, now, now],
    );
    return id;
  }

  @override
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  }) async {
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
        'meal_slot, recipe_id, eaters, portions, sort_order, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _householdId,
          weekId,
          dayOfWeek,
          mealSlot.trim(),
          recipeId,
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
  Future<int> copyLastWeek(DateTime weekStart) async {
    final source = await mostRecentWeekBefore(weekStart);
    if (source == null) return 0;
    final key = _weekKey(weekStart);
    final now = _now();
    await _db.writeTransaction((tx) async {
      final weekId = await _getOrCreateWeek(tx, key);
      final entries = source.entries;
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        await tx.execute(
          'INSERT INTO plan_entry (id, household_id, week_plan_id, '
          'day_of_week, meal_slot, recipe_id, eaters, portions, sort_order, '
          'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            _uuid.v4(),
            _householdId,
            weekId,
            e.dayOfWeek,
            e.mealSlot,
            e.recipeId,
            jsonEncode(e.eaterIds),
            e.portions,
            i,
            now,
            now,
          ],
        );
      }
    });
    return source.entries.length;
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}

/// The household's live members in display order, with their portion factors
/// (plan 0027). Shared with the cook-plan and shopping repositories, which
/// derive the same demand from the same rows — a factor read three ways would
/// be three places to drift.
///
/// A row without a factor (a local test insert; a device mid-sync before
/// `0026` reached it) reads `1`, the column's own default — never a zero that
/// would silently empty a meal.
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
