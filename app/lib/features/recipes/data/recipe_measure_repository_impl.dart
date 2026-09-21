/// [RecipeMeasureRepository] over the local PowerSync SQLite, and the only file
/// that reads or writes `recipe_measure`.
///
/// Local tables are SQLite views with INSTEAD OF triggers, so every write is a
/// plain INSERT or UPDATE, never `ON CONFLICT`.
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart' show StoredMeasure, mergeByLabel;
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../domain/component_math.dart';
import '../domain/recipe_measure_authoring.dart';
import '../domain/recipe_measure_repository.dart';

const _uuid = Uuid();

/// The columns every read asks for. A measure's denomination (`amount` +
/// `unit`, ADR-0018) is named only here, in [_rowOf] and in
/// [_insertRow]/[_updateRow].
const _columns =
    'rm.id, rm.recipe_id, rm.label, rm.amount, rm.unit, rm.sort_order, '
    'rm.created_at';

/// Every live recipe's measures by recipe id: the merged offer first, then the
/// merge-hidden duplicates, which a line may still point at
/// ([recipeMeasureById] finds them; [offeredRecipeMeasures] does not). One
/// query for the household. A non-positive amount loads as a measure
/// [RecipeMeasure.saysAnAmount] refuses; an unknown `unit` is skipped
/// ([_rowOf]).
Future<Map<String, List<RecipeMeasure>>> loadRecipeMeasures(
  SqliteConnection db,
) async {
  final rows = await db.getAll(
    'SELECT $_columns FROM recipe_measure rm WHERE rm.deleted_at IS NULL',
  );
  final byRecipe = <String, List<StoredMeasure<RecipeMeasure>>>{};
  for (final r in rows) {
    final recipeId = r['recipe_id'] as String?;
    if (recipeId == null) continue;
    final row = _rowOf(r, recipeId);
    if (row == null) continue;
    (byRecipe[recipeId] ??= []).add(row);
  }
  return {for (final e in byRecipe.entries) e.key: _offeredThenHidden(e.value)};
}

/// [rows] as the merged offer, then every live row the merge hid.
List<RecipeMeasure> _offeredThenHidden(
  List<StoredMeasure<RecipeMeasure>> rows,
) {
  final merged = mergeByLabel(rows);
  final shown = {for (final m in merged) m.id};
  return [
    ...merged,
    for (final r in rows)
      if (!shown.contains(r.measure.id)) r.measure,
  ];
}

