/// [PriceRepository] over the local PowerSync SQLite (synced receipt rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
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
          packAmount: (r['pack_amount'] as num?)?.toDouble(),
          // A unit id this catalog does not know reads as no unit at all, and
          // the line falls back to printing the basis figure it is derived
          // from — never a word this app cannot stand behind.
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

  /// The names this household's receipts have carried for one ingredient.
  ///
  /// The SELECT is spelled out in full for the reason [watchPrices]'s is, and
  /// both joined tables contribute a selected column, so PowerSync fires this
  /// watch when a line is re-matched to a different row and when the receipt
  /// carrying it is renamed, re-dated or taken back.
  ///
  /// No grouping happens here — not a `GROUP BY` and not a key column either:
  /// the fold below needs the newest row's own spelling, receipt and date,
  /// which an aggregate would have to win back with a correlated subquery, and
  /// it files each row under [printedNameKey] off the row's own words.
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

  /// The ordered rows folded into one entry per name, **newest first**.
  ///
  /// The rows arrive newest-first, so a name's FIRST row decides everything a
  /// reader sees about it — the spelling, the date, and the receipt a
  /// correction is made on — and every row after it only adds to the count and
  /// the store words. That also makes insertion order the answer's order, so
  /// nothing is sorted again afterwards.
  ///
  /// The key is [printedNameKey] — the one spelling of the printed-name key
  /// this app has, shared with the carry-over read below and with the server's
  /// own recall. Two spellings that differ by more than case are two names on
  /// purpose: that difference is exactly what this list exists to show.
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

  /// One query for the whole receipt, however many names it carries: the keys
  /// ride as placeholders in a single `IN`, and nothing here grows per line.
  ///
  /// `UPPER(TRIM(l.name_printed))` is the key spelled in SQL and
  /// [printedNameKey] is the same key spelled in Dart. The returned map is
  /// keyed by the **Dart** one, read off the row's own words, so what a caller
  /// looks up is exactly what it gets; where the two normalisations could
  /// disagree (SQLite's `UPPER` is ASCII-only) the row simply does not come
  /// back and the line falls through to the row's latest price, which is a
  /// carry-over lost and never a wrong one.
  ///
  /// `observationFrom` is the gate here as everywhere: a line whose pack
  /// nobody stated, or that rang up as nothing, is not a pack to carry.
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
      'l.name_printed, l.cents, l.discount_cents, l.kind, '
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
  Future<void> recordManualPrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    required String store,
    double? packAmount,
    String? packUnitId,
    String? measureId,
    DateTime? purchasedAt,
  }) async {
    final word = _checked(cents, packBasisAmount, store);

    final receiptId = _uuid.v4();
    final lineId = _uuid.v4();
    final stamp = DateTime.now().toUtc().toIso8601String();
    // The day this was paid on is WALL time, like a scanned receipt's: a real
    // instant would show an evening price as tomorrow's, and file it into
    // next week.
    final bought = receiptStamp(purchasedAt ?? DateTime.now());

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
        'pack_amount, pack_unit, measure_id, sort_order, created_at, '
        'updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          lineId,
          _householdId,
          receiptId,
          ingredientId,
          cents,
          0,
          'item',
          packBasisAmount,
          packAmount,
          packUnitId,
          measureId,
          0,
          stamp,
          stamp,
        ],
      );
    });
  }

  @override
  Future<void> updatePrice({
    required String lineId,
    required int cents,
    required double packBasisAmount,
    required String store,
    required DateTime purchasedAt,
    double? packAmount,
    String? packUnitId,
    String? measureId,
  }) async {
    final word = _checked(cents, packBasisAmount, store);
    final stamp = DateTime.now().toUtc().toIso8601String();
    final bought = receiptStamp(purchasedAt);

    await _db.writeTransaction((tx) async {
      // UPDATE, never an upsert: the local tables are SQLite views, and a view
      // rejects `INSERT … ON CONFLICT`.
      await tx.execute(
        'UPDATE receipt_line SET cents = ?, pack_basis_amount = ?, '
        'pack_amount = ?, pack_unit = ?, measure_id = ?, updated_at = ? '
        'WHERE id = ? AND deleted_at IS NULL',
        [
          cents,
          packBasisAmount,
          packAmount,
          packUnitId,
          measureId,
          stamp,
          lineId,
        ],
      );
      // The store, the date and the subtotal move only on this app's own
      // one-line `manual` receipt, which has no printed figures to contradict.
      // A photographed receipt keeps what the paper said.
      if (await _isOneManualLine(tx, lineId)) {
        await tx.execute(
          'UPDATE receipt SET store = ?, purchased_at = ?, '
          'subtotal_cents = ?, updated_at = ? '
          'WHERE id = (SELECT receipt_id FROM receipt_line WHERE id = ?)',
          [word, bought, cents, stamp, lineId],
        );
      }
    });
  }

  @override
  Future<void> deletePrice(String lineId) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      // Asked BEFORE anything is written, while the line is still one of the
      // receipt's live ones to count.
      final manual = await _isManualReceipt(tx, lineId);
      if (!manual) {
        // A photographed receipt keeps its line: the cents were paid and the
        // paper still has to add up. Only the price facts go, so the line
        // stops pricing anything while still saying what was bought.
        // No door reaches this today — a scanned line is corrected on its own
        // receipt — and it stays because the rule is the table's, not a
        // sheet's.
        await tx.execute(
          'UPDATE receipt_line SET pack_basis_amount = NULL, '
          'pack_amount = NULL, pack_unit = NULL, measure_id = NULL, '
          'updated_at = ? WHERE id = ? AND deleted_at IS NULL',
          [stamp, lineId],
        );
        return;
      }
      if (await _isOneManualLine(tx, lineId)) {
        await tx.execute(
          'UPDATE receipt SET deleted_at = ?, updated_at = ? '
          'WHERE id = (SELECT receipt_id FROM receipt_line WHERE id = ?)',
          [stamp, stamp, lineId],
        );
      }
      await tx.execute(
        'UPDATE receipt_line SET deleted_at = ?, updated_at = ? '
        'WHERE id = ? AND deleted_at IS NULL',
        [stamp, stamp, lineId],
      );
    });
  }

  /// Whether [lineId] belongs to this app's own hand-typed kind of receipt.
  static Future<bool> _isManualReceipt(
    SqliteWriteContext tx,
    String lineId,
  ) async {
    final row = await tx.getOptional(
      'SELECT r.source AS source FROM receipt_line l '
      'JOIN receipt r ON r.id = l.receipt_id WHERE l.id = ?',
      [lineId],
    );
    return row != null && row['source'] == 'manual';
  }

  /// Whether [lineId] is the only live line of a `manual` receipt — this app's
  /// own hand-typed price, whose receipt says nothing the line does not.
  ///
  /// A photographed receipt answers false however few lines survive on it: it
  /// is a piece of paper, and the paper is not a price.
  static Future<bool> _isOneManualLine(
    SqliteWriteContext tx,
    String lineId,
  ) async {
    // `getOptional`: a line that is not there answers no rather than throwing
    // — there is simply nothing to carry along.
    final row = await tx.getOptional(
      'SELECT r.source AS source, '
      '(SELECT COUNT(*) FROM receipt_line x '
      ' WHERE x.receipt_id = r.id AND x.deleted_at IS NULL) AS live '
      'FROM receipt_line l JOIN receipt r ON r.id = l.receipt_id '
      'WHERE l.id = ?',
      [lineId],
    );
    return row != null &&
        row['source'] == 'manual' &&
        (row['live'] as num?) == 1;
  }

  /// The three honesty rules every write here holds, and the trimmed store
  /// word they hand back.
  ///
  /// Validated at the repository and not only in the sheet, for the reason
  /// `addMeasure` states one table over: every write path has to hold the same
  /// lines, and the receipt importer is the next one.
  static String _checked(int cents, double packBasisAmount, String store) {
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
    return word;
  }
}

/// One name while [SqlitePriceRepository.receiptNamesFrom] is still walking the
/// rows: the newest row's own three facts, which are fixed the moment the name
/// is first seen, beside the two things every later row adds to.
///
/// Mutable, and private, because a record cannot be added to — and the walk is
/// what decides these, one row at a time.
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
  ),
);
