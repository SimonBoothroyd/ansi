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
  int count = 1,
  int discountCents = 0,
  String kind = 'item',
  double? packBasisAmount = 454,
  double? packAmount,
  String? packUnit,
  String? measureId,
  String? namePrinted,
  String createdAt = '2026-01-01',
  String? updatedAt,
  String? deletedAt,
}) => db.execute(
  'INSERT INTO receipt_line (id, household_id, receipt_id, ingredient_id, '
  'name_printed, cents, count, discount_cents, kind, pack_basis_amount, '
  'pack_amount, pack_unit, measure_id, sort_order, created_at, updated_at, '
  'deleted_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
  [
    id,
    'h',
    receiptId,
    ingredientId,
    namePrinted,
    cents,
    count,
    discountCents,
    kind,
    packBasisAmount,
    packAmount,
    packUnit,
    measureId,
    createdAt,
    updatedAt ?? createdAt,
    deletedAt,
  ],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqlitePriceRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqlitePriceRepository(db);
    await _seedIngredient(db);
  });

  tearDown(() => closeTestDb(db, dir));

  group('packsByPrintedName — the pack a shop’s own words were bought in', () {
    const quinoa = 'ORG TRICOLOR QUINOA';
    const wf = 'ORGANIC TRI-COLOR QUINOA';

    /// Both shops' words for one row, each bought in the size that shop sells.
    Future<void> seedTwoShops() async {
      await _seedReceipt(
        db,
        id: 'r-tj',
        store: "TJ's",
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-wf',
        store: 'Whole Foods',
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(
        db,
        id: 'l-tj',
        receiptId: 'r-tj',
        namePrinted: quinoa,
        // The helper's default pack is the 454 g bag this shop sells.
        packAmount: 16,
        packUnit: 'oz',
      );
      await _seedLine(
        db,
        id: 'l-wf',
        receiptId: 'r-wf',
        namePrinted: wf,
        packBasisAmount: 340,
        packAmount: 12,
        packUnit: 'oz',
      );
    }

    test('each shop’s words keep their own size, in one read', () async {
      await seedTwoShops();

      final packs = await repo.packsByPrintedName({quinoa, wf});

      expect(packs.keys, unorderedEquals([quinoa, wf]));
      expect(packs[quinoa]!.pack.packBasisAmount, 454);
      expect(packs[quinoa]!.pack.packAmount, 16);
      expect(packs[quinoa]!.pack.packUnit, oz);
      expect(packs[wf]!.pack.packBasisAmount, 340);
      expect(
        packs[quinoa]!.ingredientId,
        'banana',
        reason: 'the row the words were bought AS rides with the pack',
      );
    });

    test('the key is trimmed and case-insensitive, both ways', () async {
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
        namePrinted: '  org tricolor quinoa ',
      );

      final packs = await repo.packsByPrintedName({' ORG Tricolor Quinoa  '});

      expect(packs.keys, [
        quinoa,
      ], reason: 'one spelling of the name, whichever side the case came from');
    });

    test('the latest shop wins, and a corrected line breaks the tie', () async {
      await _seedReceipt(
        db,
        id: 'r-aug',
        store: "TJ's",
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-sep',
        store: 'Whole Foods',
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l-aug', receiptId: 'r-aug', namePrinted: quinoa);
      // Two lines on the SAME shop: the one edited last is the answer, which
      // is how a receipt got wrong is put right.
      await _seedLine(
        db,
        id: 'l-sep-first',
        receiptId: 'r-sep',
        namePrinted: quinoa,
        packBasisAmount: 340,
        updatedAt: '2026-09-13T18:00:00Z',
      );
      await _seedLine(
        db,
        id: 'l-sep-fixed',
        receiptId: 'r-sep',
        namePrinted: quinoa,
        packBasisAmount: 907,
        updatedAt: '2026-09-14T09:00:00Z',
      );

      final packs = await repo.packsByPrintedName({quinoa});

      expect(packs[quinoa]!.pack.lineId, 'l-sep-fixed');
      expect(packs[quinoa]!.pack.packBasisAmount, 907);
    });

    test('a tombstone is no answer — neither line nor receipt', () async {
      await _seedReceipt(
        db,
        id: 'r-gone',
        store: 'Whole Foods',
        purchasedAt: '2026-09-13T17:20:00Z',
        deletedAt: '2026-09-14',
      );
      await _seedReceipt(
        db,
        id: 'r-live',
        store: "TJ's",
        purchasedAt: '2026-09-10T10:00:00Z',
      );
      await _seedLine(
        db,
        id: 'l-gone',
        receiptId: 'r-gone',
        namePrinted: quinoa,
        packBasisAmount: 340,
      );
      await _seedLine(
        db,
        id: 'l-dropped',
        receiptId: 'r-live',
        namePrinted: quinoa,
        packBasisAmount: 907,
        updatedAt: '2026-09-12T10:00:00Z',
        deletedAt: '2026-09-12',
      );
      await _seedLine(
        db,
        id: 'l-live',
        receiptId: 'r-live',
        namePrinted: quinoa,
      );

      final packs = await repo.packsByPrintedName({quinoa});

      expect(packs[quinoa]!.pack.lineId, 'l-live');
    });

    test('a line that states no pack is not a pack to carry', () async {
      await _seedReceipt(
        db,
        id: 'r1',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(
        db,
        id: 'l-no-pack',
        receiptId: 'r1',
        namePrinted: quinoa,
        packBasisAmount: null,
      );
      // Read off the paper but never priced: `observationFrom`'s own gate.
      await _seedLine(
        db,
        id: 'l-free',
        receiptId: 'r1',
        namePrinted: 'TJ SRIRACHA',
        cents: 0,
      );

      final packs = await repo.packsByPrintedName({quinoa, 'TJ SRIRACHA'});

      expect(packs, isEmpty);
    });

    test('words nobody has bought under are absent, never a zero', () async {
      await seedTwoShops();

      final packs = await repo.packsByPrintedName({'TJ ORG BANANAS'});

      expect(packs, isEmpty);
    });

    test('a receipt that named nothing asks nothing', () async {
      await seedTwoShops();

      expect(await repo.packsByPrintedName(const {}), isEmpty);
      expect(
        await repo.packsByPrintedName(const {'', '   '}),
        isEmpty,
        reason: 'a name that is only whitespace is not a key',
      );
    });
  });

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

    test(
      'every price reader divides by the count as well as the pack',
      () async {
        // The owner's tofu line: eight 1 lb blocks for $23.92. The pack column
        // says what ONE block is, so a reader that ignored the count would
        // print $5.27 / 100 g on every screen at once.
        await _seedReceipt(
          db,
          id: 'r-sep',
          store: "TJ's",
          purchasedAt: '2026-09-13T17:20:00Z',
        );
        await _seedLine(
          db,
          id: 'l-tofu',
          receiptId: 'r-sep',
          cents: 2392,
          count: 8,
          packBasisAmount: 453.59237,
          namePrinted: 'TOFU SPR FRM HGH PRTN OR',
        );

        for (final price in [
          (await repo.watchPrices('banana').first).single,
          (await repo.watchLatestPrices().first)['banana']!,
          (await repo.watchCostPrices().first)['banana']!,
          (await loadCostPrices(db))['banana']!,
          (await repo.packsByPrintedName({
            'TOFU SPR FRM HGH PRTN OR',
          })).values.single.pack,
        ]) {
          expect(price.count, 8);
          expect(formatPricePer100(price.per100.valueOrNull!), '66¢ / 100 g');
        }
      },
    );

    test('a line written before the column rang up one of the thing', () async {
      // Every stored row meant exactly this when it was stored.
      await _seedReceipt(
        db,
        id: 'r-old',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await db.execute(
        'INSERT INTO receipt_line (id, household_id, receipt_id, '
        'ingredient_id, cents, discount_cents, kind, pack_basis_amount, '
        'sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
        ['l-old', 'h', 'r-old', 'banana', 349, 0, 'item', 454, '2026-01-01'],
      );
      final price = (await repo.watchPrices('banana').first).single;
      expect(price.count, 1);
      expect(formatPricePer100(price.per100.valueOrNull!), '77¢ / 100 g');
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

  /// The row's own base price: set, read back, taken back — on the
  /// `ingredient` row, and never a receipt.
  group('the base price', () {
    test('is set on the row, and writes no receipt', () async {
      await drainCrudQueue(db);
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 453.59237,
        packAmount: 1,
        packUnitId: 'lb',
      );

      final base = (await repo.watchBasePrice('banana').first)!;
      expect(base.cents, 349);
      expect(base.packAmount, 1);
      expect(base.packUnit, lb);
      expect(formatPricePer100(base.per100.valueOrNull!), '77¢ / 100 g');
      expect(await db.getAll('SELECT id FROM receipt'), isEmpty);
      expect(await db.getAll('SELECT id FROM receipt_line'), isEmpty);
      // An UPDATE of the one row, never an upsert: the local tables are views.
      final ops = await queuedCrudOps(db);
      expect(ops.map((o) => (o['type'], o['op'])), [('ingredient', 'PATCH')]);
    });

    test('is dated by the wall day it was set on', () async {
      final today = DateTime.now();
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
      );
      final setAt = (await repo.watchBasePrice('banana').first)!.setAt;
      expect(
        (setAt.year, setAt.month, setAt.day),
        (today.year, today.month, today.day),
      );
    });

    test('a measure pack keeps the COUNT and the word', () async {
      await _seedMeasure(
        db,
        id: 'm-bag',
        ingredientId: 'banana',
        label: 'bag',
        amount: 454,
      );
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 698,
        packBasisAmount: 908,
        packAmount: 2,
        measureId: 'm-bag',
      );
      final base = (await repo.watchBasePrice('banana').first)!;
      expect(base.packAmount, 2);
      expect(base.packUnit, isNull);
      expect(base.packLabel, 'bag');
    });

    test('names its store, trimmed, and a blank one names none', () async {
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "  TJ's ",
      );
      expect((await repo.watchBasePrice('banana').first)!.store, "TJ's");
      expect(
        ((await repo.watchCostPrices().first)['banana']! as BasePrice).store,
        "TJ's",
      );

      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: '   ',
      );
      final row = await db.get(
        'SELECT base_price_store FROM ingredient WHERE id = ?',
        ['banana'],
      );
      expect(row['base_price_store'], isNull);
    });

    test('its store joins the household’s store words, once', () async {
      await _seedReceipt(
        db,
        id: 'r-aug',
        store: 'Whole Foods',
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedReceipt(
        db,
        id: 'r-jul',
        store: "TJ's",
        purchasedAt: '2026-07-02T10:00:00Z',
      );
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        store: "TJ's",
      );
      // Set today, so it is the most recent use of the word.
      expect(await repo.watchStores().first, ["TJ's", 'Whole Foods']);

      await repo.clearBasePrice('banana');
      expect(await repo.watchStores().first, ['Whole Foods', "TJ's"]);
    });

    test('a second one replaces the first', () async {
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
      );
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 399,
        packBasisAmount: 454,
      );
      expect((await repo.watchBasePrice('banana').first)!.cents, 399);
    });

    test('is cleared whole, and receipts stay', () async {
      await _seedReceipt(
        db,
        id: 'r-sep',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      await _seedLine(db, id: 'l-sep', receiptId: 'r-sep');
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 453.59237,
        packAmount: 1,
        packUnitId: 'lb',
      );

      await repo.clearBasePrice('banana');

      expect(await repo.watchBasePrice('banana').first, isNull);
      final row = await db.get(
        'SELECT base_price_cents, base_price_pack_basis_amount, '
        'base_price_pack_amount, base_price_pack_unit, base_price_measure_id, '
        'base_price_set_at, base_price_store FROM ingredient WHERE id = ?',
        ['banana'],
      );
      expect(row.values, everyElement(isNull));
      expect(await repo.watchPrices('banana').first, hasLength(1));
    });

    test(
      'the honesty rules hold at the repository, not just the sheet',
      () async {
        await expectLater(
          repo.setBasePrice(
            ingredientId: 'banana',
            cents: 0,
            packBasisAmount: 454,
          ),
          throwsArgumentError,
          reason: 'a price is what was paid',
        );
        for (final pack in [0.0, -1.0, double.nan, double.infinity]) {
          await expectLater(
            repo.setBasePrice(
              ingredientId: 'banana',
              cents: 349,
              packBasisAmount: pack,
            ),
            throwsArgumentError,
            reason: 'pack $pack',
          );
        }
        expect(await repo.watchBasePrice('banana').first, isNull);
      },
    );
  });

  /// What every cost reads: the newest price paid, else the base price. The
  /// watched map and the one-shot load are the same query and must agree.
  group('the price a cost reads', () {
    Future<Map<String, UnitPrice>> both() async {
      final watched = await repo.watchCostPrices().first;
      final loaded = await loadCostPrices(db);
      expect(
        {for (final e in loaded.entries) e.key: e.value.key},
        {for (final e in watched.entries) e.key: e.value.key},
        reason: 'the one-shot read every cost load makes agrees',
      );
      return watched;
    }

    test('a row with only a base price is priced by it', () async {
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
      );
      final price = (await both())['banana'];
      expect(price, isA<BasePrice>());
      expect(formatPricePer100(price!.per100.valueOrNull!), '77¢ / 100 g');
    });

    test('a price paid outranks the base price, however old', () async {
      await _seedReceipt(
        db,
        id: 'r-aug',
        store: 'Whole Foods',
        purchasedAt: '2026-08-02T10:00:00Z',
      );
      await _seedLine(db, id: 'l-aug', receiptId: 'r-aug', cents: 399);
      // Set today, after the receipt: still the stand-in.
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 100,
        packBasisAmount: 454,
      );
      final price = (await both())['banana'];
      expect(price, isA<PriceObservation>());
      expect(price!.key, 'l-aug');
    });

    test('the newest LIVE line wins, on a live receipt', () async {
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
        id: 'r-gone',
        store: "TJ's",
        purchasedAt: '2026-09-20T17:20:00Z',
        deletedAt: '2026-09-21T00:00:00Z',
      );
      await _seedLine(db, id: 'l-aug', receiptId: 'r-aug', cents: 399);
      await _seedLine(
        db,
        id: 'l-sep',
        receiptId: 'r-sep',
        deletedAt: '2026-09-14T00:00:00Z',
      );
      await _seedLine(db, id: 'l-gone', receiptId: 'r-gone', cents: 999);

      expect((await both())['banana']!.key, 'l-aug');
    });

    test('a receipt taken back hands the row to its base price', () async {
      await _seedReceipt(
        db,
        id: 'r-gone',
        store: "TJ's",
        purchasedAt: '2026-09-20T17:20:00Z',
        deletedAt: '2026-09-21T00:00:00Z',
      );
      await _seedLine(db, id: 'l-gone', receiptId: 'r-gone');
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
      );
      expect((await both())['banana'], isA<BasePrice>());
    });

    test('a row with neither is absent — unpriced, never a zero', () async {
      await _seedIngredient(db, id: 'apple');
      await _seedReceipt(
        db,
        id: 'r-sep',
        store: "TJ's",
        purchasedAt: '2026-09-13T17:20:00Z',
      );
      // A line that states no pack is not a price either.
      await _seedLine(
        db,
        id: 'l-nopack',
        receiptId: 'r-sep',
        ingredientId: 'apple',
        packBasisAmount: null,
      );
      expect(await both(), isEmpty);
    });

    test('a base price says its pack in its own words', () async {
      await _seedMeasure(
        db,
        id: 'm-bag',
        ingredientId: 'banana',
        label: 'bag',
        amount: 454,
      );
      await repo.setBasePrice(
        ingredientId: 'banana',
        cents: 349,
        packBasisAmount: 454,
        packAmount: 1,
        measureId: 'm-bag',
      );
      expect((await both())['banana']!.packLabel, 'bag');
    });

    test('a new base price reaches a watcher without a refresh', () async {
      final emissions = await twoEmissions(
        repo.watchCostPrices(),
        () => repo.setBasePrice(
          ingredientId: 'banana',
          cents: 349,
          packBasisAmount: 454,
        ),
      );
      expect(emissions.first, isEmpty);
      expect(emissions.last['banana'], isA<BasePrice>());
    });
  });

  /// The receipt door's memory read back — the `On receipts` fold.
  ///
  /// The load-bearing case is the first one: the household's own
  /// mis-transcription only becomes visible if two spellings that differ by
  /// more than case stay TWO entries, while one word in two cases folds into
  /// one. That is the whole reason the section exists, so it is pinned here
  /// rather than described anywhere.
  group('watchReceiptNames', () {
    setUp(() async {
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
        purchasedAt: '2026-09-19T17:20:00Z',
      );
    });

    test('one word in two cases is one name, spelled as the newest line '
        'spells it', () async {
      await _seedLine(
        db,
        id: 'l-aug',
        receiptId: 'r-aug',
        namePrinted: 'shelled edamame',
      );
      await _seedLine(
        db,
        id: 'l-sep',
        receiptId: 'r-sep',
        namePrinted: 'SHELLED EDAMAME',
      );

      final names = await repo.watchReceiptNames('banana').first;
      expect(names.single.namePrinted, 'SHELLED EDAMAME');
      expect(names.single.lineCount, 2);
      expect(names.single.stores, [
        "TJ's",
        'Whole Foods',
      ], reason: 'the store that printed it last is named first');
      expect(names.single.lastSeen, DateTime.utc(2026, 9, 19, 17, 20));
      expect(
        names.single.receiptId,
        'r-sep',
        reason: 'a correction is made on the newest receipt carrying it',
      );
    });

    test(
      'a mis-transcription stays its own name — that is the point',
      () async {
        await _seedLine(
          db,
          id: 'l-aug',
          receiptId: 'r-aug',
          namePrinted: 'SHELLED EDAMAME',
        );
        await _seedLine(
          db,
          id: 'l-sep',
          receiptId: 'r-sep',
          namePrinted: 'SHELLER EDAMAME',
        );

        final names = await repo.watchReceiptNames('banana').first;
        expect(names.map((n) => n.namePrinted), [
          'SHELLER EDAMAME',
          'SHELLED EDAMAME',
        ], reason: 'newest first, so the answer that is live now leads');
        expect(names.map((n) => n.lineCount), [1, 1]);
      },
    );

    test('surrounding whitespace does not make a second name', () async {
      await _seedLine(
        db,
        id: 'l-aug',
        receiptId: 'r-aug',
        namePrinted: '  TJ ORG BANANAS ',
      );
      await _seedLine(
        db,
        id: 'l-sep',
        receiptId: 'r-sep',
        namePrinted: 'TJ ORG BANANAS',
      );

      final names = await repo.watchReceiptNames('banana').first;
      expect(names.single.namePrinted, 'TJ ORG BANANAS');
      expect(names.single.lineCount, 2);
    });

    test('a line with no printed words is not a name', () async {
      await _seedLine(db, id: 'l-typed', receiptId: 'r-sep');
      await _seedLine(
        db,
        id: 'l-blank',
        receiptId: 'r-aug',
        namePrinted: '   ',
      );

      expect(await repo.watchReceiptNames('banana').first, isEmpty);
    });

    test('a tombstoned line is not on the receipt any more', () async {
      await _seedLine(
        db,
        id: 'l-gone',
        receiptId: 'r-sep',
        namePrinted: 'SHELLER EDAMAME',
        deletedAt: '2026-09-19T18:00:00Z',
      );
      await _seedLine(
        db,
        id: 'l-live',
        receiptId: 'r-sep',
        namePrinted: 'SHELLED EDAMAME',
      );

      final names = await repo.watchReceiptNames('banana').first;
      expect(names.map((n) => n.namePrinted), ['SHELLED EDAMAME']);
    });

    test('a receipt taken back takes its names with it', () async {
      await _seedReceipt(
        db,
        id: 'r-gone',
        store: 'Safeway',
        purchasedAt: '2026-09-01T10:00:00Z',
        deletedAt: '2026-09-02T10:00:00Z',
      );
      await _seedLine(
        db,
        id: 'l-gone',
        receiptId: 'r-gone',
        namePrinted: 'SHELLER EDAMAME',
      );
      await _seedLine(
        db,
        id: 'l-live',
        receiptId: 'r-sep',
        namePrinted: 'SHELLED EDAMAME',
      );

      final names = await repo.watchReceiptNames('banana').first;
      expect(names.map((n) => n.namePrinted), ['SHELLED EDAMAME']);
    });

    test('only this row is asked about', () async {
      await _seedIngredient(db, id: 'quinoa');
      await _seedLine(
        db,
        id: 'l-banana',
        receiptId: 'r-sep',
        namePrinted: 'TJ ORG BANANAS',
      );
      await _seedLine(
        db,
        id: 'l-quinoa',
        receiptId: 'r-sep',
        ingredientId: 'quinoa',
        namePrinted: 'ORG TRICOLOR QUINOA',
      );

      expect(
        (await repo.watchReceiptNames('banana').first).map(
          (n) => n.namePrinted,
        ),
        ['TJ ORG BANANAS'],
      );
      expect(
        (await repo.watchReceiptNames('quinoa').first).map(
          (n) => n.namePrinted,
        ),
        ['ORG TRICOLOR QUINOA'],
      );
    });

    test(
      'a receipt nobody named the shop of contributes no store word',
      () async {
        await _seedReceipt(
          db,
          id: 'r-blank',
          store: '  ',
          purchasedAt: '2026-09-20T10:00:00Z',
        );
        await _seedLine(
          db,
          id: 'l-blank',
          receiptId: 'r-blank',
          namePrinted: 'TJ ORG BANANAS',
        );

        final names = await repo.watchReceiptNames('banana').first;
        expect(
          names.single.stores,
          isEmpty,
          reason: 'a blank word is not a shop, and it is not printed as one',
        );
      },
    );

    /// Re-matching a line is what corrects the memory, so the watch follows it.
    test(
      're-matching a line to another row moves the name off this one',
      () async {
        await _seedIngredient(db, id: 'quinoa');
        await _seedLine(
          db,
          id: 'l-sep',
          receiptId: 'r-sep',
          namePrinted: 'ORG TRICOLOR QUINOA',
        );

        final seen = await twoEmissions(
          repo.watchReceiptNames('banana'),
          () => db.execute(
            'UPDATE receipt_line SET ingredient_id = ? WHERE id = ?',
            ['quinoa', 'l-sep'],
          ),
        );
        expect(seen.first.map((n) => n.namePrinted), ['ORG TRICOLOR QUINOA']);
        expect(
          seen.last,
          isEmpty,
          reason: 'the answer moved, so the name is no longer filed here',
        );
        expect(
          (await repo.watchReceiptNames('quinoa').first).map(
            (n) => n.namePrinted,
          ),
          ['ORG TRICOLOR QUINOA'],
          reason: 'it is filed under the row somebody actually meant',
        );
      },
    );
  });
}
