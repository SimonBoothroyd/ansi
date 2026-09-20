/// The receipt repository against a REAL [PowerSyncDatabase].
///
/// Local tables are SQLite **views**, so this is where a write that a
/// hand-rolled table would accept fails the way the phone does — and where
/// the two reads the ledger makes are held against rows the app actually
/// wrote.
library;

import 'dart:io';

import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/receipts/data/receipt_providers.dart';
import 'package:ansi/features/receipts/data/receipt_repository_impl.dart';
import 'package:ansi/features/receipts/domain/receipt_save.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
  String? namePrinted = 'TJ ORG BANANAS',
  int cents = 349,
  int discountCents = 0,
  ReceiptLineKind kind = ReceiptLineKind.item,
  String? ingredientId = 'banana',
  double? packBasis = 454,
  double? packAmount = 1,
  String? packUnitId = 'lb',
  String? measureId,
  String? mint,
  String? lineId,
}) => ReceiptLineWrite(
  lineId: lineId,
  sortOrder: sortOrder,
  printedText: printed,
  namePrinted: namePrinted,
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

    test('the same word on six lines mints ONE measure', () async {
      // Six tubs of tofu, each kept as *tub*, is one word the household can
      // say — not six rows of the same word in the row's picker.
      final id = await repo.saveReceipt(
        write([
          line(
            printed: 'TJ ORG TOFU FIRM  2.49',
            cents: 249,
            packBasis: 396,
            packAmount: 396,
            packUnitId: 'g',
            mint: 'tub',
          ),
          line(
            sortOrder: 1,
            printed: 'TJ ORG TOFU FIRM  2.49',
            cents: 249,
            packBasis: 396,
            packAmount: 396,
            packUnitId: 'g',
            mint: 'tub',
          ),
        ]),
      );

      final measures = await db.getAll(
        'SELECT id FROM ingredient_measure WHERE ingredient_id = ?',
        ['banana'],
      );
      expect(measures, hasLength(1));
      final lines = await db.getAll(
        'SELECT * FROM receipt_line WHERE receipt_id = ? ORDER BY sort_order',
        [id],
      );
      expect(lines, hasLength(2));
      for (final stored in lines) {
        expect(stored['measure_id'], measures.single['id']);
        expect(
          stored['pack_amount'],
          1,
          reason: 'each line is a COUNT of the one word',
        );
        expect(stored['pack_unit'], isNull);
        expect(stored['pack_basis_amount'], 396);
      }
    });

    test('a second size of a word minted here stays as typed', () async {
      final id = await repo.saveReceipt(
        write([
          line(packAmount: 454, packUnitId: 'g', mint: 'bag'),
          line(
            sortOrder: 1,
            packBasis: 907,
            packAmount: 907,
            packUnitId: 'g',
            mint: 'bag',
          ),
        ]),
      );
      final measures = await db.getAll(
        'SELECT id, basis_amount FROM ingredient_measure',
      );
      expect(measures.single['basis_amount'], 454);
      final big = await db.get(
        'SELECT measure_id, pack_amount, pack_unit FROM receipt_line '
        'WHERE receipt_id = ? AND sort_order = 1',
        [id],
      );
      expect(big['measure_id'], isNull, reason: 'a bag is not two weights');
      expect(big['pack_amount'], 907);
      expect(big['pack_unit'], 'g');
    });

    test('two different words on one receipt are two measures', () async {
      await repo.saveReceipt(
        write([line(mint: 'tub'), line(sortOrder: 1, mint: 'bag')]),
      );
      final labels = await db.getAll(
        'SELECT label, sort_order FROM ingredient_measure '
        'ORDER BY sort_order',
      );
      expect(labels.map((r) => r['label']), ['tub', 'bag']);
      expect(labels.map((r) => r['sort_order']), [0, 1]);
    });

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

    test('the paper’s name for the thing is written with the line', () async {
      // It is what the receipt door recalls this household's own past answers
      // by, so a line saved without it is a line the next receipt cannot
      // learn from.
      final id = await repo.saveReceipt(write([line()]));
      final stored = await db.get(
        'SELECT name_printed FROM receipt_line WHERE receipt_id = ?',
        [id],
      );
      expect(stored['name_printed'], 'TJ ORG BANANAS');
      expect(
        (await repo.watchReceipt(id).first)!.lines.single.namePrinted,
        'TJ ORG BANANAS',
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

  group('a saved receipt, edited', () {
    test('kept lines update in place, a new one lands, a dropped one '
        'is tombstoned', () async {
      final id = await repo.saveReceipt(
        write([
          line(),
          line(sortOrder: 1),
          line(
            sortOrder: 2,
            printed: 'PAPER TOWELS  6.99',
            cents: 699,
            kind: ReceiptLineKind.notFood,
            ingredientId: null,
            packBasis: null,
            packAmount: null,
            packUnitId: null,
          ),
        ]),
      );
      final before = (await repo.watchReceipt(id).first)!;
      final [first, second, towels] = before.lines;

      await repo.updateReceipt(
        id,
        ReceiptWrite(
          store: 'Whole Foods',
          purchasedAt: DateTime(2026, 9, 12, 16, 13),
          lines: [
            // The figure was misread: same row, new cents.
            line(lineId: first.id, cents: 399),
            line(
              lineId: towels.id,
              sortOrder: 1,
              printed: 'ignored — the paper’s words never move',
              cents: 699,
              kind: ReceiptLineKind.notFood,
              ingredientId: null,
              packBasis: null,
              packAmount: null,
              packUnitId: null,
            ),
            line(sortOrder: 2, printed: '4 @ 0.49', cents: 196),
          ],
          droppedLineIds: [second.id],
        ),
      );

      final after = (await repo.watchReceipt(id).first)!;
      expect(after.store, 'Whole Foods');
      expect(after.purchasedAt, DateTime.utc(2026, 9, 12, 16, 13));
      expect(after.subtotalCents, 2846, reason: 'the printed totals stand');
      expect(after.lines.map((l) => l.id).take(2), [first.id, towels.id]);
      expect(after.lines.map((l) => l.cents), [399, 699, 196]);
      expect(after.lines[1].printedText, 'PAPER TOWELS  6.99');
      expect(after.lines.map((l) => l.id), isNot(contains(second.id)));
      final gone = await db.get(
        'SELECT deleted_at FROM receipt_line WHERE id = ?',
        [second.id],
      );
      expect(gone['deleted_at'], isNotNull, reason: 'a tombstone, not a hole');
    });

    test('the paper’s words never move, name and all', () async {
      final id = await repo.saveReceipt(write([line()]));
      final was = (await repo.watchReceipt(id).first)!.lines.single;
      await repo.updateReceipt(
        id,
        write([
          line(
            lineId: was.id,
            printed: 'ignored',
            namePrinted: 'ALSO IGNORED',
            cents: 399,
          ),
        ]),
      );
      final now = (await repo.watchReceipt(id).first)!.lines.single;
      expect(now.cents, 399, reason: 'the figure is a person’s to correct');
      expect(now.printedText, 'TJ ORG BANANAS  3.49');
      expect(
        now.namePrinted,
        'TJ ORG BANANAS',
        reason: 'a name that moved under an answer would refile it',
      );
    });

    test('a line nobody changed is not re-stamped', () async {
      // Recall reads the NEWEST answer by `updated_at`, so re-saving an old
      // receipt for its date must not make its stale matches the latest word.
      final id = await repo.saveReceipt(write([line(), line(sortOrder: 1)]));
      final [first, second] = (await repo.watchReceipt(id).first)!.lines;
      final was = await db.getAll(
        'SELECT id, updated_at FROM receipt_line WHERE receipt_id = ?',
        [id],
      );
      final stamps = {
        for (final r in was) r['id'] as String: r['updated_at'] as String,
      };
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await repo.updateReceipt(
        id,
        write([
          line(lineId: first.id),
          line(lineId: second.id, sortOrder: 1, cents: 399),
        ]),
      );

      final now = await db.getAll(
        'SELECT id, updated_at FROM receipt_line WHERE receipt_id = ?',
        [id],
      );
      final moved = {
        for (final r in now) r['id'] as String: r['updated_at'] as String,
      };
      expect(moved[first.id], stamps[first.id], reason: 'nothing changed');
      expect(
        moved[second.id],
        isNot(stamps[second.id]),
        reason: 'the figure moved, so the answer is new',
      );
    });

    test('a line the edit never saw is left standing', () async {
      // A second phone can open a receipt before every line has synced.
      final id = await repo.saveReceipt(write([line(), line(sortOrder: 1)]));
      final [first, second] = (await repo.watchReceipt(id).first)!.lines;

      await repo.updateReceipt(id, write([line(lineId: first.id)]));

      final after = (await repo.watchReceipt(id).first)!;
      expect(after.lines.map((l) => l.id), [first.id, second.id]);
    });

    test('an edit of a receipt deleted elsewhere writes nothing', () async {
      final id = await repo.saveReceipt(write([line()]));
      await repo.deleteReceipt(id);

      await repo.updateReceipt(id, write([line(printed: 'NEW  1.00')]));

      final live = await db.getAll(
        'SELECT id FROM receipt_line WHERE receipt_id = ? '
        'AND deleted_at IS NULL',
        [id],
      );
      expect(live, isEmpty);
    });

    test('a hand-typed receipt’s subtotal follows its line', () async {
      final id = await repo.saveReceipt(write([line()]));
      await db.execute(
        "UPDATE receipt SET source = 'manual', subtotal_cents = 349, "
        'tax_cents = NULL, total_cents = NULL WHERE id = ?',
        [id],
      );
      final [only] = (await repo.watchReceipt(id).first)!.lines;

      await repo.updateReceipt(
        id,
        write([line(lineId: only.id, cents: 449, discountCents: 50)]),
      );

      final after = (await repo.watchReceipt(id).first)!;
      expect(after.subtotalCents, 399, reason: 'no paper printed the old one');
    });

    test('an edit refuses what a save refuses', () async {
      final id = await repo.saveReceipt(write([line()]));
      expect(
        () => repo.updateReceipt(id, write(const [])),
        throwsArgumentError,
      );
    });

    test('a deleted receipt leaves both reads, lines and all', () async {
      final id = await repo.saveReceipt(write([line(), line(sortOrder: 1)]));
      await repo.deleteReceipt(id);
      expect(await repo.watchReceipt(id).first, isNull);
      expect(await repo.watchReceipts().first, isEmpty);
      final live = await db.getAll(
        'SELECT id FROM receipt_line WHERE receipt_id = ? '
        'AND deleted_at IS NULL',
        [id],
      );
      expect(live, isEmpty, reason: 'no line is left stating a price');
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
      expect(row.taxLinesCents, 82);
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

    test('a tax that is only a line is in the ledger’s total too', () async {
      // The review's Save bar adds it; the ledger must say the same figure.
      await repo.saveReceipt(
        ReceiptWrite(
          store: "TJ's",
          purchasedAt: DateTime(2026, 9, 13),
          lines: [
            line(),
            line(
              sortOrder: 1,
              cents: 82,
              kind: ReceiptLineKind.tax,
              ingredientId: null,
              packBasis: null,
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [receiptRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(receiptSummariesProvider, (_, _) {});
      addTearDown(sub.close);
      while (!container.read(receiptSummariesProvider).hasValue) {
        await Future<void>.delayed(Duration.zero);
      }
      final ledger = container.read(receiptSummariesProvider).requireValue;
      expect(ledger.single.totalCents, 349 + 82);
    });

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
