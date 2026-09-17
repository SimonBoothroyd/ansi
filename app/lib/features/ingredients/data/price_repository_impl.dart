/// [PriceRepository] over the local PowerSync SQLite (synced receipt rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../domain/price.dart';
import '../domain/price_repository.dart';

const _uuid = Uuid();

class SqlitePriceRepository implements PriceRepository {
  const SqlitePriceRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  /// One row of the price read, turned into the fact it states — or dropped.
  ///
  /// [observationFrom] is the one place that decides what IS a price, so a
  /// line whose pack nobody has stated and a line whose ingredient was retired
  /// out from under it fall out here rather than being rendered as a zero
  /// somewhere downstream (invariant 3).
  static List<PriceObservation> _observations(
    Iterable<Map<String, dynamic>> rows,
  ) => [
    for (final r in rows)
      if (_observationFromRow(r) case final observation?) observation,
  ];

  static PriceObservation? _observationFromRow(Map<String, dynamic> r) =>
      observationFrom(
        ReceiptLine(
          id: r['id'] as String,
          receiptId: r['receipt_id'] as String,
          ingredientId: r['ingredient_id'] as String?,
          printedText: r['printed_text'] as String?,
          cents: (r['cents'] as num).toInt(),
          discountCents: (r['discount_cents'] as num?)?.toInt() ?? 0,
          kind: ReceiptLineKind.fromDb(r['kind'] as String?),
          packBasisAmount: (r['pack_basis_amount'] as num?)?.toDouble(),
          measureId: r['measure_id'] as String?,
          sortOrder: (r['sort_order'] as int?) ?? 0,
        ),
        Receipt(
          id: r['receipt_id'] as String,
          store: (r['store'] as String?) ?? '',
          purchasedAt: _instant(r['purchased_at']),
          source: ReceiptSource.fromDb(r['source'] as String?),
        ),
        basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
        packLabel: r['measure_label'] as String?,
      );

  /// A stored timestamp as an instant. `purchased_at` is TEXT and its format
  /// differs by writer — this client writes `…T…Z`, a Postgres-sourced row
  /// syncs as `… …Z` — and a value with no zone marker at all is read as UTC,
  /// because `DateTime.tryParse` would otherwise read it in the device's zone
  /// and two phones would date the same shop differently.
  ///
  /// An unparseable value falls back to the epoch: it sorts last, which is
  /// where a row nobody can date belongs, and it is never a date this made up.
  static DateTime _instant(Object? raw) {
    final text = (raw as String? ?? '').trim();
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return DateTime.utc(1970);
    return parsed.isUtc
        ? parsed
        : DateTime.tryParse('${text}Z') ?? parsed.toUtc();
  }

  /// The SELECT is spelled out in full rather than shared as a fragment:
  /// `watch_coverage_test` reads these queries as literals to hold the
  /// LEFT-JOIN watch trap, and an interpolated string is invisible to it.
  ///
  /// Every joined table contributes a selected column, which is the trap
  /// itself: SQLite drops a LEFT JOIN nothing selects from, and PowerSync
  /// derives a watch's trigger tables from `EXPLAIN`, so an unselected join
  /// would leave the page stale when the ingredient's basis or the pack's
  /// measure changed under it.
  @override
  Stream<List<PriceObservation>> watchPrices(String ingredientId) {
    return _db
        .watch(
          'SELECT l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
          'l.cents, l.discount_cents, l.kind, l.pack_basis_amount, '
          'l.measure_id, l.sort_order, '
          'r.store, r.purchased_at, r.source, '
          'i.macros_basis, m.label AS measure_label '
          'FROM receipt_line l '
          'JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
          'LEFT JOIN ingredient i ON i.id = l.ingredient_id '
          'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
          'AND m.deleted_at IS NULL '
          'WHERE l.ingredient_id = ? AND l.deleted_at IS NULL '
          'ORDER BY r.purchased_at DESC, l.created_at DESC, l.id DESC',
          parameters: [ingredientId],
        )
        .map(_observations);
  }

  /// The LATEST price per ingredient, household-wide.
  ///
  /// The SELECT is spelled out in full for the reason [watchPrices]'s is, and
  /// every joined table contributes a selected column so PowerSync fires this
  /// watch when a price, a basis or a pack's word changes under it.
  ///
  /// The newest-first ordering does the picking: the first row for an
  /// ingredient that IS a price (`observationFrom` — a line whose pack nobody
  /// has stated is not one) wins, and the rest are what was paid before it.
  @override
  Stream<Map<String, PriceObservation>> watchLatestPrices() {
    return _db
        .watch(
          'SELECT l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
          'l.cents, l.discount_cents, l.kind, l.pack_basis_amount, '
          'l.measure_id, l.sort_order, '
          'r.store, r.purchased_at, r.source, '
          'i.macros_basis, m.label AS measure_label '
          'FROM receipt_line l '
          'JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
          'LEFT JOIN ingredient i ON i.id = l.ingredient_id '
          'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
          'AND m.deleted_at IS NULL '
          'WHERE l.ingredient_id IS NOT NULL AND l.deleted_at IS NULL '
          'ORDER BY r.purchased_at DESC, l.created_at DESC, l.id DESC',
        )
        .map(latestByIngredient);
  }

