/// [RecipeMeasureRepository] over the local PowerSync SQLite, and the one file
/// that writes `recipe_measure` at all.
///
/// Every statement against the table lives here — the batched read every other
/// loader goes through ([loadRecipeMeasures]), the deferred diff the recipe
/// form's Save runs ([writeRecipeMeasures]), the direct doors of the interface,
/// and the reference count that gates a retirement. One file owns the table, so
/// the two write doors cannot drift apart on the rules or on the SQL.
///
/// Local tables are SQLite VIEWS with INSTEAD OF triggers, so every write is a
/// plain INSERT or UPDATE — never `ON CONFLICT`, which a view rejects outright.
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/result/result.dart';
import '../../../core/units/recipe_measure.dart';
import '../domain/recipe_measure_authoring.dart';
import '../domain/recipe_measure_repository.dart';

const _uuid = Uuid();

/// Every live recipe's own words, keyed by recipe id, duplicates merged
/// (oldest canonical — [mergeRecipeMeasures]) and `sort_order` first.
///
/// **One query for the household**, never one per recipe or per line: a
/// measured component line is looked up in its TARGET's list, so every loader
/// that builds a target, a node or a component graph wants the whole map
/// anyway, and a household's words are a handful of rows. A recipe that coins
/// none is absent from the map, which every caller reads as the empty list.
///
/// A row whose `per_batch` is missing lands as `0`, which
/// [RecipeMeasure.saysAShare] refuses — so it names a word and converts
/// nothing, rather than dividing by a number nobody stated (invariant 3).
Future<Map<String, List<RecipeMeasure>>> loadRecipeMeasures(
  SqliteConnection db,
) async {
  final rows = await db.getAll(
    'SELECT rm.id, rm.recipe_id, rm.label, rm.per_batch, rm.sort_order, '
    'rm.created_at FROM recipe_measure rm WHERE rm.deleted_at IS NULL',
  );
  final byRecipe = <String, List<RecipeMeasureRow>>{};
  for (final r in rows) {
    final recipeId = r['recipe_id'] as String?;
    if (recipeId == null) continue;
    (byRecipe[recipeId] ??= []).add(_rowOf(r, recipeId));
  }
  return {
    for (final e in byRecipe.entries) e.key: mergeRecipeMeasures(e.value),
  };
}

/// Makes [recipeId]'s stored words equal [measures] — the DEFERRED door, run
/// inside `saveRecipe`'s transaction so a word typed in the editor lands with
/// the recipe (ADR-0011).
///
/// Diffed rather than replaced, for `saveRecipe`'s own reason: PowerSync queues
/// ops literally, so a DELETE of a kept id would tombstone it server-side for
/// every other device — and here it would also strand every line already
/// saying the word. Kept ids UPDATE (and un-tombstone), new ids INSERT, and
/// `sort_order` is the list's own order, so dragging the list is a re-stamp
/// like any other field.
///
/// A word the list has DROPPED is soft-deleted — unless something still says
/// it, which throws [RecipeMeasureInUse] and rolls the whole save back. The
/// gate is here rather than only at the bin because a retired word leaves its
/// lines unresolved for good (ADR-0018 rule 3), and neither door may walk
/// round that.
Future<void> writeRecipeMeasures(
  SqliteWriteContext tx, {
  required String recipeId,
  required String householdId,
  required List<RecipeMeasure> measures,
  required String now,
}) async {
  final stored = await tx.getAll(
    'SELECT id, label, deleted_at FROM recipe_measure WHERE recipe_id = ?',
    [recipeId],
  );
  final storedIds = {for (final r in stored) r['id'] as String};
  final keptIds = {for (final m in measures) m.id};

  for (final r in stored) {
    final id = r['id'] as String;
    if (keptIds.contains(id) || r['deleted_at'] != null) continue;
    await _refuseWhileSaid(
      tx,
      measureId: id,
      label: r['label'] as String? ?? '',
    );
    await tx.execute(
      'UPDATE recipe_measure SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, id],
    );
  }

  for (final (index, measure) in measures.indexed) {
    if (storedIds.contains(measure.id)) {
      // Clearing deleted_at revives a word whose id is being reused, which is
      // the same rule the groups and the lines follow one table over.
      await tx.execute(
        'UPDATE recipe_measure SET label = ?, per_batch = ?, sort_order = ?, '
        'updated_at = ?, deleted_at = NULL WHERE id = ?',
        [measure.label, measure.perBatch, index, now, measure.id],
      );
    } else {
      await tx.execute(
        'INSERT INTO recipe_measure (id, household_id, recipe_id, label, '
        'per_batch, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          measure.id,
          householdId,
          recipeId,
          measure.label,
          measure.perBatch,
          index,
          now,
          now,
        ],
      );
    }
  }
}

