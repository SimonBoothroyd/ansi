/// [MeasureRepository] over the local PowerSync SQLite (synced vocab rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/measure.dart';
import '../domain/measure_repository.dart';

const _uuid = Uuid();

class SqliteMeasureRepository implements MeasureRepository {
  const SqliteMeasureRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) {
    // Ordered oldest-first so the merge below keeps the canonical (oldest)
    // row per duplicate label on every device — the offline-dupe doctrine
    // (see the interface doc). Display order is re-established afterwards.
    return _db
        .watch(
          'SELECT id, label, grams, sort_order, source, created_at '
          'FROM ingredient_measure '
          'WHERE ingredient_id = ? AND deleted_at IS NULL '
          'ORDER BY created_at, id',
          parameters: [ingredientId],
        )
        .map((rows) {
          final byLabel = <String, (Measure, String)>{};
          for (final r in rows) {
            final label = r['label'] as String;
            if (byLabel.containsKey(label)) continue; // newer dupe — hidden
            byLabel[label] = (
              Measure(
                id: r['id'] as String,
                label: label,
                grams: (r['grams'] as num).toDouble(),
                sortOrder: (r['sort_order'] as int?) ?? 0,
                source: r['source'] as String?,
              ),
              r['created_at'] as String? ?? '',
            );
          }
          final kept = byLabel.values.toList()
            ..sort((a, b) {
              final bySort = a.$1.sortOrder.compareTo(b.$1.sortOrder);
              if (bySort != 0) return bySort;
              final byCreated = a.$2.compareTo(b.$2);
              return byCreated != 0 ? byCreated : a.$1.id.compareTo(b.$1.id);
            });
          return [for (final (m, _) in kept) m];
        });
  }

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double grams,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    late final int sortOrder;
    await _db.writeTransaction((tx) async {
      // After the existing measures. A plain INSERT, never ON CONFLICT
      // (view-backed local tables reject UPSERT), and no label collision
      // check — a duplicate merges on read instead of failing anywhere.
      final row = await tx.get(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM ingredient_measure '
        'WHERE ingredient_id = ? AND deleted_at IS NULL',
        [ingredientId],
      );
      sortOrder = (row['m'] as int) + 1;
      await tx.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, grams, sort_order, source, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, _householdId, ingredientId, label, grams, sortOrder, 'manual', now, now],
      );
    });
    return Measure(
      id: id,
      label: label,
      grams: grams,
      sortOrder: sortOrder,
      source: 'manual',
    );
  }

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE ingredient_measure SET deleted_at = ?, updated_at = ? '
      'WHERE id = ?',
      [now, now, measureId],
    );
  }
}
