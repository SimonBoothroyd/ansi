/// [LeftoverRepository] over the local PowerSync SQLite.
///
/// The read is [readCookings] over every live cooking, its linked meals,
/// their ticks and its change rows ([loadCookingInputs]): one flat read, no
/// walk over weeks. The watch query selects a column from every table it
/// joins: SQLite drops a LEFT JOIN with no selected column, and that table
/// then never re-fires the watch.
///
/// Each write reads the cooking again inside its transaction and is measured
/// against what it holds then. Local tables are views, so a write is a
/// SELECT then an INSERT or UPDATE, never an UPSERT.
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/week_shape.dart';
import '../domain/leftover_repository.dart';
import '../domain/leftovers.dart';
import 'cooking_store.dart';

class SqliteLeftoverRepository implements LeftoverRepository {
  const SqliteLeftoverRepository(
    this._db, {
    required String householdId,
    DateTime Function() clock = DateTime.now,
  }) : _householdId = householdId,
       _clock = clock;

  final SqliteConnection _db;
  final String _householdId;

  /// The wall clock: which of a cooking's meals are behind us when a write
  /// measures it.
  final DateTime Function() _clock;

  @override
  Stream<LeftoverShelves> watchHouseholdLeftovers({required DateTime today}) =>
      _db
          .watch(
            // What moves a cooking: itself, its changes, its meals and their
            // weeks, who ate them, its recipe's shelf life and the portion
            // factors a meal's demand is read with.
            'SELECT c.id, cc.id, pe.id, wp.id, me.id, r.id, hm.id '
            'FROM cooking c '
            'LEFT JOIN cooking_change cc ON cc.cooking_id = c.id '
            'LEFT JOIN plan_entry pe ON pe.cooking = c.id '
            'LEFT JOIN week_plan wp ON wp.id = pe.week_plan_id '
            'LEFT JOIN meal_eaten me ON me.plan_entry_id = pe.id '
            'LEFT JOIN recipe r ON r.id = c.recipe_id '
            'LEFT JOIN household_member hm ON 1 = 1 '
            'LIMIT 1',
          )
          .asyncMap(
            (_) async => readCookings(
              await loadCookingInputs(_db, today: today),
              today,
              unborn: await loadUnbornMeals(_db, today),
            ),
          );

  @override
  Future<void> setLeftoverPortions(Leftover left, double portions) =>
      _db.writeTransaction((tx) async {
        final read = await readCookingIn(tx, left.id, _today());
        if (read == null) return;
        final fridge = left.place == LeftoverPlace.fridge;
        final delta = portions - (fridge ? read.fridge : read.freezer);
        if (delta.abs() < 1e-9) return;
        await insertCookingChange(
          tx,
          householdId: _householdId,
          cookingId: left.id,
          fridge: fridge ? delta : 0,
          freezer: fridge ? 0 : delta,
        );
      });

  @override
  Future<LeftoverUndo> freezeLeftover(Leftover left) =>
      _db.writeTransaction((tx) async {
        final read = await readCookingIn(tx, left.id, _today());
        final moving = read == null || read.fridge <= 0 ? 0.0 : read.fridge;
        final id = await insertCookingChange(
          tx,
          householdId: _householdId,
          cookingId: left.id,
          fridge: -moving,
          freezer: moving,
        );
        return (changes: [id], gone: const <String, String?>{});
      });

  @override
  Future<LeftoverUndo> markLeftoversGone(List<Leftover> lefts) =>
      _db.writeTransaction((tx) async {
        final today = _today();
        final now = DateTime.now().toUtc().toIso8601String();
        // The day it was said, by the household's clock: what was in date
        // then stays.
        final saidAt = _clock().toUtc().toIso8601String();
        final changes = <String>[];
        final gone = <String, String?>{};
        final byCooking = <String, Set<LeftoverPlace>>{};
        for (final left in lefts) {
          (byCooking[left.id] ??= {}).add(left.place);
        }
        for (final MapEntry(key: id, value: places) in byCooking.entries) {
          final read = await readCookingIn(tx, id, today);
          if (read == null) continue;
          final other = {for (final r in read.rows) r.place}.difference(places);
          if (other.contains(LeftoverPlace.fridge)) {
            // Only the freezer part gone off, beside a fridge part still in
            // date: count it to nothing, leaving the fridge as it is.
            changes.add(
              await insertCookingChange(
                tx,
                householdId: _householdId,
                cookingId: id,
                freezer: read.freezer > 0 ? -read.freezer : 0,
              ),
            );
            continue;
          }
          // Gone off for good: the fridge part never comes back, whatever
          // is unticked after; a freezer part in date today stays.
          final before = await tx.get(
            'SELECT gone_at FROM cooking WHERE id = ?',
            [id],
          );
          await tx.execute(
            'UPDATE cooking SET gone_at = ?, updated_at = ? WHERE id = ?',
            [saidAt, now, id],
          );
          gone[id] = before['gone_at'] as String?;
        }
        return (changes: changes, gone: gone);
      });

  @override
  Future<void> undoLeftovers(LeftoverUndo undo) =>
      _db.writeTransaction((tx) async {
        final now = DateTime.now().toUtc().toIso8601String();
        for (final id in undo.changes) {
          await tx.execute(
            'UPDATE cooking_change SET deleted_at = ?, updated_at = ? '
            'WHERE id = ?',
            [now, now, id],
          );
        }
        for (final MapEntry(key: id, value: was) in undo.gone.entries) {
          await tx.execute(
            'UPDATE cooking SET gone_at = ?, updated_at = ? WHERE id = ?',
            [was, now, id],
          );
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
      [recipeId, label].whereType<String>().length == 1,
      'a recipe or words, never both (the server refuses it)',
    );
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'INSERT INTO cooking (id, household_id, recipe_id, label, made, place, '
      'since, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        _householdId,
        recipeId,
        label?.trim(),
        portions,
        place.name,
        isoDateOf(since),
        now,
        now,
      ],
    );
    return id;
  }

  DateTime _today() {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }
}
