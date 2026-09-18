/// [ReceiptRepository] over the local PowerSync SQLite (synced receipt rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../domain/receipt_repository.dart';
import '../domain/receipt_save.dart';

const _uuid = Uuid();

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
          'THEN l.cents - COALESCE(l.discount_cents, 0) END), 0) AS lines_sum '
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
          'l.id AS line_id, l.ingredient_id, l.printed_text, l.cents, '
          'l.discount_cents, l.kind, l.pack_basis_amount, l.pack_amount, '
          'l.pack_unit, l.measure_id, l.sort_order, '
          'i.canonical_name, i.macros_basis, m.label AS measure_label '
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
              cents: (r['cents'] as num?)?.toInt() ?? 0,
              discountCents: (r['discount_cents'] as num?)?.toInt() ?? 0,
              kind: (r['kind'] as String?) ?? 'item',
              packBasisAmount: (r['pack_basis_amount'] as num?)?.toDouble(),
              packAmount: (r['pack_amount'] as num?)?.toDouble(),
              packUnit: r['pack_unit'] as String?,
              measureId: r['measure_id'] as String?,
              measureLabel: r['measure_label'] as String?,
              macrosBasis: r['macros_basis'] as String?,
            ),
      ],
    );
  }

  @override
  Future<String> saveReceipt(ReceiptWrite write) async {
    final store = write.store.trim();
    if (store.isEmpty) {
      throw ArgumentError.value(write.store, 'store', 'must name a store');
    }
    if (write.lines.isEmpty) {
      throw ArgumentError.value(
        write.lines,
        'lines',
        'a receipt with no lines is not a receipt',
      );
    }

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
      for (final line in write.lines) {
        // The one place an import mints a measure, and only where the
        // household's own tap asked for it. It happens BEFORE the line, so
        // the line can point at the word rather than at the unit it was
        // typed in — which is what makes the next receipt for this row land
        // on it.
        var measureId = line.measureId;
        final mint = line.mintMeasureLabel?.trim();
        final basis = line.packBasisAmount;
        if (mint != null &&
            mint.isNotEmpty &&
            basis != null &&
            line.ingredientId != null) {
          final last = await tx.get(
            'SELECT COALESCE(MAX(sort_order), -1) AS m FROM ingredient_measure '
            'WHERE ingredient_id = ? AND deleted_at IS NULL',
            [line.ingredientId],
          );
          measureId = _uuid.v4();
          await tx.execute(
            'INSERT INTO ingredient_measure (id, household_id, '
            'ingredient_id, label, basis_amount, sort_order, source, '
            'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              measureId,
              _householdId,
              line.ingredientId,
              mint,
              basis,
              ((last['m'] as num?)?.toInt() ?? -1) + 1,
              'manual',
              stamp,
              stamp,
            ],
          );
        }
        // A pack minted as a measure is stored as a COUNT of it, so the word
        // is the measure's own and never a second copy.
        final minted = measureId != null && measureId != line.measureId;
        await tx.execute(
          'INSERT INTO receipt_line (id, household_id, receipt_id, '
          'ingredient_id, printed_text, cents, discount_cents, kind, '
          'pack_basis_amount, pack_amount, pack_unit, measure_id, '
          'sort_order, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            _uuid.v4(),
            _householdId,
            receiptId,
            line.ingredientId,
            line.printedText,
            line.cents,
            line.discountCents,
            line.kind.dbValue,
            line.packBasisAmount,
            if (minted) 1 else line.packAmount,
            if (minted) null else line.packUnitId,
            measureId,
            line.sortOrder,
            stamp,
            stamp,
          ],
        );
      }
    });
    return receiptId;
  }
}

/// A stored timestamp as an instant.
///
/// `purchased_at` is TEXT and its format differs by writer — this client
/// writes `…T…Z`, a Postgres-sourced row syncs as `… …Z` — and a value with
/// no zone marker at all is read as UTC, because `DateTime.tryParse` would
/// otherwise read it in the device's zone and two phones would date the same
/// shop differently. An unparseable value falls back to the epoch: it sorts
/// last, which is where a row nobody can date belongs.
/// [wall] as the column stores it — the receipt's **wall time**, marked `Z`.
///
/// A receipt's moment is the time at the till, and it has to read back as the
/// same day on every device: converting `17:42` on a phone seven hours west
/// of UTC would store `00:42` the next morning and file a Sunday shop into
/// Monday's week. So the wall components are written as they stand, and
/// [receiptInstant] reads them back unchanged. The zone the shop happened in
/// is not a fact this household needs; the date on the paper is.
String receiptStamp(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
  wall.second,
).toIso8601String();

DateTime receiptInstant(Object? raw) {
  final text = (raw as String? ?? '').trim();
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return DateTime.utc(1970);
  return parsed.isUtc
      ? parsed
      : DateTime.tryParse('${text}Z') ?? parsed.toUtc();
}
