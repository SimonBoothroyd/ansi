/// [PriceRepository] over the local PowerSync SQLite: synced receipt rows,
/// and the base price on each `ingredient` row.
library;

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../domain/cost_price.dart';
import '../domain/price.dart';
import '../domain/price_repository.dart';

class SqlitePriceRepository implements PriceRepository {
  const SqlitePriceRepository(this._db);

  final SqliteConnection _db;

  /// The price rows as observations. [observationFrom] decides what is a price;
  /// lines that are not are dropped, never rendered as zero.
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
          // A row synced before the column reads as one of the thing, which
          // is what it meant when it was written.
          count: (r['count'] as num?)?.toInt() ?? 1,
          kind: ReceiptLineKind.fromDb(r['kind'] as String?),
          packBasisAmount: (r['pack_basis_amount'] as num?)?.toDouble(),
          packAmount: (r['pack_amount'] as num?)?.toDouble(),
          // An unknown unit id reads as no unit, and the line prints its basis
          // figure instead.
          packUnit: unitById((r['pack_unit'] as String?) ?? ''),
          measureId: r['measure_id'] as String?,
          sortOrder: (r['sort_order'] as int?) ?? 0,
        ),
        Receipt(
          id: r['receipt_id'] as String,
          store: (r['store'] as String?) ?? '',
          purchasedAt: receiptInstant(r['purchased_at']),
          source: ReceiptSource.fromDb(r['source'] as String?),
        ),
        basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
        packLabel: r['measure_label'] as String?,
      );

  /// The base price a row's `base_price_*` columns state, or null. Reads
  /// `row_id`, the row's `macros_basis` and the base measure's label as
  /// `base_measure_label`.
  static BasePrice? _basePriceFromRow(Map<String, dynamic> r) => basePriceFrom(
    ingredientId: r['row_id'] as String,
    cents: (r['base_price_cents'] as num?)?.toInt(),
    packBasisAmount: (r['base_price_pack_basis_amount'] as num?)?.toDouble(),
    basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
    setAt: r['base_price_set_at'] == null
        ? null
        : receiptInstant(r['base_price_set_at']),
    packAmount: (r['base_price_pack_amount'] as num?)?.toDouble(),
    packUnit: unitById((r['base_price_pack_unit'] as String?) ?? ''),
    measureId: r['base_price_measure_id'] as String?,
    packLabel: r['base_measure_label'] as String?,
  );

  /// The SELECT is a full literal, not a shared fragment: `watch_coverage_test`
  /// reads these queries as literals. Every joined table contributes a selected
  /// column, because SQLite drops an unselected LEFT JOIN and PowerSync would
  /// then miss that table as a watch trigger.
  @override
  Stream<List<PriceObservation>> watchPrices(String ingredientId) {
    return _db
        .watch(
          'SELECT l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
          'l.cents, l.discount_cents, l.count, l.kind, l.pack_basis_amount, '
          'l.pack_amount, l.pack_unit, l.measure_id, l.sort_order, '
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

  /// The latest price per ingredient, household-wide. A full literal with a
  /// column selected from every joined table, as in [watchPrices]. Rows are
  /// newest first, so the first row per ingredient that is a price
  /// (`observationFrom`) wins.
  @override
  Stream<Map<String, PriceObservation>> watchLatestPrices() {
    return _db
        .watch(
          'SELECT l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
          'l.cents, l.discount_cents, l.count, l.kind, l.pack_basis_amount, '
          'l.pack_amount, l.pack_unit, l.measure_id, l.sort_order, '
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

  /// The newest readable receipt price per ingredient, from rows ordered newest
  /// first.
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

  /// Every row with each of its live receipt lines, newest first, folded by
  /// [costPricesFrom]. Driven from `ingredient` so a row with a base price and
  /// no receipt is still a row. A full literal with a column selected from
  /// every joined table, as in [watchPrices].
  @override
  Stream<Map<String, UnitPrice>> watchCostPrices() {
    return _db
        .watch(
          'SELECT i.id AS row_id, i.macros_basis, i.base_price_cents, '
          'i.base_price_pack_basis_amount, i.base_price_pack_amount, '
          'i.base_price_pack_unit, i.base_price_measure_id, '
          'i.base_price_set_at, bm.label AS base_measure_label, '
          'l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
          'l.cents, l.discount_cents, l.count, l.kind, l.pack_basis_amount, '
          'l.pack_amount, l.pack_unit, l.measure_id, l.sort_order, '
          'r.id AS receipt_row, r.store, r.purchased_at, r.source, '
          'm.label AS measure_label '
          'FROM ingredient i '
          'LEFT JOIN receipt_line l ON l.ingredient_id = i.id '
          'AND l.deleted_at IS NULL '
          'LEFT JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
          'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
          'AND m.deleted_at IS NULL '
          'LEFT JOIN ingredient_measure bm ON bm.id = i.base_price_measure_id '
          'AND bm.deleted_at IS NULL '
          'ORDER BY i.id, r.purchased_at DESC, l.created_at DESC, l.id DESC',
        )
        .map(costPricesFrom);
  }

  /// The price each row's cost reads, from [watchCostPrices]'s rows: per row,
  /// the first line that is a price on a live receipt, and the row's base
  /// price, resolved by [costPrices]. Shared with the recipe and week cost
  /// loads ([loadCostPrices]).
  static Map<String, UnitPrice> costPricesFrom(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final paid = <String, PriceObservation>{};
    final base = <String, BasePrice>{};
    final seen = <String>{};
    for (final r in rows) {
      final id = r['row_id'] as String;
      if (seen.add(id)) {
        if (_basePriceFromRow(r) case final price?) base[id] = price;
      }
      // No line, or a line whose receipt was deleted: nothing paid here.
      if (paid.containsKey(id) || r['id'] == null || r['receipt_row'] == null) {
        continue;
      }
      if (_observationFromRow(r) case final price?) paid[id] = price;
    }
    return costPrices(latestPaid: paid, base: base);
  }

  @override
  Stream<BasePrice?> watchBasePrice(String ingredientId) {
    return _db
        .watch(
          'SELECT i.id AS row_id, i.macros_basis, i.base_price_cents, '
          'i.base_price_pack_basis_amount, i.base_price_pack_amount, '
          'i.base_price_pack_unit, i.base_price_measure_id, '
          'i.base_price_set_at, bm.label AS base_measure_label '
          'FROM ingredient i '
          'LEFT JOIN ingredient_measure bm ON bm.id = i.base_price_measure_id '
          'AND bm.deleted_at IS NULL '
          'WHERE i.id = ?',
          parameters: [ingredientId],
        )
        .map((rows) => rows.isEmpty ? null : _basePriceFromRow(rows.first));
  }

  /// The names this household's receipts have printed for one ingredient. A
  /// full literal with a column selected from both joined tables, as in
  /// [watchPrices]. No `GROUP BY`: the fold below needs the newest row's own
  /// spelling, receipt and date.
  @override
  Stream<List<ReceiptName>> watchReceiptNames(String ingredientId) {
    return _db
        .watch(
          'SELECT l.name_printed, l.receipt_id, l.created_at, l.id, '
          'r.store, r.purchased_at '
          'FROM receipt_line l '
          'JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
          'WHERE l.ingredient_id = ? AND l.deleted_at IS NULL '
          "AND TRIM(COALESCE(l.name_printed, '')) <> '' "
          'ORDER BY r.purchased_at DESC, l.created_at DESC, l.id DESC',
          parameters: [ingredientId],
        )
        .map(receiptNamesFrom);
  }

  /// The ordered rows folded into one entry per name, newest first. A name's
  /// first row fixes its spelling, date and receipt; later rows only add to the
  /// count and the stores. Keyed by [printedNameKey], so spellings that differ
  /// by more than case stay separate.
  static List<ReceiptName> receiptNamesFrom(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final tallies = <String, _NameTally>{};
    for (final r in rows) {
      final key = printedNameKey(r['name_printed'] as String?);
      if (key == null) continue;
      final tally = tallies.putIfAbsent(
        key,
        () => _NameTally(
          namePrinted: ((r['name_printed'] as String?) ?? '').trim(),
          lastSeen: receiptInstant(r['purchased_at']),
          receiptId: r['receipt_id'] as String,
        ),
      );
      tally.lines++;
      final store = ((r['store'] as String?) ?? '').trim();
      if (store.isNotEmpty && !tally.stores.contains(store)) {
        tally.stores.add(store);
      }
    }
    return [
      for (final tally in tallies.values)
        (
          namePrinted: tally.namePrinted,
          lineCount: tally.lines,
          stores: tally.stores,
          lastSeen: tally.lastSeen,
          receiptId: tally.receiptId,
        ),
    ];
  }

  /// One query per receipt: the keys ride as placeholders in a single `IN`.
  ///
  /// `UPPER(TRIM(l.name_printed))` is [printedNameKey] in SQL. The map is keyed
  /// by the Dart one, read off the row's own words. Where the two disagree
  /// (SQLite's `UPPER` is ASCII-only) the row is not returned and the line
  /// falls back to the row's latest price. `observationFrom` gates what counts
  /// as a pack.
  @override
  Future<Map<String, PackLastBoughtAs>> packsByPrintedName(
    Set<String> namesPrinted,
  ) async {
    final keys = {
      for (final name in namesPrinted)
        if (printedNameKey(name) case final key?) key,
    }.toList();
    if (keys.isEmpty) return const {};
    final marks = List.filled(keys.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
      'l.name_printed, l.cents, l.discount_cents, l.count, l.kind, '
      'l.pack_basis_amount, l.pack_amount, l.pack_unit, l.measure_id, '
      'l.sort_order, r.store, r.purchased_at, r.source, '
      'i.macros_basis, m.label AS measure_label '
      'FROM receipt_line l '
      'JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
      'LEFT JOIN ingredient i ON i.id = l.ingredient_id '
      'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
      'AND m.deleted_at IS NULL '
      'WHERE l.ingredient_id IS NOT NULL AND l.deleted_at IS NULL '
      'AND l.pack_basis_amount IS NOT NULL '
      'AND UPPER(TRIM(l.name_printed)) IN ($marks) '
      'ORDER BY r.purchased_at DESC, l.updated_at DESC, l.id DESC',
      keys,
    );
    final packs = <String, PackLastBoughtAs>{};
    for (final r in rows) {
      final key = printedNameKey(r['name_printed'] as String?);
      if (key == null || packs.containsKey(key)) continue;
      final observation = _observationFromRow(r);
      if (observation == null) continue;
      packs[key] = (
        ingredientId: r['ingredient_id'] as String,
        pack: observation,
      );
    }
    return packs;
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
  Future<void> setBasePrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    double? packAmount,
    String? packUnitId,
    String? measureId,
  }) async {
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
    final stamp = DateTime.now().toUtc().toIso8601String();
    // Wall time, as a receipt's date is kept, so the month a cost names is
    // the same on every device.
    final setAt = receiptStamp(DateTime.now());
    // UPDATE, never an upsert: the local tables are views.
    await _db.execute(
      'UPDATE ingredient SET base_price_cents = ?, '
      'base_price_pack_basis_amount = ?, base_price_pack_amount = ?, '
      'base_price_pack_unit = ?, base_price_measure_id = ?, '
      'base_price_set_at = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [
        cents,
        packBasisAmount,
        packAmount,
        packUnitId,
        measureId,
        setAt,
        stamp,
        ingredientId,
      ],
    );
  }

  @override
  Future<void> clearBasePrice(String ingredientId) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    // Cleared whole: the server refuses a base price missing any of its parts.
    await _db.execute(
      'UPDATE ingredient SET base_price_cents = NULL, '
      'base_price_pack_basis_amount = NULL, base_price_pack_amount = NULL, '
      'base_price_pack_unit = NULL, base_price_measure_id = NULL, '
      'base_price_set_at = NULL, updated_at = ? '
      'WHERE id = ?',
      [stamp, ingredientId],
    );
  }
}

