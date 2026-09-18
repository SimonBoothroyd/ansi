/// The receipt repository against a REAL [PowerSyncDatabase].
///
/// Local tables are SQLite **views**, so this is where a write that a
/// hand-rolled table would accept fails the way the phone does — and where
/// the two reads the ledger makes are held against rows the app actually
/// wrote.
library;

import 'dart:io';

import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/receipts/data/receipt_repository_impl.dart';
import 'package:ansi/features/receipts/domain/receipt_save.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _seedIngredient(
  PowerSyncDatabase db, {
  String id = 'banana',
  String name = 'Bananas, organic',
  String basis = 'g',
}) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
  'macros_basis) VALUES (?, ?, ?, ?, ?)',
  [id, 'h', name, 'piece', basis],
);

ReceiptLineWrite line({
  int sortOrder = 0,
  String printed = 'TJ ORG BANANAS  3.49',
  int cents = 349,
  int discountCents = 0,
  ReceiptLineKind kind = ReceiptLineKind.item,
  String? ingredientId = 'banana',
  double? packBasis = 454,
  double? packAmount = 1,
  String? packUnitId = 'lb',
  String? measureId,
  String? mint,
}) => ReceiptLineWrite(
  sortOrder: sortOrder,
  printedText: printed,
  cents: cents,
  discountCents: discountCents,
  kind: kind,
  ingredientId: ingredientId,
  packBasisAmount: packBasis,
  packAmount: packAmount,
  packUnitId: packUnitId,
  measureId: measureId,
  mintMeasureLabel: mint,
);