class SqliteRecipeMeasureRepository implements RecipeMeasureRepository {
  const SqliteRecipeMeasureRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  /// The SELECT is spelled out in full rather than shared with
  /// [loadRecipeMeasures]: `watch_coverage_test` reads these queries as
  /// literals to hold the LEFT-JOIN watch trap, and an interpolated fragment is
  /// invisible to it. The row→measure rule is shared in [_rowOf], which is the
  /// half that could actually drift.
  @override
  Stream<List<RecipeMeasure>> watchRecipeMeasures(String recipeId) => _db
      .watch(
        'SELECT rm.id, rm.recipe_id, rm.label, rm.per_batch, rm.sort_order, '
        'rm.created_at FROM recipe_measure rm '
        'WHERE rm.recipe_id = ? AND rm.deleted_at IS NULL '
        'ORDER BY rm.sort_order, rm.created_at, rm.id',
        parameters: [recipeId],
      )
      .map(
        (rows) =>
            mergeRecipeMeasures([for (final r in rows) _rowOf(r, recipeId)]),
      );

  @override
  Future<RecipeMeasure> addRecipeMeasure({
    required String recipeId,
    required String label,
    required double perBatch,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    late final RecipeMeasure minted;
    await _db.writeTransaction((tx) async {
      // The recipe's live words, read inside the transaction: the duplicate
      // rule is about what is there NOW, and the form's copy may be stale.
      final live = await _liveMeasuresOf(tx, recipeId);
      final row = await tx.get(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM recipe_measure '
        'WHERE recipe_id = ? AND deleted_at IS NULL',
        [recipeId],
      );
      // Authored by the domain, not by this file: both doors hold one set of
      // rules, and a word that merely names a catalog unit is refused against
      // the catalog's own lookup rather than a hand list.
      minted = _authored(
        authorRecipeMeasure(
          id: id,
          recipeId: recipeId,
          label: label,
          perBatch: perBatch,
          measures: live,
          sortOrder: (row['m'] as int) + 1,
        ),
      );
      await tx.execute(
        'INSERT INTO recipe_measure (id, household_id, recipe_id, label, '
        'per_batch, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _householdId,
          recipeId,
          minted.label,
          minted.perBatch,
          minted.sortOrder,
          now,
          now,
        ],
      );
    });
    return minted;
  }

  @override
  Future<void> restateRecipeMeasure({
    required String measureId,
    required String label,
    required double perBatch,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT recipe_id, sort_order FROM recipe_measure '
        'WHERE id = ? AND deleted_at IS NULL',
        [measureId],
      );
      if (row == null) {
        throw const RecipeMeasureRefused(
          'recipe_measure/gone',
          'That word is not one of this recipe’s any more.',
        );
      }
      final recipeId = row['recipe_id'] as String;
      // `authorRecipeMeasure` never counts a row as its own duplicate (it
      // compares ids), so re-stating the number without touching the word is
      // not a collision with itself.
      final restated = _authored(
        authorRecipeMeasure(
          id: measureId,
          recipeId: recipeId,
          label: label,
          perBatch: perBatch,
          measures: await _liveMeasuresOf(tx, recipeId),
          sortOrder: (row['sort_order'] as int?) ?? 0,
        ),
      );
      // The id is untouched, which is the point: every line already saying the
      // word follows the new number without being rewritten.
      await tx.execute(
        'UPDATE recipe_measure SET label = ?, per_batch = ?, updated_at = ? '
        'WHERE id = ?',
        [restated.label, restated.perBatch, now, measureId],
      );
    });
  }

  @override
  Future<void> reorderRecipeMeasures(String recipeId, List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      // Stamped by position rather than swapped in pairs: two devices that
      // dragged different rows then converge on one list per row's last write,
      // instead of on a set of half-applied swaps.
      for (final (index, id) in ids.indexed) {
        await tx.execute(
          'UPDATE recipe_measure SET sort_order = ?, updated_at = ? '
          'WHERE id = ? AND recipe_id = ? AND deleted_at IS NULL',
          [index, now, id, recipeId],
        );
      }
    });
  }

  @override
  Future<RecipeMeasureUsage> countLinesUsing(String measureId) =>
      countRecipeMeasureReferrers(_db, measureId);

  @override
  Future<void> softDeleteRecipeMeasure(String measureId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT label FROM recipe_measure WHERE id = ? AND deleted_at IS NULL',
        [measureId],
      );
      // Already gone is not a failure: the bin has nothing left to do.
      if (row == null) return;
      await _refuseWhileSaid(
        tx,
        measureId: measureId,
        label: row['label'] as String? ?? '',
      );
      await tx.execute(
        'UPDATE recipe_measure SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, measureId],
      );
      // Nothing else follows a word out, because nothing may: a line saying it
      // keeps its number and reads as unresolved, which is why this delete is
      // gated rather than cascaded (ADR-0018 rule 3).
    });
  }

  Future<List<RecipeMeasure>> _liveMeasuresOf(
    SqliteWriteContext tx,
    String recipeId,
  ) async {
    final rows = await tx.getAll(
      'SELECT rm.id, rm.recipe_id, rm.label, rm.per_batch, rm.sort_order, '
      'rm.created_at FROM recipe_measure rm '
      'WHERE rm.recipe_id = ? AND rm.deleted_at IS NULL '
      'ORDER BY rm.sort_order, rm.created_at, rm.id',
      [recipeId],
    );
    return mergeRecipeMeasures([for (final r in rows) _rowOf(r, recipeId)]);
  }
}

