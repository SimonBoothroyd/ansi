/// [ReceiptRepository] over the local PowerSync SQLite (synced receipt rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../ingredients/domain/measure_authoring.dart';
import '../../ingredients/domain/price.dart';
import '../domain/receipt_repository.dart';
import '../domain/receipt_save.dart';

const _uuid = Uuid();

/// A measure minted by the save in flight, and the weight it was minted at.
typedef _Minted = ({String id, double basis});

class SqliteReceiptRepository implements ReceiptRepository {
  const SqliteReceiptRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;
  final String _householdId;

  /// The ledger list.
  ///
  /// The two counts and the lines' sum come from a LEFT JOIN and a GROUP BY
  /// rather than from correlated subqueries: the join is what puts
  /// `receipt_line` in the watch's trigger set, so a line saved on the other
  /// phone moves this list. SQLite drops a join nothing selects from, and the
  /// aggregates over `l` are that selection.
  ///
  /// The SELECT is spelled out in full rather than shared as a fragment —
  /// `watch_coverage_test` reads these queries as literals, and an
  /// interpolated string is invisible to it.
  @override
  Stream<List<ReceiptLedgerRow>> watchReceipts() {
    return _db
        .watch(
          'SELECT r.id, r.store, r.purchased_at, r.source, '
          'r.subtotal_cents, r.tax_cents, r.total_cents, '
          'COUNT(l.id) AS line_count, '
          "COUNT(CASE WHEN l.kind = 'not_food' THEN 1 END) AS not_food_count, "
          "COALESCE(SUM(CASE WHEN l.kind <> 'tax' "
          'THEN l.cents - COALESCE(l.discount_cents, 0) END), 0) AS lines_sum, '
          "COALESCE(SUM(CASE WHEN l.kind = 'tax' "
          'THEN l.cents - COALESCE(l.discount_cents, 0) END), 0) AS tax_sum '
          'FROM receipt r '
          'LEFT JOIN receipt_line l ON l.receipt_id = r.id '
          'AND l.deleted_at IS NULL '
          'WHERE r.deleted_at IS NULL '
          'GROUP BY r.id '
          'ORDER BY r.purchased_at DESC, r.created_at DESC, r.id DESC',
        )
        .map(
          (rows) => [
            for (final r in rows)
              (
                id: r['id'] as String,
                store: (r['store'] as String?) ?? '',
                purchasedAt: receiptInstant(r['purchased_at']),
                source: (r['source'] as String?) ?? 'photo',
                subtotalCents: (r['subtotal_cents'] as num?)?.toInt(),
                taxCents: (r['tax_cents'] as num?)?.toInt(),
                totalCents: (r['total_cents'] as num?)?.toInt(),
                lineCount: (r['line_count'] as num?)?.toInt() ?? 0,
                notFoodCount: (r['not_food_count'] as num?)?.toInt() ?? 0,
                linesSumCents: (r['lines_sum'] as num?)?.toInt() ?? 0,
                taxLinesCents: (r['tax_sum'] as num?)?.toInt() ?? 0,
              ),
          ],
        );
  }

  /// One receipt with its lines.
  ///
  /// Every joined table contributes a selected column, which is the LEFT-JOIN
  /// watch trap itself: SQLite drops a join nothing selects from, so an
  /// unselected `ingredient` would leave this page stale when a matched row
  /// was renamed under it.
  @override
  Stream<StoredReceipt?> watchReceipt(String receiptId) {
    return _db
        .watch(
          'SELECT r.id, r.store, r.purchased_at, r.source, '
          'r.subtotal_cents, r.tax_cents, r.total_cents, '
          'l.id AS line_id, l.ingredient_id, l.printed_text, l.name_printed, '
          'l.cents, '
          'l.discount_cents, l.count, l.kind, l.pack_basis_amount, '
          'l.pack_amount, '
          'l.pack_unit, l.measure_id, l.sort_order, '
          'i.canonical_name, m.label AS measure_label '
          'FROM receipt r '
          'LEFT JOIN receipt_line l ON l.receipt_id = r.id '
          'AND l.deleted_at IS NULL '
          'LEFT JOIN ingredient i ON i.id = l.ingredient_id '
          'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
          'AND m.deleted_at IS NULL '
          'WHERE r.id = ? AND r.deleted_at IS NULL '
          'ORDER BY l.sort_order, l.created_at, l.id',
          parameters: [receiptId],
        )
        .map(_receiptFrom);
  }

