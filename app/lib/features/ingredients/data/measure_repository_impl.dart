/// [MeasureRepository] over the local PowerSync SQLite (synced vocab rows).
library;

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/measure.dart';
import '../domain/measure_repository.dart';

class SqliteMeasureRepository implements MeasureRepository {
  const SqliteMeasureRepository(this._db);

  final SqliteConnection _db;

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) {
    return _db
        .watch(
          'SELECT id, label, grams, sort_order FROM ingredient_measure '
          'WHERE ingredient_id = ? AND deleted_at IS NULL '
          'ORDER BY sort_order, created_at',
          parameters: [ingredientId],
        )
        .map(
          (rows) => rows
              .map(
                (r) => Measure(
                  id: r['id'] as String,
                  label: r['label'] as String,
                  grams: (r['grams'] as num).toDouble(),
                  sortOrder: (r['sort_order'] as int?) ?? 0,
                ),
              )
              .toList(),
        );
  }
}
