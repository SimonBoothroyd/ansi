/// [LeftoverRepository] over the local PowerSync SQLite.
///
/// The read is [readLeftovers] over five weeks of cook plans, the stored
/// rows, the old `batch_leftover` answers and the meals planned from either
/// pointer. The watch query selects a column from every table it joins:
/// SQLite drops a LEFT JOIN with no selected column, and that table then never
/// re-fires the watch.
///
/// Local tables are views, so a write is a SELECT then an INSERT or UPDATE,
/// never an UPSERT. No unique index stands behind `batch`: two phones storing
/// one batch offline both upload, and the read keeps the newest.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/week_shape.dart';
import '../../planning/data/planning_repository_impl.dart' show loadMembers;
import '../../planning/domain/planning.dart'
    show Member, PlanEntry, eatersDemand, memberServings;
import '../domain/cook_plan.dart' show LeftoverAnswer;
import '../domain/leftover_repository.dart';
import '../domain/leftovers.dart';
import 'cook_plan_repository_impl.dart' show loadCookPlan;

class SqliteLeftoverRepository implements LeftoverRepository {
  const SqliteLeftoverRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;
  final String _householdId;

  @override
  Stream<LeftoverShelves> watchHouseholdLeftovers({
    required DateTime weekStart,
    required DateTime today,
  }) => _db
      .watch(
        // What moves a leftover: the weeks' meals and recipes, who ate them,
        // Cook's old answers, the stored rows and the portion factors a
        // meal's demand is read with.
        'SELECT wp.id, pe.id, me.id, bl.id, r.id, lo.id, hm.id '
        'FROM week_plan wp '
        'LEFT JOIN plan_entry pe ON pe.week_plan_id = wp.id '
        'LEFT JOIN meal_eaten me ON me.plan_entry_id = pe.id '
        'LEFT JOIN batch_leftover bl ON bl.plan_entry_id = pe.id '
        'LEFT JOIN recipe r ON r.id = pe.recipe_id '
        'LEFT JOIN leftover lo ON 1 = 1 '
        'LEFT JOIN household_member hm ON 1 = 1 '
        'LIMIT 1',
      )
      .asyncMap((_) => _load(weekStart: weekStart, today: today));

  Future<LeftoverShelves> _load({
    required DateTime weekStart,
    required DateTime today,
  }) async {
    final weeks = [
      for (final w in leftoverWeekStarts(weekStart))
        (
          weekStart: w,
          plan: await loadCookPlan(_db, isoDateOf(w), components: false),
        ),
    ];
    final stored = [
      for (final r in await _db.getAll(
        'SELECT id, place, recipe_id, label, portions, since, batch, gone_at, '
        'updated_at FROM leftover WHERE deleted_at IS NULL',
      ))
        _storedOf(r),
    ];
    final recipes = {
      for (final r in await _db.getAll(
        'SELECT id, title, keeps_for_days, freezable, freezer_days FROM recipe '
        'WHERE deleted_at IS NULL AND id IN '
        '(SELECT recipe_id FROM leftover WHERE deleted_at IS NULL)',
      ))
        r['id'] as String: (
          title: r['title'] as String,
          keepsForDays: r['keeps_for_days'] as int?,
          freezerDays: r['freezer_days'] as int?,
          freezable: (r['freezable'] as int? ?? 0) == 1,
        ),
    };
    // Cook's answers from before the page, newest last so it wins.
    final answers = <String, LeftoverAnswer>{
      for (final r in await _db.getAll(
        'SELECT plan_entry_id, kept, binned, eaten FROM batch_leftover '
        'WHERE deleted_at IS NULL ORDER BY updated_at',
      ))
        r['plan_entry_id'] as String: (
          kept: (r['kept'] as num? ?? 0).toDouble(),
          binned: (r['binned'] as num? ?? 0).toDouble(),
          eaten: (r['eaten'] as num? ?? 0).toDouble(),
        ),
    };
    final planned = await _plannedFrom();
    return readLeftovers(
      weeks: weeks,
      today: today,
      stored: stored,
      recipes: recipes,
      answers: answers,
      fromBatch: planned.batch,
      fromRow: planned.row,
      ticks: stored.any((r) => r.batch != null)
          ? await _tickSpans([
              for (final w in weeks) w.weekStart,
              // A batch can fold in a meal of the week after.
              DateTime(weekStart.year, weekStart.month, weekStart.day + 7),
            ])
          : const {},
    );
  }