  static StoredReceipt? _receiptFrom(Iterable<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    final head = rows.first;
    return (
      id: head['id'] as String,
      store: (head['store'] as String?) ?? '',
      purchasedAt: receiptInstant(head['purchased_at']),
      source: (head['source'] as String?) ?? 'photo',
      subtotalCents: (head['subtotal_cents'] as num?)?.toInt(),
      taxCents: (head['tax_cents'] as num?)?.toInt(),
      totalCents: (head['total_cents'] as num?)?.toInt(),
      lines: [
        for (final r in rows)
          // A receipt with no live lines still answers, through the LEFT
          // JOIN's one all-null row — the paper stands, one line shorter.
          if (r['line_id'] != null)
            (
              id: r['line_id'] as String,
              ingredientId: r['ingredient_id'] as String?,
              ingredientName: r['canonical_name'] as String?,
              printedText: (r['printed_text'] as String?) ?? '',
              namePrinted: r['name_printed'] as String?,
              cents: (r['cents'] as num?)?.toInt() ?? 0,
              // A row synced before the column rang up one of the thing.
              count: (r['count'] as num?)?.toInt() ?? 1,
              discountCents: (r['discount_cents'] as num?)?.toInt() ?? 0,
              kind: (r['kind'] as String?) ?? 'item',
              packBasisAmount: (r['pack_basis_amount'] as num?)?.toDouble(),
              packAmount: (r['pack_amount'] as num?)?.toDouble(),
              packUnit: r['pack_unit'] as String?,
              measureId: r['measure_id'] as String?,
              measureLabel: r['measure_label'] as String?,
            ),
      ],
    );
  }

