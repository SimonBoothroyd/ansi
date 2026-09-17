import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/price_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _seedIngredient(
  PowerSyncDatabase db, {
  String id = 'banana',
  String basis = 'g',
}) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
  'macros_basis) VALUES (?, ?, ?, ?, ?)',
  [id, 'h', 'Bananas, organic', 'piece', basis],
);

Future<void> _seedMeasure(
  PowerSyncDatabase db, {
  required String id,
  required String ingredientId,
  required String label,
  required double amount,
  String? deletedAt,
}) => db.execute(
  'INSERT INTO ingredient_measure (id, household_id, ingredient_id, label, '
  'basis_amount, sort_order, created_at, deleted_at) '
  'VALUES (?, ?, ?, ?, ?, 0, ?, ?)',
  [id, 'h', ingredientId, label, amount, '2026-01-01', deletedAt],
);

Future<void> _seedReceipt(
  PowerSyncDatabase db, {
  required String id,
  required String store,
  required String purchasedAt,
  String source = 'photo',
  String? deletedAt,
}) => db.execute(
  'INSERT INTO receipt (id, household_id, store, purchased_at, source, '
  'created_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
  [id, 'h', store, purchasedAt, source, purchasedAt, deletedAt],
);

Future<void> _seedLine(
  PowerSyncDatabase db, {
  required String id,
  required String receiptId,
  String? ingredientId = 'banana',
  int cents = 349,
  int discountCents = 0,
  String kind = 'item',
  double? packBasisAmount = 454,
  double? packAmount,
  String? packUnit,
  String? measureId,
  String createdAt = '2026-01-01',
  String? deletedAt,
}) => db.execute(
  'INSERT INTO receipt_line (id, household_id, receipt_id, ingredient_id, '
  'cents, discount_cents, kind, pack_basis_amount, pack_amount, pack_unit, '
  'measure_id, sort_order, created_at, deleted_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)',
  [
    id,
    'h',
    receiptId,
    ingredientId,
    cents,
    discountCents,
    kind,
    packBasisAmount,
    packAmount,
    packUnit,
    measureId,
    createdAt,
    deletedAt,
  ],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqlitePriceRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqlitePriceRepository(db, householdId: 'h');
    await _seedIngredient(db);
  });

  tearDown(() => closeTestDb(db, dir));

  group('watchPrices', () {
    test('newest first — the latest is what a recipe reads', () async {
      await _seedReceipt(
        db,
        id: 'r-aug',
        store: 'Whole Foods',
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-sep',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l-aug', receiptId: 'r-aug', cents: 399);
      await _seedLine(db, id: 'l-sep', receiptId: 'r-sep');

      final prices = await repo.watchPrices('banana').first;
      expect(prices.map((p) => p.lineId), ['l-sep', 'l-aug']);
      expect(prices.first.store, "TJ's");
      expect(prices.first.purchasedAt, DateTime.utc(2026, 9, 13, 17, 20));
      expect(
        formatPricePer100(prices.first.per100.valueOrNull!),
        '77¢ / 100 g',
      );
      expect(formatPricePer100(prices.last.per100.valueOrNull!), '88¢ / 100 g');
    });

    test('the pack keeps the word it was named with', () async {
      await _seedMeasure(
        db,
        id: 'm-bag',
        ingredientId: 'banana',
        label: 'bag',
        amount: 454,
      );
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r1', measureId: 'm-bag');

      final prices = await repo.watchPrices('banana').first;
      expect(prices.single.packLabel, 'bag');
      expect(prices.single.packBasisAmount, 454);
    });

    test('a deleted measure leaves the amount and loses the word', () async {
      await _seedMeasure(
        db,
        id: 'm-bag',
        ingredientId: 'banana',
        label: 'bag',
        amount: 454,
        deletedAt: '2026-09-14T00:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r1', measureId: 'm-bag');

      final prices = await repo.watchPrices('banana').first;
      expect(prices.single.packLabel, isNull);
      expect(prices.single.packBasisAmount, 454);
    });

    test('a per-ml row reads its prices in its own dimension', () async {
      await _seedIngredient(db, id: 'oil', basis: 'ml');
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(
        db,
        id: 'l1',
        receiptId: 'r1',
        ingredientId: 'oil',
        cents: 899,
        packBasisAmount: 500,
      );

      final prices = await repo.watchPrices('oil').first;
      expect(
        formatPricePer100(prices.single.per100.valueOrNull!),
        r'$1.80 / 100 ml',
      );
    });

    test('a discount is taken off what was paid', () async {
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r1', discountCents: 50);

      final prices = await repo.watchPrices('banana').first;
      expect(prices.single.cents, 349);
      expect(prices.single.paidCents, 299);
    });

    test('lines that are not prices never appear as zeros', () async {
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      // Matched, but nobody has said what the pack is.
      await _seedLine(
        db,
        id: 'l-nopack',
        receiptId: 'r1',
        packBasisAmount: null,
      );
      // Marked not food in review.
      await _seedLine(
        db,
        id: 'l-notfood',
        receiptId: 'r1',
        kind: 'not_food',
        packBasisAmount: null,
      );
      // Tombstoned.
      await _seedLine(
        db,
        id: 'l-gone',
        receiptId: 'r1',
        deletedAt: '2026-09-14T00:00:00Z',
      );

      expect(await repo.watchPrices('banana').first, isEmpty);
    });

    test('a deleted receipt takes its prices with it', () async {
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
        deletedAt: '2026-09-14T00:00:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r1');

      expect(await repo.watchPrices('banana').first, isEmpty);
    });

    test('another ingredient’s prices stay on that ingredient', () async {
      await _seedIngredient(db, id: 'apple');
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r1', ingredientId: 'apple');

      expect(await repo.watchPrices('banana').first, isEmpty);
      expect(await repo.watchPrices('apple').first, hasLength(1));
    });

    test(
      'a Postgres-shaped timestamp dates the same as this client’s',
      () async {
        await _seedReceipt(
          db,
          id: 'r1',
          store: "TJ's",
          // The space separator a synced row arrives with.
          purchasedAt: '2026-09-13 17:20:00Z',
        );
        await _seedLine(db, id: 'l1', receiptId: 'r1');

        final prices = await repo.watchPrices('banana').first;
        expect(prices.single.purchasedAt, DateTime.utc(2026, 9, 13, 17, 20));
      },
    );
  });

  group('watchStores', () {
    test('the words this household has used, most recent first', () async {
      await _seedReceipt(
        db,
        id: 'r-aug',
        store: 'Whole Foods',
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-sep',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-jul',
        store: "TJ's",
        purchasedAt: '2026-07-01T10:00:00Z',
      );

      expect(await repo.watchStores().first, ["TJ's", 'Whole Foods']);
    });

    test('a deleted receipt takes its store word out of the offer', () async {
      await _seedReceipt(
        db,
        id: 'r1',
        store: 'Somewhere Else',
        purchasedAt: '2026-09-13T17:20:00Z',
        deletedAt: '2026-09-14T00:00:00Z',
      );
      expect(await repo.watchStores().first, isEmpty);
    });
  });

  group('recordManualPrice', () {
    test('writes a one-line manual receipt, readable as a price', () async {
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
        purchasedAt: DateTime.utc(2026, 9, 13, 17, 20),
      );

      final receipt = await db.get('SELECT * FROM receipt');
      expect(receipt['source'], 'manual');
      expect(receipt['store'], "TJ's");
      expect(
        receipt['subtotal_cents'],
        349,
        reason: 'a typed price has one line, so that IS the subtotal',
      );
      expect(receipt['tax_cents'], isNull);
      expect(receipt['total_cents'], isNull);

      final prices = await repo.watchPrices('banana').first;
      expect(
        formatPricePer100(prices.single.per100.valueOrNull!),
        '77¢ / 100 g',
      );
      expect(prices.single.purchasedAt, DateTime.utc(2026, 9, 13, 17, 20));
      expect(prices.single.store, "TJ's");
    });

    test('the pack’s word rides along when one was picked', () async {
      await _seedMeasure(
        db,
        id: 'm-bag',
        ingredientId: 'banana',
        label: 'bag',
        amount: 454,
      );
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
        measureId: 'm-bag',
      );

      final prices = await repo.watchPrices('banana').first;
      expect(prices.single.packLabel, 'bag');
    });

    test('a price typed today is dated today', () async {
      final before = DateTime.now().toUtc();
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
      );
      final prices = await repo.watchPrices('banana').first;
      expect(
        prices.single.purchasedAt.isBefore(
          before.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test('the store word is trimmed, and an empty one is refused', () async {
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "  TJ's  ",
      );
      expect((await repo.watchStores().first).single, "TJ's");

      await expectLater(
        repo.recordManualPrice(
          ingredientId: 'banana',
          cents: 349,
          packBasisAmount: 454,
          store: '   ',
        ),
        throwsArgumentError,
      );
    });

    test(
      'the honesty rules hold at the repository, not just the sheet',
      () async {
        await expectLater(
          repo.recordManualPrice(
            ingredientId: 'banana',
            cents: 0,
            packBasisAmount: 454,
            store: "TJ's",
          ),
          throwsArgumentError,
          reason: 'a price is what was paid',
        );
        for (final pack in [0.0, -1.0, double.nan, double.infinity]) {
          await expectLater(
            repo.recordManualPrice(
              ingredientId: 'banana',
              cents: 349,
              packBasisAmount: pack,
              store: "TJ's",
            ),
            throwsArgumentError,
            reason: 'pack $pack',
          );
        }
        expect(await repo.watchPrices('banana').first, isEmpty);
      },
    );

    test('the pack is stored twice: as entered, and in the basis', () async {
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 453.59237,
        store: "TJ's",
        packAmount: 1,
        packUnitId: 'lb',
      );

      final prices = await repo.watchPrices('banana').first;
      expect(prices.single.packAmount, 1);
      expect(prices.single.packUnit, lb);
      expect(
        prices.single.packBasisAmount,
        closeTo(453.6, 0.1),
        reason: 'the derivation still reads the basis figure',
      );
      expect(
        formatPricePer100(prices.single.per100.valueOrNull!),
        '77¢ / 100 g',
      );
    });

    test('a measure pack keeps the COUNT and no unit', () async {
      await _seedMeasure(
        db,
        id: 'm-bag',
        ingredientId: 'banana',
        label: 'bag',
        amount: 454,
      );
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 698,
        packBasisAmount: 908,
        store: "TJ's",
        packAmount: 2,
        measureId: 'm-bag',
      );

      final prices = await repo.watchPrices('banana').first;
      expect(prices.single.packAmount, 2);
      expect(prices.single.packUnit, isNull);
      expect(prices.single.packLabel, 'bag');
    });

    test(
      'the write is two rows in one transaction, and a plain INSERT',
      () async {
        await drainCrudQueue(db);
        await repo.recordManualPrice(
          ingredientId: 'banana',
          cents: 349,
          packBasisAmount: 454,
          store: "TJ's",
        );
        final ops = await queuedCrudOps(db);
        expect(ops.map((o) => o['type']), ['receipt', 'receipt_line']);
        expect(ops.every((o) => o['op'] == 'PUT'), isTrue);
      },
    );
  });

  group('updatePrice', () {
    test(
      'rewrites the line, and its one-line manual receipt with it',
      () async {
        await repo.recordManualPrice(
          ingredientId: 'banana',
          cents: 349,
          packBasisAmount: 454,
          store: "TJ's",
          packAmount: 454,
          packUnitId: 'g',
          purchasedAt: DateTime.utc(2026, 9, 13),
        );
        final was = (await repo.watchPrices('banana').first).single;

        await repo.updatePrice(
          lineId: was.lineId,
          cents: 399,
          packBasisAmount: 453.59237,
          store: 'Whole Foods',
          purchasedAt: was.purchasedAt,
          packAmount: 1,
          packUnitId: 'lb',
        );

        final now = (await repo.watchPrices('banana').first).single;
        expect(now.lineId, was.lineId, reason: 'the same line, corrected');
        expect(now.cents, 399);
        expect(now.packAmount, 1);
        expect(now.packUnit, lb);
        expect(now.store, 'Whole Foods');
        expect(
          now.purchasedAt,
          DateTime.utc(2026, 9, 13),
          reason: 'an edit is a correction, not a second shop',
        );

        final receipt = await db.get('SELECT * FROM receipt');
        expect(receipt['store'], 'Whole Foods');
        expect(receipt['subtotal_cents'], 399);
      },
    );

    test('a photographed receipt keeps what the paper printed', () async {
      await _seedReceipt(
        db,
        id: 'r-photo',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r-photo');
      await _seedLine(db, id: 'l2', receiptId: 'r-photo', cents: 199);

      await repo.updatePrice(
        lineId: 'l1',
        cents: 399,
        packBasisAmount: 454,
        store: 'Somewhere Else',
        purchasedAt: DateTime.utc(2026),
      );

      final receipt = await db.get(
        "SELECT * FROM receipt WHERE id = 'r-photo'",
      );
      expect(receipt['store'], "TJ's");
      expect(receipt['purchased_at'], '2026-09-13T17:20:00Z');
      final line = await db.get("SELECT * FROM receipt_line WHERE id = 'l1'");
      expect(line['cents'], 399);
    });

    test('the honesty rules hold here too', () async {
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
      );
      final was = (await repo.watchPrices('banana').first).single;
      await expectLater(
        repo.updatePrice(
          lineId: was.lineId,
          cents: 0,
          packBasisAmount: 454,
          store: "TJ's",
          purchasedAt: was.purchasedAt,
        ),
        throwsArgumentError,
      );
      expect((await repo.watchPrices('banana').first).single.cents, 349);
    });

    test('the write is an UPDATE, never an upsert', () async {
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
      );
      final was = (await repo.watchPrices('banana').first).single;
      await drainCrudQueue(db);
      await repo.updatePrice(
        lineId: was.lineId,
        cents: 399,
        packBasisAmount: 454,
        store: "TJ's",
        purchasedAt: was.purchasedAt,
      );
      final ops = await queuedCrudOps(db);
      expect(ops.map((o) => o['op']).toSet(), {'PATCH'});
      expect(
        ops.map((o) => o['type']),
        containsAll(<String>['receipt_line', 'receipt']),
      );
    });
  });

  group('deletePrice', () {
    test('takes the line, and the one-line manual receipt behind it', () async {
      await repo.recordManualPrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
      );
      final was = (await repo.watchPrices('banana').first).single;

      await repo.deletePrice(was.lineId);

      expect(await repo.watchPrices('banana').first, isEmpty);
      final receipt = await db.get('SELECT * FROM receipt');
      expect(receipt['deleted_at'], isNotNull);
      expect(
        await repo.watchStores().first,
        isEmpty,
        reason: 'the store word went with the receipt that used it',
      );
    });

    test('a photographed receipt is never deleted from here', () async {
      await _seedReceipt(
        db,
        id: 'r-photo',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l1', receiptId: 'r-photo');
      await _seedLine(db, id: 'l2', receiptId: 'r-photo', cents: 199);

      await repo.deletePrice('l1');

      final receipt = await db.get(
        "SELECT * FROM receipt WHERE id = 'r-photo'",
      );
      expect(receipt['deleted_at'], isNull, reason: 'the paper stands');
      final lines = await db.getAll(
        'SELECT id FROM receipt_line WHERE deleted_at IS NULL',
      );
      expect(lines.map((r) => r['id']), ['l2']);
    });

    test('a deleted price leaves every derivation alone', () async {
      await _seedReceipt(
        db,
        id: 'r-aug',
        store: 'Whole Foods',
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-sep',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l-aug', receiptId: 'r-aug', cents: 399);
      await _seedLine(db, id: 'l-sep', receiptId: 'r-sep');

      await repo.deletePrice('l-sep');

      expect(
        (await repo.watchLatestPrices().first)['banana']!.lineId,
        'l-aug',
        reason: 'the latest is the latest LIVE line',
      );
      expect(
        (await loadLatestPrices(db))['banana']!.lineId,
        'l-aug',
        reason: 'the one-shot read every cost surface makes agrees',
      );
      expect((await repo.watchPrices('banana').first).map((p) => p.lineId), [
        'l-aug',
      ]);
    });
  });
}