  /// Every tick on the meals of the weeks beginning [weekStarts], an untick
  /// ending it, by `plan_entry` id: what a count said by hand is measured
  /// against. Each carries the share of the meal its member eats.
  Future<Map<String, List<TickSpan>>> _tickSpans(
    List<DateTime> weekStarts,
  ) async {
    final keys = [for (final w in weekStarts) isoDateOf(w)];
    final marks = List.filled(keys.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT me.plan_entry_id, me.member_id, me.created_at, me.deleted_at, '
      'pe.eaters, pe.portions, pe.day_of_week, pe.meal_slot '
      'FROM meal_eaten me '
      'JOIN plan_entry pe ON pe.id = me.plan_entry_id '
      'JOIN week_plan wp ON wp.id = pe.week_plan_id '
      'WHERE wp.week_start_date IN ($marks)',
      keys,
    );
    if (rows.isEmpty) return const {};
    final members = {for (final m in await loadMembers(_db)) m.id: m};
    final spans = <String, List<TickSpan>>{};
    for (final r in rows) {
      final entryId = r['plan_entry_id'] as String;
      final entry = PlanEntry(
        id: entryId,
        dayOfWeek: r['day_of_week'] as int,
        mealSlot: r['meal_slot'] as String,
        eaterIds: (jsonDecode(r['eaters'] as String? ?? '[]') as List)
            .cast<String>(),
        portions: r['portions'] as int?,
      );
      final memberId = r['member_id'] as String;
      final from = DateTime.tryParse(r['created_at'] as String? ?? '');
      if (from == null) continue;
      (spans[entryId] ??= []).add((
        memberId: memberId,
        share: memberServings(entry, memberId, members),
        from: from,
        until: DateTime.tryParse(r['deleted_at'] as String? ?? ''),
      ));
    }
    return spans;
  }

  /// Every live meal planned from a leftover, by batch key (`leftover_of`)
  /// and by stored row (`from_leftover`): its id, its day and its demand. The
  /// override wins, as in the cook plan.
  Future<
    ({
      Map<String, List<PlannedFromLeftover>> batch,
      Map<String, List<PlannedFromLeftover>> row,
    })
  >
  _plannedFrom() async {
    final rows = await _db.getAll(
      'SELECT pe.id, pe.leftover_of, pe.from_leftover, pe.eaters, '
      'pe.portions, pe.day_of_week, wp.week_start_date FROM plan_entry pe '
      'JOIN week_plan wp ON wp.id = pe.week_plan_id '
      'WHERE pe.deleted_at IS NULL '
      'AND (pe.leftover_of IS NOT NULL OR pe.from_leftover IS NOT NULL)',
    );
    final batch = <String, List<PlannedFromLeftover>>{};
    final row = <String, List<PlannedFromLeftover>>{};
    if (rows.isNotEmpty) {
      final members = {for (final m in await loadMembers(_db)) m.id: m};
      for (final r in rows) {
        final meal = (
          entryId: r['id'] as String,
          day: dateOfDay(
            DateTime.parse(r['week_start_date'] as String),
            r['day_of_week'] as int,
          ),
          portions: _demandOf(r, members),
        );
        if (r['leftover_of'] case final String key) {
          (batch[key] ??= []).add(meal);
        } else if (r['from_leftover'] case final String key) {
          (row[key] ??= []).add(meal);
        }
      }
    }
    return (batch: batch, row: row);
  }

  @override
  Stream<Map<String, LeftoverPlace>> watchLeftoverPlaces() => _db
      .watch('SELECT id, place FROM leftover WHERE deleted_at IS NULL')
      .map(
        (rows) => {
          for (final r in rows) r['id'] as String: _placeOf(r['place']),
        },
      );

  @override
  Future<void> setLeftoverPortions(Leftover left, double portions) =>
      _db.writeTransaction((tx) async {
        final id = await _storedIdFor(tx, left);
        // Said now: later ticks move it from here.
        await tx.execute(
          'UPDATE leftover SET portions = ?, updated_at = ? WHERE id = ?',
          [portions, _now(), id],
        );
      });