ReceiptWrite write(List<ReceiptLineWrite> lines, {DateTime? on}) =>
    ReceiptWrite(
      store: "TJ's",
      purchasedAt: on ?? DateTime(2026, 9, 13, 17, 42),
      subtotalCents: 2846,
      taxCents: 82,
      totalCents: 2928,
      lines: lines,
    );

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteReceiptRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteReceiptRepository(db, householdId: 'h');
    await _seedIngredient(db);
  });

  tearDown(() => closeTestDb(db, dir));

  group('saveReceipt', () {
    test('writes one receipt and every line, in plain INSERTs', () async {
      final id = await repo.saveReceipt(
        write([
          line(),
          line(
            sortOrder: 1,
            printed: 'PAPER TOWELS  6.99',
            cents: 699,
            kind: ReceiptLineKind.notFood,
            ingredientId: null,
            packBasis: null,
            packAmount: null,
            packUnitId: null,
          ),
          line(
            sortOrder: 2,
            printed: 'TAX  0.82',
            cents: 82,
            kind: ReceiptLineKind.tax,
            ingredientId: null,
            packBasis: null,
            packAmount: null,
            packUnitId: null,
          ),
        ]),
      );

      final receipt = await db.get('SELECT * FROM receipt WHERE id = ?', [id]);
      expect(receipt['store'], "TJ's");
      expect(receipt['source'], 'photo');
      expect(receipt['subtotal_cents'], 2846);
      expect(receipt['tax_cents'], 82);
      expect(receipt['total_cents'], 2928);
      final lines = await db.getAll(
        'SELECT * FROM receipt_line WHERE receipt_id = ? ORDER BY sort_order',
        [id],
      );
      expect(lines, hasLength(3));
      expect(lines.map((r) => r['kind']), ['item', 'not_food', 'tax']);
      expect(lines.first['pack_basis_amount'], 454);
      expect(lines.first['pack_unit'], 'lb');
    });

    test('the receipt keeps its WALL time, so no phone moves a day', () async {
      // 17:42 at the till reads back as 17:42, whatever zone the device is in;
      // converting it would file a late Sunday shop into Monday's week.
      final id = await repo.saveReceipt(write([line()]));
      final stored = await db.get(
        'SELECT purchased_at FROM receipt WHERE id = ?',
        [id],
      );
      expect(stored['purchased_at'], '2026-09-13T17:42:00.000Z');
      final read = receiptInstant(stored['purchased_at']);
      expect(read.year, 2026);
      expect(read.month, 9);
      expect(read.day, 13);
      expect(read.hour, 17);
    });

    test(
      'keep as a measure mints the word and points the line at it',
      () async {
        // The ONE place an import mints a measure, and only where the
        // household's own tap asked for it.
        final id = await repo.saveReceipt(
          write([
            line(
              printed: 'TJ SRIRACHA  3.99',
              cents: 399,
              packBasis: 482,
              packAmount: 482,
              packUnitId: 'g',
              mint: 'bottle',
            ),
          ]),
        );
        final measure = await db.get(
          'SELECT * FROM ingredient_measure WHERE ingredient_id = ?',
          ['banana'],
        );
        expect(measure['label'], 'bottle');
        expect(measure['basis_amount'], 482);
        expect(measure['source'], 'manual');
        expect(measure['sort_order'], 0);

        final stored = await db.get(
          'SELECT * FROM receipt_line WHERE receipt_id = ?',
          [id],
        );
        expect(stored['measure_id'], measure['id']);
        expect(
          stored['pack_amount'],
          1,
          reason: 'a pack named as a measure is stored as a COUNT of it',
        );
        expect(
          stored['pack_unit'],
          isNull,
          reason: 'the measure’s label is the word; a second copy would drift',
        );
        expect(
          stored['pack_basis_amount'],
          482,
          reason: 'the figure every price is derived from is unchanged',
        );
      },
    );

    test('a minted measure sits after the ones the row already had', () async {
      await db.execute(
        'INSERT INTO ingredient_measure (id, household_id, ingredient_id, '
        'label, basis_amount, sort_order) VALUES (?, ?, ?, ?, ?, ?)',
        ['m-0', 'h', 'banana', 'bunch', 900, 0],
      );
      await repo.saveReceipt(write([line(mint: 'bag')]));
      final minted = await db.get(
        "SELECT sort_order FROM ingredient_measure WHERE label = 'bag'",
      );
      expect(minted['sort_order'], 1);
    });

    test('no mint asked for, no measure written', () async {
      await repo.saveReceipt(write([line()]));
      expect(
        await db.getAll('SELECT id FROM ingredient_measure'),
        isEmpty,
        reason: 'the pipeline mints nothing; only a tap does',
      );
    });

    test('an empty store and a lineless receipt are both refused', () async {
      expect(
        () => repo.saveReceipt(
          ReceiptWrite(
            store: '   ',
            purchasedAt: DateTime(2026, 9, 13),
            lines: [line()],
          ),
        ),
        throwsArgumentError,
      );
      expect(() => repo.saveReceipt(write(const [])), throwsArgumentError);
    });
  });

  group('the two reads', () {
    test('the ledger row counts its lines and sums them without tax', () async {
      await repo.saveReceipt(
        write([
          line(),
          line(
            sortOrder: 1,
            cents: 699,
            kind: ReceiptLineKind.notFood,
            ingredientId: null,
            packBasis: null,
          ),
          line(
            sortOrder: 2,
            cents: 82,
            kind: ReceiptLineKind.tax,
            ingredientId: null,
            packBasis: null,
          ),
        ]),
      );
      final row = (await repo.watchReceipts().first).single;
      expect(row.store, "TJ's");
      expect(row.lineCount, 3);
      expect(row.notFoodCount, 1);
      expect(row.linesSumCents, 349 + 699, reason: 'tax is not in the lines');
      expect(row.totalCents, 2928);
    });

    test(
      'newest first, and a tombstoned receipt is not there at all',
      () async {
        await repo.saveReceipt(write([line()], on: DateTime(2026, 9, 6)));
        final newer = await repo.saveReceipt(
          write([line()], on: DateTime(2026, 9, 13)),
        );
        final gone = await repo.saveReceipt(
          write([line()], on: DateTime(2026, 9, 20)),
        );
        await db.execute('UPDATE receipt SET deleted_at = ? WHERE id = ?', [
          '2026-09-21',
          gone,
        ]);
        final rows = await repo.watchReceipts().first;
        expect(rows.map((r) => r.id).first, newer);
        expect(rows, hasLength(2));
      },
    );

    test('one receipt reads back with its lines and their words', () async {
      final id = await repo.saveReceipt(
        write([line(), line(sortOrder: 1, cents: 263)]),
      );
      final stored = (await repo.watchReceipt(id).first)!;
      expect(stored.store, "TJ's");
      expect(stored.source, 'photo');
      expect(stored.lines, hasLength(2));
      expect(
        stored.lines.first.ingredientName,
        'Bananas, organic',
        reason: 'the join names the row, rather than a copy on the line',
      );
      expect(stored.lines.first.macrosBasis, 'g');
      expect(stored.lines.map((l) => l.cents), [349, 263]);
    });

    test(
      'a deleted line leaves the paper standing, one line shorter',
      () async {
        final id = await repo.saveReceipt(
          write([line(), line(sortOrder: 1, cents: 263)]),
        );
        await db.execute(
          'UPDATE receipt_line SET deleted_at = ? '
          'WHERE receipt_id = ? AND sort_order = 1',
          ['2026-09-14', id],
        );
        final stored = (await repo.watchReceipt(id).first)!;
        expect(stored.lines, hasLength(1));
        expect(
          stored.totalCents,
          2928,
          reason: 'the printed total is the paper’s',
        );
      },
    );

    test('an id that names nothing is gone, not an error', () async {
      expect(await repo.watchReceipt('nope').first, isNull);
    });

    test('a pack named as a measure reads back with its word', () async {
      final id = await repo.saveReceipt(write([line(mint: 'bag')]));
      final stored = (await repo.watchReceipt(id).first)!;
      expect(stored.lines.single.measureLabel, 'bag');
      expect(stored.lines.single.packAmount, 1);
    });
  });

  test('every write leaves an upload op — nothing is local-only', () async {
    await repo.saveReceipt(write([line(mint: 'bag')]));
    final ops = await queuedCrudOps(db);
    expect(ops.map((o) => o['op']).toSet(), {'PUT'});
    expect(
      ops.map((o) => o['type']).toSet(),
      containsAll(<String>['receipt', 'receipt_line', 'ingredient_measure']),
    );
  });
}
