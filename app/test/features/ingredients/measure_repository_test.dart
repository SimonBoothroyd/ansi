import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/data/measure_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/serving_measure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _seedMeasure(
  PowerSyncDatabase db, {
  required String id,
  required String ingredientId,
  required String label,
  required double amount,
  int sortOrder = 0,
  String createdAt = '2026-01-01',
  String? deletedAt,
}) => db.execute(
  'INSERT INTO ingredient_measure '
  '(id, household_id, ingredient_id, label, basis_amount, sort_order, '
  'created_at, deleted_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  [id, 'h', ingredientId, label, amount, sortOrder, createdAt, deletedAt],
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
      amount: 299,
      sortOrder: 1,
    );
    await _seedMeasure(
      db,
      id: 'm-medium',
      ingredientId: 'potato',
      label: 'potato, medium',
      amount: 213,
    );
    await _seedMeasure(
      db,
      id: 'm-other',
      ingredientId: 'onion',
      label: 'onion, medium',
      amount: 110,
    );
    await _seedMeasure(
      db,
      id: 'm-dead',
      ingredientId: 'potato',
      label: 'retired',
      amount: 1,
      deletedAt: '2026-01-02',
    );

    final measures = await repo.watchMeasures('potato').first;
    expect(measures.map((m) => m.id), ['m-medium', 'm-large']);
    expect(measures.first.label, 'potato, medium');
    expect(measures.first.amount, 213);
    expect(measures.last.sortOrder, 1);
  });

  group('duplicate labels merge on read (no unique index)', () {
    test('the oldest live row is canonical; newer dupes are hidden', () async {
      // Two offline devices both added "half can": every device must show
      // the same single chip — the oldest row by (created_at, id).
      await _seedMeasure(
        db,
        id: 'm-newer',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 210,
        createdAt: '2026-01-02',
      );
      await _seedMeasure(
        db,
        id: 'm-older',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 200,
      );

      final measures = await repo.watchMeasures('coconut').first;
      expect(measures, hasLength(1));
      expect(measures.single.id, 'm-older');
      expect(measures.single.amount, 200);
    });

    test(
      'equal created_at falls back to id order — still deterministic',
      () async {
        await _seedMeasure(
          db,
          id: 'm-b',
          ingredientId: 'coconut',
          label: 'half can',
          amount: 210,
        );
        await _seedMeasure(
          db,
          id: 'm-a',
          ingredientId: 'coconut',
          label: 'half can',
          amount: 200,
        );

        final measures = await repo.watchMeasures('coconut').first;
        expect(measures.single.id, 'm-a');
      },
    );

    test('the tie-break survives mixed timestamp text formats', () async {
      // created_at is TEXT: this client writes `…T…Z`, Postgres-synced rows
      // arrive as `… …Z` (the space separator is the operative difference).
      // Lexicographically the space sorts before 'T', which would crown the
      // WRONG row; the merge compares parsed instants.
      await _seedMeasure(
        db,
        id: 'm-app',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 200,
        createdAt: '2026-01-01T05:00:00.000Z', // older instant, Dart format
      );
      await _seedMeasure(
        db,
        id: 'm-pg',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 210,
        createdAt: '2026-01-01 12:00:00Z', // newer instant, synced PG format
      );

      final measures = await repo.watchMeasures('coconut').first;
      expect(measures.single.id, 'm-app');
      expect(measures.single.amount, 200);
    });

    test('a zone-less timestamp is read as UTC, not device-local', () async {
      // A bare `2026-01-01 12:00:00` would parse in the device's LOCAL zone,
      // so two devices in different zones would disagree about which row is
      // oldest. The merge assumes UTC for zone-less values instead.
      await _seedMeasure(
        db,
        id: 'm-zoneless',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 200,
        createdAt: '2026-01-01 05:00:00', // older instant, no zone marker
      );
      await _seedMeasure(
        db,
        id: 'm-utc',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 210,
        createdAt: '2026-01-01T12:00:00.000Z', // newer instant, explicit UTC
      );

      final measures = await repo.watchMeasures('coconut').first;
      expect(measures.single.id, 'm-zoneless');
      expect(measures.single.amount, 200);
    });

    test('a soft-deleted canonical un-hides the surviving duplicate', () async {
      await _seedMeasure(
        db,
        id: 'm-older',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 200,
      );
      await _seedMeasure(
        db,
        id: 'm-newer',
        ingredientId: 'coconut',
        label: 'half can',
        amount: 210,
        createdAt: '2026-01-02',
      );

      await repo.softDeleteMeasure('m-older');
      final measures = await repo.watchMeasures('coconut').first;
      expect(measures.single.id, 'm-newer');
      expect(measures.single.amount, 210);
    });
  });

  group('the editor write path', () {
    test(
      'addMeasure writes a manual-sourced row after the existing ones',
      () async {
        await _seedMeasure(
          db,
          id: 'm-can',
          ingredientId: 'coconut',
          label: 'can (400 ml)',
          amount: 400,
          sortOrder: 3,
        );

        final added = await repo.addMeasure(
          ingredientId: 'coconut',
          label: 'half can',
          amount: 200,
        );
        expect(added.source, 'manual');
        expect(added.sortOrder, 4);

        final measures = await repo.watchMeasures('coconut').first;
        expect(measures.map((m) => m.label), ['can (400 ml)', 'half can']);
        expect(measures.last.amount, 200);
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
        amount: 200,
      );
      await repo.softDeleteMeasure(added.id);

      expect(await repo.watchMeasures('coconut').first, isEmpty);
      final row = await db.get(
        'SELECT deleted_at FROM ingredient_measure WHERE id = ?',
        [added.id],
      );
      expect(row['deleted_at'], isNotNull);
    });

    test('addMeasure validates at the repository, not just the form', () async {
      // Volume-named labels (case/space/plural disguises included) would
      // shadow density-owned conversion; bad grams could never convert.
      for (final label in ['cup', ' Cups ', 'tbsp', 'ml']) {
        await expectLater(
          repo.addMeasure(ingredientId: 'coconut', label: label, amount: 200),
          throwsArgumentError,
          reason: label,
        );
      }
      for (final amount in [0.0, -5.0, double.nan]) {
        await expectLater(
          repo.addMeasure(
            ingredientId: 'coconut',
            label: 'half can',
            amount: amount,
          ),
          throwsArgumentError,
          reason: '$amount',
        );
      }
      await expectLater(
        repo.addMeasure(ingredientId: 'coconut', label: '   ', amount: 200),
        throwsArgumentError,
      );
      expect(await repo.watchMeasures('coconut').first, isEmpty);
    });

    test('addMeasure stores the trimmed label', () async {
      final added = await repo.addMeasure(
        ingredientId: 'coconut',
        label: '  half can ',
        amount: 200,
      );
      expect(added.label, 'half can');
      final row = await db.get(
        'SELECT label FROM ingredient_measure WHERE id = ?',
        [added.id],
      );
      expect(row['label'], 'half can');
    });

    test(
      're-adding a deleted label starts fresh (tombstone never blocks)',
      () async {
        final first = await repo.addMeasure(
          ingredientId: 'coconut',
          label: 'half can',
          amount: 200,
        );
        await repo.softDeleteMeasure(first.id);
        final second = await repo.addMeasure(
          ingredientId: 'coconut',
          label: 'half can',
          amount: 190,
        );

        final measures = await repo.watchMeasures('coconut').first;
        expect(measures.single.id, second.id);
        expect(measures.single.amount, 190);
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
      amount: 299,
    );
    final results = await emissions;
    expect(results.first, isEmpty);
    expect(results.last.single.label, 'potato, large');
  });

  group('basis-aware reads', () {
    test('a per-ml ingredient denominates its measures in ml', () async {
      await db.execute(
        'INSERT INTO ingredient (id, household_id, canonical_name, '
        'default_unit, macros_basis, status, source, match_text) VALUES '
        "('coconut', 'h', 'Coconut Milk', 'cup', 'ml', 'complete', 'seed', "
        "'coconut milk')",
      );
      await _seedMeasure(
        db,
        id: 'm-can',
        ingredientId: 'coconut',
        label: 'can (400 ml)',
        amount: 400,
      );
      final measures = await repo.watchMeasures('coconut').first;
      expect(measures.single.basis, MacrosBasis.perMl);
      expect(measures.single.amount, 400);
    });

    test('a measure without a local vocab row still lists, per-g', () async {
      // Sync order can deliver the measure before its ingredient — the LEFT
      // join keeps it visible with the per-g fallback.
      await _seedMeasure(
        db,
        id: 'm-orphan',
        ingredientId: 'not-synced-yet',
        label: 'scoop',
        amount: 30,
      );
      final measures = await repo.watchMeasures('not-synced-yet').first;
      expect(measures.single.basis, MacrosBasis.perG);
    });
  });

  group('measuresByIngredients — the batched read', () {
    test('keys every asked-for ingredient that has measures, with the same '
        'order and duplicate merge as the watch', () async {
      await _seedMeasure(
        db,
        id: 'm-large',
        ingredientId: 'potato',
        label: 'potato, large',
        amount: 299,
        sortOrder: 1,
      );
      await _seedMeasure(
        db,
        id: 'm-medium',
        ingredientId: 'potato',
        label: 'potato, medium',
        amount: 213,
      );
      await _seedMeasure(
        db,
        id: 'm-dupe',
        ingredientId: 'potato',
        label: 'potato, medium', // the offline duplicate: hidden, not deleted
        amount: 200,
        createdAt: '2026-02-01',
      );
      await _seedMeasure(
        db,
        id: 'm-dead',
        ingredientId: 'potato',
        label: 'retired',
        amount: 1,
        deletedAt: '2026-01-02',
      );
      await _seedMeasure(
        db,
        id: 'm-clove',
        ingredientId: 'garlic',
        label: 'clove',
        amount: 3,
      );

      final batched = await repo.measuresByIngredients({
        'potato',
        'garlic',
        'nothing-here',
      });

      expect(batched.keys.toSet(), {'potato', 'garlic'});
      expect(batched['potato']!.map((m) => m.id), ['m-medium', 'm-large']);
      expect(batched['garlic']!.single.label, 'clove');
      // Byte-for-byte the watch's answer — one rule, two readers.
      expect(batched['potato'], await repo.watchMeasures('potato').first);
    });

    test('an empty id set reads nothing at all', () async {
      expect(await repo.measuresByIngredients(const {}), isEmpty);
    });

    test('a measure without a local vocab row still lists, per-g', () async {
      await _seedMeasure(
        db,
        id: 'm-orphan',
        ingredientId: 'not-synced-yet',
        label: 'scoop',
        amount: 30,
      );
      final batched = await repo.measuresByIngredients({'not-synced-yet'});
      expect(batched['not-synced-yet']!.single.basis, MacrosBasis.perG);
    });
  });

  group('renaming and re-weighing in place', () {
    setUp(
      () => _seedMeasure(
        db,
        id: 'm-can',
        ingredientId: 'tomatoes',
        label: 'can (400 g)',
        amount: 400,
      ),
    );

    test('a rename keeps the id, so every line follows it', () async {
      await repo.renameMeasure('m-can', '  can (380 g)  ');
      final m = (await repo.watchMeasures('tomatoes').first).single;
      expect(m.id, 'm-can');
      expect(m.label, 'can (380 g)');
      expect(m.amount, 400);
    });

    test('a re-weigh keeps the id and the label', () async {
      await repo.setMeasureAmount('m-can', 380);
      final m = (await repo.watchMeasures('tomatoes').first).single;
      expect(m.id, 'm-can');
      expect(m.label, 'can (400 g)');
      expect(m.amount, 380);
    });

    test("it holds the add form's lines on the label", () async {
      await expectLater(
        repo.renameMeasure('m-can', '   '),
        throwsArgumentError,
      );
      await expectLater(
        repo.renameMeasure('m-can', 'cup'),
        throwsArgumentError,
      );
      await expectLater(repo.setMeasureAmount('m-can', 0), throwsArgumentError);
      await expectLater(
        repo.setMeasureAmount('m-can', double.nan),
        throwsArgumentError,
      );
      // Nothing moved.
      final m = (await repo.watchMeasures('tomatoes').first).single;
      expect(m.label, 'can (400 g)');
      expect(m.amount, 400);
    });

    test('a live label collision is refused rather than merged away', () async {
      await _seedMeasure(
        db,
        id: 'm-half',
        ingredientId: 'tomatoes',
        label: 'half can',
        amount: 200,
        sortOrder: 1,
      );
      await expectLater(
        repo.renameMeasure('m-half', 'can (400 g)'),
        throwsArgumentError,
      );
      // A tombstoned twin is not a collision: it is not live.
      await _seedMeasure(
        db,
        id: 'm-gone',
        ingredientId: 'tomatoes',
        label: 'tin',
        amount: 400,
        sortOrder: 2,
        deletedAt: '2026-01-02',
      );
      await repo.renameMeasure('m-half', 'tin');
      expect((await repo.watchMeasures('tomatoes').first).map((m) => m.label), [
        'can (400 g)',
        'tin',
      ]);
      // Nor is the same label on ANOTHER ingredient.
      await _seedMeasure(
        db,
        id: 'm-other-can',
        ingredientId: 'beans',
        label: 'drum',
        amount: 400,
      );
      await repo.renameMeasure('m-half', 'drum');
      expect(
        (await repo.watchMeasures('beans').first).single.id,
        'm-other-can',
      );
    });

    test('a rename never crosses the reserved serving prefix', () async {
      await _seedMeasure(
        db,
        id: 'm-serving',
        ingredientId: 'tomatoes',
        label: '${kServingMeasurePrefix}1 cup',
        amount: 236.59,
        sortOrder: 1,
      );
      // In: a second serving would appear from nowhere.
      await expectLater(
        repo.renameMeasure('m-can', '${kServingMeasurePrefix}1 can'),
        throwsArgumentError,
      );
      // Out: the row's stated serving would quietly stop being one.
      await expectLater(
        repo.renameMeasure('m-serving', 'a cupful'),
        throwsArgumentError,
      );
      final labels = (await repo.watchMeasures('tomatoes').first).map(
        (m) => m.label,
      );
      expect(labels, ['can (400 g)', '${kServingMeasurePrefix}1 cup']);
    });

    test('a reorder re-stamps sort_order by position', () async {
      await _seedMeasure(
        db,
        id: 'm-half',
        ingredientId: 'tomatoes',
        label: 'half can',
        amount: 200,
        sortOrder: 1,
      );
      await _seedMeasure(
        db,
        id: 'm-crate',
        ingredientId: 'tomatoes',
        label: 'crate',
        amount: 4800,
        sortOrder: 2,
      );

      await repo.reorderMeasures('tomatoes', ['m-crate', 'm-can', 'm-half']);

      final measures = await repo.watchMeasures('tomatoes').first;
      expect(measures.map((m) => m.id), ['m-crate', 'm-can', 'm-half']);
      expect(measures.map((m) => m.sortOrder), [0, 1, 2]);
    });

    test('a reorder never reaches another ingredient\'s rows', () async {
      await _seedMeasure(
        db,
        id: 'm-foreign',
        ingredientId: 'beans',
        label: 'tin',
        amount: 400,
        sortOrder: 7,
      );
      await repo.reorderMeasures('tomatoes', ['m-foreign', 'm-can']);
      expect((await repo.watchMeasures('beans').first).single.sortOrder, 7);
      // The one row it does own still landed, at its own position.
      expect((await repo.watchMeasures('tomatoes').first).single.sortOrder, 1);
    });

    test(
      'an id naming no live measure is refused, not silently ignored',
      () async {
        await repo.softDeleteMeasure('m-can');
        await expectLater(
          repo.renameMeasure('m-can', 'crate'),
          throwsArgumentError,
        );
      },
    );
  });
}
