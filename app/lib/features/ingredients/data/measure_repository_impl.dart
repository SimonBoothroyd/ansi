/// [MeasureRepository] over the local PowerSync SQLite (synced vocab rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../domain/allowed_units.dart';
import '../domain/measure_repository.dart';
import '../domain/serving_measure.dart';

const _uuid = Uuid();

class SqliteMeasureRepository implements MeasureRepository {
  const SqliteMeasureRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  // Both reads spell their SELECT out in full: `watch_coverage_test` reads
  // these queries as literals and cannot see an interpolated fragment. The
  // row→list rule is shared in [_merge].

  /// One ingredient's rows through [mergeByLabel] — the shared body of
  /// [watchMeasures] and [measuresByIngredients].
  static List<Measure> _merge(Iterable<Map<String, dynamic>> rows) =>
      mergeByLabel([
        for (final r in rows)
          (
            measure: Measure(
              id: r['id'] as String,
              label: r['label'] as String,
              amount: (r['basis_amount'] as num).toDouble(),
              basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
              sortOrder: (r['sort_order'] as int?) ?? 0,
              source: r['source'] as String?,
            ),
            createdAt: r['created_at'],
          ),
      ]);

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    // Ids are uuids we minted or synced, never user text; they still ride as
    // bound parameters rather than being interpolated into the SQL.
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT m.id, m.ingredient_id, m.label, m.basis_amount, m.sort_order, '
      'm.source, m.created_at, i.macros_basis '
      'FROM ingredient_measure m '
      'LEFT JOIN ingredient i ON i.id = m.ingredient_id '
      'WHERE m.ingredient_id IN ($placeholders) AND m.deleted_at IS NULL '
      'ORDER BY m.created_at, m.id',
      ids.toList(),
    );
    final byIngredient = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      (byIngredient[r['ingredient_id'] as String] ??= []).add(r);
    }
    return {for (final e in byIngredient.entries) e.key: _merge(e.value)};
  }

  /// The ingredient join supplies the basis the amounts are in (ADR-0008).
  /// LEFT, so a measure whose vocab row has not synced still lists (basis falls
  /// back to per-g), and with a selected column so the watch fires on
  /// ingredient edits (SQLite drops an unselected LEFT JOIN).
  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) {
    return _db
        .watch(
          'SELECT m.id, m.ingredient_id, m.label, m.basis_amount, '
          'm.sort_order, m.source, m.created_at, i.macros_basis '
          'FROM ingredient_measure m '
          'LEFT JOIN ingredient i ON i.id = m.ingredient_id '
          'WHERE m.ingredient_id = ? AND m.deleted_at IS NULL '
          'ORDER BY m.created_at, m.id',
          parameters: [ingredientId],
        )
        .map(_merge);
  }

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async {
    // Validated here so every write path holds the same rules: a volume-named
    // label would shadow density, and a non-positive or NaN amount cannot
    // convert.
    final trimmed = measureLabelAsAuthored(label);
    if (trimmed.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (isVolumeUnitLabel(trimmed)) {
      throw ArgumentError.value(
        label,
        'label',
        'names a volume unit — density owns volume conversion',
      );
    }
    if (!(amount > 0)) {
      // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
      throw ArgumentError.value(amount, 'amount', 'must be a positive number');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    late final int sortOrder;
    late final MacrosBasis basis;
    await _db.writeTransaction((tx) async {
      // The amount's basis is the ingredient's (ADR-0008); read it so the
      // returned Measure labels itself correctly.
      final ing = await tx.getOptional(
        'SELECT macros_basis FROM ingredient WHERE id = ?',
        [ingredientId],
      );
      basis = MacrosBasis.fromDb(ing?['macros_basis'] as String?);
      // After the existing measures. A plain INSERT: view-backed local tables
      // reject UPSERT. No label-collision check; duplicates merge on read.
      final row = await tx.get(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM ingredient_measure '
        'WHERE ingredient_id = ? AND deleted_at IS NULL',
        [ingredientId],
      );
      sortOrder = (row['m'] as int) + 1;
      await tx.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount, sort_order, '
        'source, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _householdId,
          ingredientId,
          trimmed,
          amount,
          sortOrder,
          'manual',
          now,
          now,
        ],
      );
    });
    return Measure(
      id: id,
      label: trimmed,
      amount: amount,
      basis: basis,
      sortOrder: sortOrder,
      source: 'manual',
    );
  }

  @override
  Future<void> renameMeasure(String measureId, String label) async {
    // The add form's lines, held here rather than in the row's editor, for
    // the reason addMeasure states: every write path must hold the same ones.
    final trimmed = measureLabelAsAuthored(label);
    if (trimmed.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (isVolumeUnitLabel(trimmed)) {
      throw ArgumentError.value(
        label,
        'label',
        'names a volume unit — density owns volume conversion',
      );
    }
    if (trimmed.startsWith(kServingMeasurePrefix)) {
      throw ArgumentError.value(
        label,
        'label',
        'is the serving’s reserved name — a serving is stated in the '
            'nutrition section',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT ingredient_id, label FROM ingredient_measure '
        'WHERE id = ? AND deleted_at IS NULL',
        [measureId],
      );
      if (row == null) {
        throw ArgumentError.value(
          measureId,
          'measureId',
          'names no live measure',
        );
      }
      if ((row['label'] as String).startsWith(kServingMeasurePrefix)) {
        throw ArgumentError.value(
          label,
          'label',
          'renames the serving — it is stated in the nutrition section',
        );
      }
      // The same key the merge deduplicates on, so this refuses exactly the
      // renames that would hide a row.
      final clash = await tx.getOptional(
        'SELECT id FROM ingredient_measure WHERE ingredient_id = ? '
        'AND deleted_at IS NULL AND label = ? AND id <> ?',
        [row['ingredient_id'], trimmed, measureId],
      );
      if (clash != null) {
        throw ArgumentError.value(
          label,
          'label',
          'is already a measure of this ingredient',
        );
      }
      await tx.execute(
        'UPDATE ingredient_measure SET label = ?, updated_at = ? WHERE id = ?',
        [trimmed, now, measureId],
      );
    });
  }

  @override
  Future<void> setMeasureAmount(String measureId, double amount) async {
    // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
    if (!(amount > 0)) {
      throw ArgumentError.value(amount, 'amount', 'must be a positive number');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE ingredient_measure SET basis_amount = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [amount, now, measureId],
    );
  }

  @override
  Future<void> reorderMeasures(String ingredientId, List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      // Stamped by position rather than swapped in pairs, so two devices' drags
      // converge per row on the last write.
      for (final (index, id) in ids.indexed) {
        await tx.execute(
          'UPDATE ingredient_measure SET sort_order = ?, updated_at = ? '
          'WHERE id = ? AND ingredient_id = ? AND deleted_at IS NULL',
          [index, now, id, ingredientId],
        );
      }
    });
  }

  @override
  Future<MeasureUsage> countLinesUsing(String measureId) async {
    // The three tables that can carry a `measure_id`, live rows only: recipe
    // lines, shopping contributions, planned ingredient meals.
    final counted = await _db.get(
      'SELECT '
      '(SELECT COUNT(*) FROM recipe_line_item '
      'WHERE measure_id = ? AND deleted_at IS NULL) '
      '+ (SELECT COUNT(*) FROM shopping_list_contribution '
      'WHERE measure_id = ? AND deleted_at IS NULL) '
      '+ (SELECT COUNT(*) FROM plan_entry '
      'WHERE measure_id = ? AND deleted_at IS NULL) AS n',
      [measureId, measureId, measureId],
    );
    final lines = (counted['n'] as num).toInt();
    if (lines == 0) return MeasureUsage.none;
    // Named so the refusal can point somewhere. A line whose group or recipe is
    // gone is counted above but has no page to name.
    final rows = await _db.getAll(
      'SELECT DISTINCT r.id AS id, r.title AS title '
      'FROM recipe_line_item li '
      'JOIN ingredient_group gr ON gr.id = li.group_id '
      'JOIN recipe r ON r.id = gr.recipe_id '
      'WHERE li.measure_id = ? AND li.deleted_at IS NULL '
      'AND gr.deleted_at IS NULL AND r.deleted_at IS NULL '
      'ORDER BY r.title',
      [measureId],
    );
    return MeasureUsage(
      lines: lines,
      recipes: [
        for (final r in rows)
          (id: r['id'] as String, title: (r['title'] as String?) ?? 'Untitled'),
      ],
    );
  }

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE ingredient_measure SET deleted_at = ?, updated_at = ? '
        'WHERE id = ?',
        [now, now, measureId],
      );
      // Nothing else follows a measure out (ADR-0015): a piece weight borrowed
      // from it is a number on the ingredient row and stays.
    });
  }
}
