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
import '../../../core/units/measure.dart' show StoredMeasure, mergeByLabel;
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../domain/component_math.dart';
import '../domain/recipe_measure_authoring.dart';
import '../domain/recipe_measure_repository.dart';

const _uuid = Uuid();

/// The columns every read of the table asks for, in one place.
///
/// The **denomination** — what one of the word comes to, which is an `amount`
/// and the `unit` it is said in (ADR-0018) — is named here, in [_rowOf] and in
/// [_insertRow]/[_updateRow], and nowhere else in the app: four sites, so
/// re-stating what a measure IS is an edit to this file rather than a sweep
/// through every query, loader and provider that carries one.
const _columns =
    'rm.id, rm.recipe_id, rm.label, rm.amount, rm.unit, rm.sort_order, '
    'rm.created_at';

/// Every live recipe's own words, keyed by recipe id — the OFFER first
/// (duplicates merged, oldest canonical, `sort_order` first), then the
/// merge-hidden twins behind it.
///
/// **A line is resolved by id, so every live row has to be here.** The merge
/// hides a duplicate word rather than deleting it, and a line already pointing
/// at the hidden row still means what it said; a list that dropped it would
/// read that line as "its measure is gone" on every surface. So the hidden rows
/// ride along at the tail, where [recipeMeasureById] finds them and
/// [offeredRecipeMeasures] — which every chip row goes through — does not.
///
/// **One query for the household**, never one per recipe or per line: a
/// measured component line is looked up in its TARGET's list, so every loader
/// that builds a target, a node or a component graph wants the whole map
/// anyway, and a household's words are a handful of rows. A recipe that coins
/// none is absent from the map, which every caller reads as the empty list.
///
/// A row whose amount is missing or non-positive lands as a measure
/// [RecipeMeasure.saysAnAmount] refuses — so it names a word and converts
/// nothing, rather than converting through a number nobody stated
/// (invariant 3). A row whose `unit` is not a unit this build knows is
/// **skipped entirely** ([_rowOf]).
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

/// [rows] as the loader hands them on: the merged offer, then every live row
/// the merge hid, so a lookup by id can still reach one.
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
///
/// **The authoring gate runs on what this Save STATES, against the `makes` this
/// Save leaves behind.** The yields are read back off the recipe row inside the
/// transaction — the row has already been written by then — so a `makes` edit
/// and a word edit arriving in one Save are judged against each other, never
/// against a yield the Save is in the middle of replacing. That is the data
/// half of [recipeMeasuresOrphanedBy]: the editor warns about the words an edit
/// orphans, and this is what makes the warning true.
///
/// A word the list carries through **unchanged is never re-authored**, which is
/// ADR-0018 rule 4 in the one place it could be broken. What a batch makes is
/// the recipe's own fact and the household may restate it; a gate that refused
/// every later Save of a recipe whose word the new `makes` orphans would trap
/// the person inside the editor instead of warning them on the way out. So the
/// orphaned word stays, its lines read as `ComponentFamilyMismatch`, and only a
/// word being coined or re-stated has to answer for itself.
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
  // The editor's list is the MERGED one, so a merge-hidden twin is absent from
  // it for a reason that is not "drop this word". Its label is still kept, so
  // the row is left exactly where it is — otherwise every Save of this recipe
  // would either tombstone the twin or throw [RecipeMeasureInUse] on the lines
  // saying it.
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

  // Read once, lazily: a Save that states no new word asks the recipe row
  // nothing, and a recipe with no yield can still carry the words it already
  // has through a Save that leaves them alone.
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

/// Whether [measure] says something the stored row [was] did not — a new word,
/// or one whose denomination or label this Save re-states. Position alone is
/// not a re-statement: dragging the list re-stamps `sort_order` and states
/// nothing about what a word IS.
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
      //
      // The YIELDS come off the recipe row, here rather than from the caller:
      // the gate is "only when we know what the recipe makes", which is a fact
      // about the stored recipe and not something a form may assert.
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
          amount: amount,
          unit: unit,
          yields: await _yieldsOf(tx, recipeId),
          measures: await _liveMeasuresOf(tx, recipeId),
          sortOrder: (row['sort_order'] as int?) ?? 0,
        ),
      );
      // The id is untouched, which is the point: every line already saying the
      // word follows the re-statement without being rewritten.
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
      'SELECT $_columns FROM recipe_measure rm '
      'WHERE rm.recipe_id = ? AND rm.deleted_at IS NULL '
      'ORDER BY rm.sort_order, rm.created_at, rm.id',
      [recipeId],
    );
    return mergeByLabel(_rowsOf(rows, recipeId));
  }
}

/// What [recipeId] says a batch makes — the authoring gate's one input, read
/// off the recipe row rather than taken from a caller.
///
/// ADR-0018 rule 2: a word may only be authored against a `makes` it can be
/// held to. That is a fact about the stored recipe, so both write doors ask the
/// row for it inside their own transaction. A recipe that has not synced (or
/// has been retired) states nothing, and `authorRecipeMeasure` refuses on
/// `recipe_measure/no_yield` — which is the truth about what is known here.
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

/// The one INSERT of a measure row. Every door that mints a word goes through
/// it, so what a measure IS is stated in one statement rather than in each of
/// them.
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

/// The one UPDATE of a measure row — the re-statement, at both doors.
///
/// The **id is untouched**, which is the whole point of a re-statement: every
/// line already saying the word follows it. Clearing `deleted_at` revives a
/// word whose id is being reused, the rule the groups and the lines follow one
/// table over; on a live row it changes nothing.
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

/// What still says [measureId] — the count both the bin's refusal and the
/// deferred diff's gate read, so the two refuse on exactly the same answer.
///
/// 0048 names exactly two tables that can carry the pointer, and both are
/// counted: a recipe's component line, and one week's override of one.
///
/// **Only what is still live counts, on the whole chain.** A line under a
/// tombstoned group or recipe, and an override on a retired week, are rows
/// nothing can reach and nobody can go and change — counting them would refuse
/// the retirement for ever with no door ("1 line still says it, in 0
/// recipes"). So the count and the named recipes come off the SAME filter.
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
  // Named so the refusal can hand the reader somewhere to go — the same live
  // rows [lines] counted, which is why the two can never disagree.
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

/// Every stored row this build can read, as [mergeByLabel] takes them —
/// the rows [_rowOf] skips are simply not there.
List<StoredMeasure<RecipeMeasure>> _rowsOf(
  Iterable<Map<String, Object?>> rows,
  String recipeId,
) => [
  for (final r in rows)
    if (_rowOf(r, recipeId) case final row?) row,
];

/// One stored row as [mergeByLabel] takes it, or **null for a row whose
/// `unit` is not a unit this build knows**.
///
/// A measure is an amount in a unit, so a unit this build cannot look up leaves
/// the row unable to say the one thing it exists to say. Such a row is dropped
/// rather than given a stand-in: the fallback would be `pieces`, and `3 blob`
/// read as 3 pieces of whatever the batch is counted in is exactly the
/// confidently-wrong batch share ADR-0018 rule 7 refuses. Dropped, the line
/// naming it reads [ComponentMeasureMissing] — the same honest gap as a word
/// that has been retired, which is what a word this build cannot read IS.
///
/// It happens the way every forward-compatibility question here happens: a
/// later build coins a word in a unit this one has never heard of, and the row
/// syncs down anyway.
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