  /// The newest readable price per ingredient, from rows already ordered
  /// newest-first. Shared with the recipe and week loads, which read the same
  /// query through their own connection.
  static Map<String, PriceObservation> latestByIngredient(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final latest = <String, PriceObservation>{};
    for (final r in rows) {
      final ingredientId = r['ingredient_id'] as String?;
      if (ingredientId == null || latest.containsKey(ingredientId)) continue;
      final observation = _observationFromRow(r);
      if (observation != null) latest[ingredientId] = observation;
    }
    return latest;
  }

  @override
  Stream<List<String>> watchStores() {
    return _db
        .watch(
          'SELECT r.store AS store, MAX(r.purchased_at) AS last_seen '
          'FROM receipt r '
          "WHERE r.deleted_at IS NULL AND TRIM(r.store) <> '' "
          'GROUP BY r.store '
          'ORDER BY last_seen DESC, r.store',
        )
        .map((rows) => [for (final r in rows) r['store'] as String]);
  }

  @override
  Future<void> recordManualPrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    required String store,
    String? measureId,
    DateTime? purchasedAt,
  }) async {
    // Validated here and not only in the sheet, for the reason `addMeasure`
    // states one table over: every write path has to hold the same lines, and
    // the receipt importer is the next one.
    final word = store.trim();
    if (word.isEmpty) {
      throw ArgumentError.value(store, 'store', 'must name a store');
    }
    if (cents <= 0) {
      throw ArgumentError.value(
        cents,
        'cents',
        'a price is what was paid, and nothing was',
      );
    }
    // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
    if (!(packBasisAmount > 0) || !packBasisAmount.isFinite) {
      throw ArgumentError.value(
        packBasisAmount,
        'packBasisAmount',
        'a price needs to say what the cents bought',
      );
    }

    final receiptId = _uuid.v4();
    final lineId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final stamp = now.toIso8601String();
    final bought = (purchasedAt ?? now).toUtc().toIso8601String();

    await _db.writeTransaction((tx) async {
      // Plain INSERTs, never ON CONFLICT: the local tables are SQLite views
      // and a view rejects UPSERT.
      //
      // The subtotal IS the line's cents — a typed price has one line and no
      // paper, so there is nothing else it could honestly be. Tax and total
      // stay null rather than repeating it: nobody stated them.
      await tx.execute(
        'INSERT INTO receipt (id, household_id, store, purchased_at, '
        'subtotal_cents, source, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [receiptId, _householdId, word, bought, cents, 'manual', stamp, stamp],
      );
      await tx.execute(
        'INSERT INTO receipt_line (id, household_id, receipt_id, '
        'ingredient_id, cents, discount_cents, kind, pack_basis_amount, '
        'measure_id, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          lineId,
          _householdId,
          receiptId,
          ingredientId,
          cents,
          0,
          'item',
          packBasisAmount,
          measureId,
          0,
          stamp,
          stamp,
        ],
      );
    });
  }
}

/// The latest price per ingredient, read once rather than watched — what the
/// recipe and week cost loads join their lines against.
///
/// The query is [SqlitePriceRepository.watchLatestPrices]'s, spelled out again
/// rather than shared as a fragment: `watch_coverage_test` reads these queries
/// as literals, and an interpolated string is invisible to it.
Future<Map<String, PriceObservation>> loadLatestPrices(
  SqliteConnection db,
) async => SqlitePriceRepository.latestByIngredient(
  await db.getAll(
    'SELECT l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
    'l.cents, l.discount_cents, l.kind, l.pack_basis_amount, '
    'l.measure_id, l.sort_order, '
    'r.store, r.purchased_at, r.source, '
    'i.macros_basis, m.label AS measure_label '
    'FROM receipt_line l '
    'JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
    'LEFT JOIN ingredient i ON i.id = l.ingredient_id '
    'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
    'AND m.deleted_at IS NULL '
    'WHERE l.ingredient_id IS NOT NULL AND l.deleted_at IS NULL '
    'ORDER BY r.purchased_at DESC, l.created_at DESC, l.id DESC',
  ),
);
