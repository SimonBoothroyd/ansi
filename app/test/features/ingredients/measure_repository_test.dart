import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/ingredients/data/measure_repository_impl.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _seedMeasure(
  PowerSyncDatabase db, {
  required String id,
  required String ingredientId,
  required String label,
  required double grams,
  int sortOrder = 0,
  String? deletedAt,
}) => db.execute(
  'INSERT INTO ingredient_measure '
  '(id, household_id, ingredient_id, label, grams, sort_order, created_at, '
  'deleted_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  [id, 'h', ingredientId, label, grams, sortOrder, '2026-01-01', deletedAt],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteMeasureRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteMeasureRepository(db);
  });

  tearDown(() => closeTestDb(db, dir));

  test("lists an ingredient's live measures, sort_order first", () async {
    await _seedMeasure(
      db,
      id: 'm-large',
      ingredientId: 'potato',
      label: 'potato, large',
      grams: 299,
      sortOrder: 1,
    );
    await _seedMeasure(
      db,
      id: 'm-medium',
      ingredientId: 'potato',
      label: 'potato, medium',
      grams: 213,
    );
    await _seedMeasure(
      db,
      id: 'm-other',
      ingredientId: 'onion',
      label: 'onion, medium',
      grams: 110,
    );
    await _seedMeasure(
      db,
      id: 'm-dead',
      ingredientId: 'potato',
      label: 'retired',
      grams: 1,
      deletedAt: '2026-01-02',
    );

    final measures = await repo.watchMeasures('potato').first;
    expect(measures.map((m) => m.id), ['m-medium', 'm-large']);
    expect(measures.first.label, 'potato, medium');
    expect(measures.first.grams, 213);
    expect(measures.last.sortOrder, 1);
  });

  test('the watch re-fires when a measure is added', () async {
    final emissions = repo.watchMeasures('potato').take(2).toList();
    // First emission: empty. Then the insert must re-fire the stream.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _seedMeasure(
      db,
      id: 'm1',
      ingredientId: 'potato',
      label: 'potato, large',
      grams: 299,
    );
    final results = await emissions;
    expect(results.first, isEmpty);
    expect(results.last.single.label, 'potato, large');
  });
}