  @override
  Future<String> saveReceipt(ReceiptWrite write) async {
    _refuseUnsayable(write);
    final store = write.store.trim();

    final receiptId = _uuid.v4();
    final stamp = DateTime.now().toUtc().toIso8601String();
    final bought = receiptStamp(write.purchasedAt);

    await _db.writeTransaction((tx) async {
      // Plain INSERTs, never ON CONFLICT: the local tables are SQLite views
      // and a view rejects UPSERT.
      await tx.execute(
        'INSERT INTO receipt (id, household_id, store, purchased_at, '
        'subtotal_cents, tax_cents, total_cents, source, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          receiptId,
          _householdId,
          store,
          bought,
          write.subtotalCents,
          write.taxCents,
          write.totalCents,
          'photo',
          stamp,
          stamp,
        ],
      );
      final mintedWords = <(String, String), _Minted>{};
      for (final line in write.lines) {
        await _writeLine(tx, receiptId, line, stamp, mintedWords);
      }
    });
    return receiptId;
  }

  @override
  Future<void> updateReceipt(String receiptId, ReceiptWrite write) async {
    _refuseUnsayable(write);
    final stamp = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      final receipt = await tx.getOptional(
        'SELECT source FROM receipt WHERE id = ? AND deleted_at IS NULL',
        [receiptId],
      );
      // Deleted on another phone: there is nothing left to edit.
      if (receipt == null) return;
      // UPDATE, never an upsert: the local tables are SQLite views. Printed
      // totals are the paper's and stand; a hand-typed receipt printed none,
      // so its subtotal follows its lines.
      final manual =
          ReceiptSource.fromDb(receipt['source'] as String?) ==
          ReceiptSource.manual;
      await tx.execute(
        'UPDATE receipt SET store = ?, purchased_at = ?, '
        'subtotal_cents = COALESCE(?, subtotal_cents), updated_at = ? '
        'WHERE id = ?',
        [
          write.store.trim(),
          receiptStamp(write.purchasedAt),
          if (manual) _linesCents(write) else null,
          stamp,
          receiptId,
        ],
      );
      // Only a line the person dropped is tombstoned: one merely absent from
      // the write may not have synced to this phone yet.
      for (final id in write.droppedLineIds) {
        await tx.execute(
          'UPDATE receipt_line SET deleted_at = ?, updated_at = ? '
          'WHERE id = ? AND receipt_id = ? AND deleted_at IS NULL',
          [stamp, stamp, id, receiptId],
        );
      }
      final mintedWords = <(String, String), _Minted>{};
      for (final line in write.lines) {
        await _writeLine(tx, receiptId, line, stamp, mintedWords);
      }
    });
  }

  @override
  Future<void> deleteReceipt(String receiptId) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE receipt_line SET deleted_at = ?, updated_at = ? '
        'WHERE receipt_id = ? AND deleted_at IS NULL',
        [stamp, stamp, receiptId],
      );
      await tx.execute(
        'UPDATE receipt SET deleted_at = ?, updated_at = ? '
        'WHERE id = ? AND deleted_at IS NULL',
        [stamp, stamp, receiptId],
      );
    });
  }

  /// What [write]'s lines come to, tax excluded — the review's own sum.
  static int _linesCents(ReceiptWrite write) => write.lines
      .where((l) => l.kind != ReceiptLineKind.tax)
      .fold(0, (sum, l) => sum + l.cents - l.discountCents);

  static void _refuseUnsayable(ReceiptWrite write) {
    if (write.store.trim().isEmpty) {
      throw ArgumentError.value(write.store, 'store', 'must name a store');
    }
    if (write.lines.isEmpty) {
      throw ArgumentError.value(
        write.lines,
        'lines',
        'a receipt with no lines is not a receipt',
      );
    }
  }

  /// Writes one line of [receiptId] — an UPDATE where the line is already a
  /// row ([ReceiptLineWrite.lineId]), a plain INSERT where it is new. Never
  /// `ON CONFLICT`: the local tables are SQLite views and a view rejects
  /// UPSERT.
  ///
  /// [mintedWords] is what this save has already minted, keyed by ingredient
  /// and word, so six identical lines mint one measure. It lives for one
  /// transaction.
  Future<void> _writeLine(
    SqliteWriteContext tx,
    String receiptId,
    ReceiptLineWrite line,
    String stamp,
    Map<(String, String), _Minted> mintedWords,
  ) async {
    // The one place an import mints a measure, and only where the household's
    // own tap asked for it. It happens BEFORE the line, so the line can point
    // at the word rather than at the unit it was typed in.
    var measureId = line.measureId;
    final mint = line.mintMeasureLabel?.trim();
    final basis = line.packBasisAmount;
    final ingredientId = line.ingredientId;
    if (mint != null &&
        mint.isNotEmpty &&
        basis != null &&
        ingredientId != null) {
      final already = mintedWords[(ingredientId, mint)];
      if (already == null) {
        final last = await tx.get(
          'SELECT COALESCE(MAX(sort_order), -1) AS m FROM ingredient_measure '
          'WHERE ingredient_id = ? AND deleted_at IS NULL',
          [ingredientId],
        );
        measureId = _uuid.v4();
        mintedWords[(ingredientId, mint)] = (id: measureId, basis: basis);
        await tx.execute(
          'INSERT INTO ingredient_measure (id, household_id, '
          'ingredient_id, label, basis_amount, sort_order, source, '
          'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            measureId,
            _householdId,
            ingredientId,
            mint,
            basis,
            ((last['m'] as num?)?.toInt() ?? -1) + 1,
            'manual',
            stamp,
            stamp,
          ],
        );
      } else if (isSameMeasureWeight(basis, already.basis)) {
        measureId = already.id;
      }
      // A second size of the same word stays as typed: one word is one
      // weight, and the pack sheet is where that is refused out loud.
    }
    // A pack minted as a measure is stored as a COUNT of it, so the word is
    // the measure's own and never a second copy.
    final minted = measureId != null && measureId != line.measureId;
    // Only a food line is ever counted (0050), and it is held HERE as well as
    // in the mapping: a local table is a view with no CHECK behind it, so a
    // count on a bag fee would pass on the phone and stall the upload queue
    // against Postgres.
    final counted = line.kind == ReceiptLineKind.item && line.count >= 1
        ? line.count
        : 1;
    final said = [
      line.ingredientId,
      line.cents,
      counted,
      line.discountCents,
      line.kind.dbValue,
      line.packBasisAmount,
      if (minted) 1 else line.packAmount,
      if (minted) null else line.packUnitId,
      measureId,
      line.sortOrder,
    ];
    if (line.lineId case final id?) {
      // `printed_text` and `name_printed` are the PAPER's and no edit moves
      // them. The name is also what the receipt door recalls past answers by,
      // and a name that moved under an answer would file it somewhere nobody
      // asked about.
      //
      // The `IS NOT` tail is what makes a re-save of an unchanged line write
      // nothing at all: recall reads the newest `updated_at`, so re-stamping
      // a line nobody touched would make an old receipt's stale match the
      // latest answer — and it would queue an upload op saying nothing.
      await tx.execute(
        'UPDATE receipt_line SET ingredient_id = ?, cents = ?, count = ?, '
        'discount_cents = ?, kind = ?, pack_basis_amount = ?, '
        'pack_amount = ?, pack_unit = ?, measure_id = ?, sort_order = ?, '
        'updated_at = ? WHERE id = ? AND receipt_id = ? '
        'AND deleted_at IS NULL AND (ingredient_id IS NOT ? OR '
        'cents IS NOT ? OR count IS NOT ? OR discount_cents IS NOT ? OR '
        'kind IS NOT ? OR '
        'pack_basis_amount IS NOT ? OR pack_amount IS NOT ? OR '
        'pack_unit IS NOT ? OR measure_id IS NOT ? OR sort_order IS NOT ?)',
        [...said, stamp, id, receiptId, ...said],
      );
      return;
    }
    await tx.execute(
      'INSERT INTO receipt_line (id, household_id, receipt_id, '
      'printed_text, name_printed, ingredient_id, cents, count, '
      'discount_cents, kind, pack_basis_amount, pack_amount, pack_unit, '
      'measure_id, sort_order, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        _householdId,
        receiptId,
        line.printedText,
        line.namePrinted,
        ...said,
        stamp,
        stamp,
      ],
    );
  }
}