/// One name's running tally while [SqlitePriceRepository.receiptNamesFrom]
/// walks the rows: the newest row's facts, plus the count and stores later rows
/// add to.
class _NameTally {
  _NameTally({
    required this.namePrinted,
    required this.lastSeen,
    required this.receiptId,
  });

  final String namePrinted;
  final DateTime lastSeen;
  final String receiptId;
  final List<String> stores = [];
  int lines = 0;
}

/// The price every row's cost reads, loaded once: what the recipe and week
/// cost loads join against. Repeats [SqlitePriceRepository.watchCostPrices]'s
/// query as a literal, because `watch_coverage_test` cannot see an
/// interpolated fragment.
Future<Map<String, UnitPrice>> loadCostPrices(SqliteConnection db) async =>
    SqlitePriceRepository.costPricesFrom(
      await db.getAll(
        'SELECT i.id AS row_id, i.macros_basis, i.base_price_cents, '
        'i.base_price_pack_basis_amount, i.base_price_pack_amount, '
        'i.base_price_pack_unit, i.base_price_measure_id, '
        'i.base_price_set_at, bm.label AS base_measure_label, '
        'l.id, l.receipt_id, l.ingredient_id, l.printed_text, '
        'l.cents, l.discount_cents, l.count, l.kind, l.pack_basis_amount, '
        'l.pack_amount, l.pack_unit, l.measure_id, l.sort_order, '
        'r.id AS receipt_row, r.store, r.purchased_at, r.source, '
        'm.label AS measure_label '
        'FROM ingredient i '
        'LEFT JOIN receipt_line l ON l.ingredient_id = i.id '
        'AND l.deleted_at IS NULL '
        'LEFT JOIN receipt r ON r.id = l.receipt_id AND r.deleted_at IS NULL '
        'LEFT JOIN ingredient_measure m ON m.id = l.measure_id '
        'AND m.deleted_at IS NULL '
        'LEFT JOIN ingredient_measure bm ON bm.id = i.base_price_measure_id '
        'AND bm.deleted_at IS NULL '
        'ORDER BY i.id, r.purchased_at DESC, l.created_at DESC, l.id DESC',
      ),
    );
