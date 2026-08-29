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
  String createdAt = '2026-01-01',
  String? deletedAt,
}) => db.execute(
  'INSERT INTO ingredient_measure '
  '(id, household_id, ingredient_id, label, grams, sort_order, created_at, '
  'deleted_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  [id, 'h', ingredientId, label, grams, sortOrder, createdAt, deletedAt],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteMeasureRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteMeasureRepository(db, householdId: 'h');
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

  group('duplicate labels merge on read (0011 — no unique index)', () {
    test('the oldest live row is canonical; newer dupes are hidden', () async {
      // Two offline devices both added "half can": every device must show
      // the same single chip — the oldest row by (created_at, id).
      await _seedMeasure(
        db,
        id: 'm-newer',
        ingredientId: 'coconut',
        label: 'half can',
        grams: 210,
        createdAt: '2026-01-02',
      );
      await _seedMeasure(
        db,
        id: 'm-older',
        ingredientId: 'coconut',
        label: 'half can',
        grams: 200,
      );

      final measures = await repo.watchMeasures('coconut').first;
      expect(measures, hasLength(1));
      expect(measures.single.id, 'm-older');
      expect(measures.single.grams, 200);
    });

    test(
      'equal created_at falls back to id order — still deterministic',
      () async {
        await _seedMeasure(
          db,
          id: 'm-b',
          ingredientId: 'coconut',
          label: 'half can',
          grams: 210,
        );
        await _seedMeasure(
          db,
          id: 'm-a',
          ingredientId: 'coconut',
          label: 'half can',
          grams: 200,
        );

        final measures = await repo.watchMeasures('coconut').first;
        expect(measures.single.id, 'm-a');
      },
    );

    test('a soft-deleted canonical un-hides the surviving duplicate', () async {
      await _seedMeasure(
        db,
        id: 'm-older',
        ingredientId: 'coconut',
        label: 'half can',
        grams: 200,
      );
      await _seedMeasure(
        db,
        id: 'm-newer',
        ingredientId: 'coconut',
        label: 'half can',
        grams: 210,
        createdAt: '2026-01-02',
      );

      await repo.softDeleteMeasure('m-older');
      final measures = await repo.watchMeasures('coconut').first;
      expect(measures.single.id, 'm-newer');
      expect(measures.single.grams, 210);
    });
  });

  group('the editor write path (0011)', () {
    test(
      'addMeasure writes a manual-sourced row after the existing ones',
      () async {
        await _seedMeasure(
          db,
          id: 'm-can',
          ingredientId: 'coconut',
          label: 'can (400 ml)',
          grams: 400,
          sortOrder: 3,
        );

        final added = await repo.addMeasure(
          ingredientId: 'coconut',
          label: 'half can',
          grams: 200,
        );
        expect(added.source, 'manual');
        expect(added.sortOrder, 4);

        final measures = await repo.watchMeasures('coconut').first;
        expect(measures.map((m) => m.label), ['can (400 ml)', 'half can']);
        expect(measures.last.grams, 200);
        final row = await db.get(
          'SELECT household_id, source FROM ingredient_measure WHERE id = ?',
          [added.id],
        );
        expect(row['household_id'], 'h');
        expect(row['source'], 'manual');
      },
    );

    test('softDeleteMeasure tombstones, never hard-deletes', () async {
      final added = await repo.addMeasure(
        ingredientId: 'coconut',
        label: 'half can',
        grams: 200,
      );
      await repo.softDeleteMeasure(added.id);

      expect(await repo.watchMeasures('coconut').first, isEmpty);
      final row = await db.get(
        'SELECT deleted_at FROM ingredient_measure WHERE id = ?',
        [added.id],
      );
      expect(row['deleted_at'], isNotNull);
    });

    test(
      're-adding a deleted label starts fresh (tombstone never blocks)',
      () async {
        final first = await repo.addMeasure(
          ingredientId: 'coconut',
          label: 'half can',
          grams: 200,
        );
        await repo.softDeleteMeasure(first.id);
        final second = await repo.addMeasure(
          ingredientId: 'coconut',
          label: 'half can',
          grams: 190,
        );

        final measures = await repo.watchMeasures('coconut').first;
        expect(measures.single.id, second.id);
        expect(measures.single.grams, 190);
      },
    );
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