/// What still says [measureId] — the count both the bin's refusal and the
/// deferred diff's gate read, so the two refuse on exactly the same answer.
///
/// 0048 names exactly two tables that can carry the pointer, and both are
/// counted: a recipe's component line, and one week's override of one. A
/// tombstoned row is not a use — it is already gone.
Future<RecipeMeasureUsage> countRecipeMeasureReferrers(
  SqliteReadContext db,
  String measureId,
) async {
  final counted = await db.get(
    'SELECT '
    '(SELECT COUNT(*) FROM recipe_line_item '
    'WHERE recipe_measure_id = ? AND deleted_at IS NULL) '
    '+ (SELECT COUNT(*) FROM week_recipe_line_override '
    'WHERE recipe_measure_id = ? AND deleted_at IS NULL) AS n',
    [measureId, measureId],
  );
  final lines = (counted['n'] as num).toInt();
  if (lines == 0) return RecipeMeasureUsage.none;
  // Named so the refusal can hand the reader somewhere to go. A line whose
  // group or recipe is gone still counts above — it is a row that would be
  // stranded — but there is no page to send anybody to, so it is not named.
  final rows = await db.getAll(
    'SELECT DISTINCT r.id AS id, r.title AS title '
    'FROM recipe_line_item li '
    'JOIN ingredient_group gr ON gr.id = li.group_id '
    'JOIN recipe r ON r.id = gr.recipe_id '
    'WHERE li.recipe_measure_id = ? AND li.deleted_at IS NULL '
    'AND gr.deleted_at IS NULL AND r.deleted_at IS NULL '
    'ORDER BY r.title',
    [measureId],
  );
  return RecipeMeasureUsage(
    lines: lines,
    recipes: [
      for (final r in rows)
        (id: r['id'] as String, title: (r['title'] as String?) ?? 'Untitled'),
    ],
  );
}

/// Throws [RecipeMeasureInUse] while anything still points at [measureId].
Future<void> _refuseWhileSaid(
  SqliteWriteContext tx, {
  required String measureId,
  required String label,
}) async {
  final usage = await countRecipeMeasureReferrers(tx, measureId);
  if (!usage.any) return;
  throw RecipeMeasureInUse(measureId: measureId, label: label, usage: usage);
}

/// One stored row as [mergeRecipeMeasures] takes it.
RecipeMeasureRow _rowOf(Map<String, Object?> r, String recipeId) => (
  measure: RecipeMeasure(
    id: r['id']! as String,
    recipeId: recipeId,
    label: r['label'] as String? ?? '',
    perBatch: (r['per_batch'] as num?)?.toDouble() ?? 0,
    sortOrder: (r['sort_order'] as int?) ?? 0,
  ),
  createdAt: r['created_at'],
);

/// The authored measure, or the authoring rule's refusal as a throw — the
/// repository's posture (see `core/result/result.dart`: repositories throw and
/// the write door turns a throw into a message with a reason).
RecipeMeasure _authored(Result<RecipeMeasure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw RecipeMeasureRefused(
    failure.code,
    failure.message,
  ),
};