/// Makes [recipeId]'s stored measures equal [measures], inside `saveRecipe`'s
/// transaction (ADR-0011).
///
/// Diffed, not replaced: PowerSync queues ops literally, so deleting a kept id
/// would tombstone it everywhere. A dropped word that is still said throws
/// [RecipeMeasureInUse] and rolls the save back. New and re-stated words are
/// authored against the yields read back inside the transaction; an unchanged
/// word is never re-authored (ADR-0018 rules 3–4).
Future<void> writeRecipeMeasures(
  SqliteWriteContext tx, {
  required String recipeId,
  required String householdId,
  required List<RecipeMeasure> measures,
  required String now,
}) async {
  final stored = await tx.getAll(
    'SELECT id, label, amount, unit, deleted_at FROM recipe_measure '
    'WHERE recipe_id = ?',
    [recipeId],
  );
  final storedById = {for (final r in stored) r['id'] as String: r};
  final keptIds = {for (final m in measures) m.id};
  // The editor's list is the merged one, so a merge-hidden duplicate is absent
  // without being dropped. Its label is still kept, so its row is left alone.
  final keptLabels = {for (final m in measures) m.label};

  for (final r in stored) {
    final id = r['id'] as String;
    if (keptIds.contains(id) || r['deleted_at'] != null) continue;
    if (keptLabels.contains(r['label'] as String? ?? '')) continue;
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

  // Read lazily: a Save that states no new word needs no yields.
  List<YieldDenomination>? yields;

  for (final (index, measure) in measures.indexed) {
    final positioned = measure.copyWith(recipeId: recipeId, sortOrder: index);
    final was = storedById[measure.id];
    if (_restates(positioned, was)) {
      yields ??= await _yieldsOf(tx, recipeId);
      _authored(
        authorRecipeMeasure(
          id: positioned.id,
          recipeId: recipeId,
          label: positioned.label,
          amount: positioned.amount,
          unit: positioned.unit,
          yields: yields,
          measures: [
            for (final m in measures)
              if (m.id != positioned.id) m,
          ],
          sortOrder: index,
        ),
      );
    }
    if (was != null) {
      await _updateRow(tx, positioned, now: now);
    } else {
      await _insertRow(tx, positioned, householdId: householdId, now: now);
    }
  }
}

/// Whether [measure] is a new word, or re-states the denomination or label of
/// the stored row [was]. A `sort_order` change alone is not a re-statement.
bool _restates(RecipeMeasure measure, Map<String, Object?>? was) {
  if (was == null) return true;
  return measure.label != (was['label'] as String? ?? '') ||
      measure.amount != ((was['amount'] as num?)?.toDouble() ?? 0) ||
      measure.unit.id != (was['unit'] as String? ?? '');
}

class SqliteRecipeMeasureRepository implements RecipeMeasureRepository {
  const SqliteRecipeMeasureRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<List<RecipeMeasure>> watchRecipeMeasures(String recipeId) => _db
      .watch(
        'SELECT $_columns FROM recipe_measure rm '
        'WHERE rm.recipe_id = ? AND rm.deleted_at IS NULL '
        'ORDER BY rm.sort_order, rm.created_at, rm.id',
        parameters: [recipeId],
      )
      .map((rows) => mergeByLabel(_rowsOf(rows, recipeId)));

  @override
  Future<RecipeMeasure> addRecipeMeasure({
    required String recipeId,
    required String label,
    required double amount,
    required Unit unit,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    late final RecipeMeasure minted;
    await _db.writeTransaction((tx) async {
      // Read inside the transaction: the form's copy may be stale.
      final live = await _liveMeasuresOf(tx, recipeId);
      final row = await tx.get(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM recipe_measure '
        'WHERE recipe_id = ? AND deleted_at IS NULL',
        [recipeId],
      );
      // The domain authors the word; the yields come off the stored recipe row,
      // not from the caller.
      minted = _authored(
        authorRecipeMeasure(
          id: id,
          recipeId: recipeId,
          label: label,
          amount: amount,
          unit: unit,
          yields: await _yieldsOf(tx, recipeId),
          measures: live,
          sortOrder: (row['m'] as int) + 1,
        ),
      );
      await _insertRow(tx, minted, householdId: _householdId, now: now);
    });
    return minted;
  }

  @override
  Future<void> restateRecipeMeasure({
    required String measureId,
    required String label,
    required double amount,
    required Unit unit,
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
          'That measure was deleted. Add it again to use it.',
        );
      }
      final recipeId = row['recipe_id'] as String;
      // `authorRecipeMeasure` compares ids, so a row is never its own
      // duplicate.
      final restated = _authored(
        authorRecipeMeasure(
          id: measureId,
          recipeId: recipeId,
          label: label,
          amount: amount,
          unit: unit,
          yields: await _yieldsOf(tx, recipeId),
          measures: await _liveMeasuresOf(tx, recipeId),
          sortOrder: (row['sort_order'] as int?) ?? 0,
        ),
      );
      // The id is untouched, so every line saying the word follows the
      // re-statement.
      await _updateRow(tx, restated, now: now);
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
      // Gated, not cascaded: a line saying a retired word would read as
      // unresolved (ADR-0018 rule 3).
    });
  }

  Future<List<RecipeMeasure>> _liveMeasuresOf(
    SqliteWriteContext tx,
    String recipeId,
  ) async {
    final rows = await tx.getAll(
      'SELECT $_columns FROM recipe_measure rm '
      'WHERE rm.recipe_id = ? AND rm.deleted_at IS NULL '
      'ORDER BY rm.sort_order, rm.created_at, rm.id',
      [recipeId],
    );
    return mergeByLabel(_rowsOf(rows, recipeId));
  }
}

/// What [recipeId] says a batch makes, read off the recipe row inside the
/// caller's transaction (ADR-0018 rule 2). An unsynced or retired recipe states
/// nothing, and `authorRecipeMeasure` then refuses with
/// `recipe_measure/no_yield`.
Future<List<YieldDenomination>> _yieldsOf(
  SqliteReadContext tx,
  String recipeId,
) async {
  final row = await tx.getOptional(
    'SELECT yield_qty, yield_unit, yield_qty_2, yield_unit_2 FROM recipe '
    'WHERE id = ? AND deleted_at IS NULL',
    [recipeId],
  );
  if (row == null) return const [];
  return yieldDenominations(
    (row['yield_qty'] as num?)?.toDouble(),
    unitById(row['yield_unit'] as String? ?? ''),
    (row['yield_qty_2'] as num?)?.toDouble(),
    unitById(row['yield_unit_2'] as String? ?? ''),
  );
}