  @override
  Future<void> freezeLeftover(Leftover left) =>
      _db.writeTransaction((tx) async {
        final id = await _storedIdFor(tx, left);
        // `since` stays the cook day: freezer dates count from it. The count
        // is said again as it stands, since later ticks come off it from now.
        await tx.execute(
          "UPDATE leftover SET place = 'freezer', since = ?, portions = ?, "
          'updated_at = ? WHERE id = ?',
          [isoDateOf(left.since), left.inBox, _now(), id],
        );
      });

  @override
  Future<void> markLeftoversGone(List<Leftover> lefts) =>
      _db.writeTransaction((tx) async {
        final now = _now();
        for (final left in lefts) {
          final id = await _storedIdFor(tx, left);
          await tx.execute(
            'UPDATE leftover SET gone_at = ?, updated_at = ? WHERE id = ?',
            [now, now, id],
          );
        }
      });

  @override
  Future<void> restoreLeftovers(List<Leftover> lefts) =>
      _db.writeTransaction((tx) async {
        final now = _now();
        for (final left in lefts) {
          if (left.id case final id?) {
            await tx.execute(
              'UPDATE leftover SET place = ?, since = ?, portions = ?, '
              'gone_at = NULL, updated_at = ? WHERE id = ?',
              [left.place.name, isoDateOf(left.since), left.inBox, now, id],
            );
          } else if (left.batch case final batch?) {
            // It was derived: the batch reads from its ticks again.
            await tx.execute(
              'UPDATE leftover SET deleted_at = ?, updated_at = ? '
              'WHERE batch = ? AND deleted_at IS NULL',
              [now, now, batch],
            );
          }
        }
      });

  @override
  Future<String> addLeftover({
    required LeftoverPlace place,
    required double portions,
    required DateTime since,
    String? recipeId,
    String? label,
  }) async {
    assert(
      (recipeId == null) != (label == null),
      'a recipe or words, never both (the server refuses it)',
    );
    final id = const Uuid().v4();
    await _db.writeTransaction(
      (tx) => _insert(
        tx,
        id: id,
        place: place,
        recipeId: recipeId,
        label: label?.trim(),
        portions: portions,
        since: since,
      ),
    );
    return id;
  }

  /// The stored row [left] is, storing a derived one first: the newest live
  /// row already naming its batch if another write got there, else a new
  /// fridge row at the count it showed.
  Future<String> _storedIdFor(SqliteWriteContext tx, Leftover left) async {
    if (left.id case final id?) return id;
    final batch = left.batch!;
    final existing = await tx.getOptional(
      'SELECT id FROM leftover WHERE batch = ? AND deleted_at IS NULL '
      'ORDER BY updated_at DESC, id DESC LIMIT 1',
      [batch],
    );
    if (existing != null) return existing['id'] as String;
    final id = const Uuid().v4();
    await _insert(
      tx,
      id: id,
      place: left.place,
      recipeId: left.recipeId,
      portions: left.inBox,
      since: left.since,
      batch: batch,
    );
    return id;
  }

  Future<void> _insert(
    SqliteWriteContext tx, {
    required String id,
    required LeftoverPlace place,
    required double portions,
    required DateTime since,
    String? recipeId,
    String? label,
    String? batch,
  }) {
    final now = _now();
    return tx.execute(
      'INSERT INTO leftover (id, household_id, place, recipe_id, label, '
      'portions, since, batch, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        _householdId,
        place.name,
        recipeId,
        label,
        portions,
        isoDateOf(since),
        batch,
        now,
        now,
      ],
    );
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}

/// A meal's demand: its portions override, else its eaters' factors.
double _demandOf(Row r, Map<String, Member> members) =>
    (r['portions'] as int?)?.toDouble() ??
    eatersDemand(
      (jsonDecode(r['eaters'] as String? ?? '[]') as List).cast<String>(),
      members,
    );

LeftoverPlace _placeOf(Object? place) =>
    place == 'freezer' ? LeftoverPlace.freezer : LeftoverPlace.fridge;

StoredLeftover _storedOf(Row r) => StoredLeftover(
  id: r['id'] as String,
  place: _placeOf(r['place']),
  recipeId: r['recipe_id'] as String?,
  label: r['label'] as String?,
  portions: (r['portions'] as num? ?? 0).toDouble(),
  since: DateTime.parse(r['since'] as String),
  batch: r['batch'] as String?,
  goneAt: switch (r['gone_at']) {
    final String at => DateTime.parse(at),
    _ => null,
  },
  updatedAt: DateTime.parse(r['updated_at'] as String),
);