/// The one INSERT of a measure row.
Future<void> _insertRow(
  SqliteWriteContext tx,
  RecipeMeasure measure, {
  required String householdId,
  required String now,
}) => tx.execute(
  'INSERT INTO recipe_measure (id, household_id, recipe_id, label, '
  'amount, unit, sort_order, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    measure.id,
    householdId,
    measure.recipeId,
    measure.label,
    measure.amount,
    measure.unit.id,
    measure.sortOrder,
    now,
    now,
  ],
);

/// The one UPDATE of a measure row. The id is untouched, so lines saying the
/// word follow it. Clearing `deleted_at` revives a word whose id is reused.
Future<void> _updateRow(
  SqliteWriteContext tx,
  RecipeMeasure measure, {
  required String now,
}) => tx.execute(
  'UPDATE recipe_measure SET label = ?, amount = ?, unit = ?, sort_order = ?, '
  'updated_at = ?, deleted_at = NULL WHERE id = ?',
  [
    measure.label,
    measure.amount,
    measure.unit.id,
    measure.sortOrder,
    now,
    measure.id,
  ],
);

/// What still says [measureId]: recipe component lines and week overrides, the
/// two tables that can carry the pointer. Both the bin's refusal and the
/// deferred diff's gate read it.
///
/// Only rows live along their whole chain count. A line under a tombstoned
/// group or recipe, or an override on a retired week, cannot be reached to fix,
/// and counting it would block the retirement for ever.
Future<RecipeMeasureUsage> countRecipeMeasureReferrers(
  SqliteReadContext db,
  String measureId,
) async {
  final counted = await db.get(
    'SELECT '
    '(SELECT COUNT(*) FROM recipe_line_item li '
    'JOIN ingredient_group gr ON gr.id = li.group_id '
    'JOIN recipe r ON r.id = gr.recipe_id '
    'WHERE li.recipe_measure_id = ? AND li.deleted_at IS NULL '
    'AND gr.deleted_at IS NULL AND r.deleted_at IS NULL) AS lines, '
    '(SELECT COUNT(*) FROM week_recipe_line_override wro '
    'JOIN week_plan wp ON wp.id = wro.week_plan_id '
    'WHERE wro.recipe_measure_id = ? AND wro.deleted_at IS NULL '
    'AND wp.deleted_at IS NULL) AS weeks',
    [measureId, measureId],
  );
  final lines = (counted['lines'] as num).toInt();
  final weeks = (counted['weeks'] as num).toInt();
  if (lines == 0 && weeks == 0) return RecipeMeasureUsage.none;
  // The recipes to name in the refusal, off the same live filter as [lines].
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
    weeks: weeks,
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

/// Every stored row this build can read, as [mergeByLabel] takes them.
List<StoredMeasure<RecipeMeasure>> _rowsOf(
  Iterable<Map<String, Object?>> rows,
  String recipeId,
) => [
  for (final r in rows)
    if (_rowOf(r, recipeId) case final row?) row,
];

/// One stored row as [mergeByLabel] takes it, or null for a row whose `unit`
/// this build does not know (a later build coined it). Dropped rather than
/// given a `pieces` stand-in, which would produce a wrong batch share (ADR-0018
/// rule 7); the line naming it reads [ComponentMeasureMissing].
StoredMeasure<RecipeMeasure>? _rowOf(Map<String, Object?> r, String recipeId) {
  final unit = unitById(r['unit'] as String? ?? '');
  if (unit == null) return null;
  return (
    measure: RecipeMeasure(
      id: r['id']! as String,
      recipeId: recipeId,
      label: r['label'] as String? ?? '',
      amount: (r['amount'] as num?)?.toDouble() ?? 0,
      unit: unit,
      sortOrder: (r['sort_order'] as int?) ?? 0,
    ),
    createdAt: r['created_at'],
  );
}

/// The authored measure, or the authoring refusal as a throw (repositories
/// throw; see `core/result/result.dart`).
RecipeMeasure _authored(Result<RecipeMeasure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw RecipeMeasureRefused(
    failure.code,
    failure.message,
  ),
};
