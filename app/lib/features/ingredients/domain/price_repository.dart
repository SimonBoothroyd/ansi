/// Reading and writing what the household paid. Pure Dart.
///
/// The ledger is `receipt` + `receipt_line`; a hand-typed price is a one-line
/// `manual` receipt. The photo pipeline writes the same tables through its own
/// door.
library;

import 'price.dart';

abstract interface class PriceRepository {
  /// Every price the household has paid for [ingredientId], newest first. Lines
  /// that are not prices are left out (`observationFrom`), never shown as zero.
  /// Watched, so a synced shop lands without a refresh.
  Stream<List<PriceObservation>> watchPrices(String ingredientId);

  /// The latest price for every ingredient the household has paid for, keyed by
  /// ingredient id. One map, because every cost surface prices many rows at
  /// once. A row with no readable price is absent.
  Stream<Map<String, PriceObservation>> watchLatestPrices();

  /// Every distinct name this household's receipts have printed for
  /// [ingredientId], most recently first, for the `On receipts` fold. Grouped
  /// case-insensitively on the server's recall key. Live lines of live receipts
  /// only; a line with no printed name is skipped.
  Stream<List<ReceiptName>> watchReceiptNames(String ingredientId);

  /// The pack each of [namesPrinted] was last bought in, keyed by
  /// [printedNameKey]; read once per receipt.
  ///
  /// A printed name is one store's words for one product, so its pack can
  /// differ from the row's latest. Each entry carries the row it was bought as
  /// ([PackLastBoughtAs]), since the caller holds the line's current match.
  /// Live lines of live receipts only, latest by the receipt's `purchased_at`
  /// then the line's `updated_at`. A name never bought under is absent.
  Future<Map<String, PackLastBoughtAs>> packsByPrintedName(
    Set<String> namesPrinted,
  );

  /// The store words this household has used, most recently first, for the
  /// price sheet's chip row. There is no store table.
  Stream<List<String>> watchStores();

  /// Writes one hand-typed price: a `manual` [Receipt] with a single item
  /// [ReceiptLine], in one transaction.
  ///
  /// [cents] is what was paid and [packBasisAmount] what it bought, in the
  /// ingredient's basis unit; the caller resolves the pack through
  /// `packInBasis` first. [packAmount] with [packUnitId] or [measureId] is the
  /// pack as entered (`packAsEntered`). [purchasedAt] defaults to now.
  ///
  /// Throws [ArgumentError] for a non-positive [cents] or [packBasisAmount], or
  /// an empty [store].
  Future<void> recordManualPrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    required String store,
    double? packAmount,
    String? packUnitId,
    String? measureId,
    DateTime? purchasedAt,
  });

  /// Rewrites the stored price [lineId] in place. An UPDATE, never an upsert:
  /// the local tables are PowerSync views, which reject `INSERT … ON CONFLICT`.
  ///
  /// The line's facts always move. The receipt's store, `purchased_at` and
  /// subtotal move only when it is a one-line `manual` receipt; a photographed
  /// receipt keeps what the paper printed. [purchasedAt] is required: an edit
  /// passes back the date the price already carried.
  ///
  /// Throws [ArgumentError] as [recordManualPrice] does.
  Future<void> updatePrice({
    required String lineId,
    required int cents,
    required double packBasisAmount,
    required String store,
    required DateTime purchasedAt,
    double? packAmount,
    String? packUnitId,
    String? measureId,
  });

  /// Takes back the stored price [lineId].
  ///
  /// - A hand-typed price: the line is tombstoned and its `manual` receipt goes
  ///   with it.
  /// - A line of a photographed receipt stays, and only its pack facts are
  ///   cleared (`pack_basis_amount`, `pack_amount`, `pack_unit`, `measure_id`),
  ///   so it stops pricing anything. `ingredient_id` stays.
  Future<void> deletePrice(String lineId);
}

/// One name this household's receipts have printed for an ingredient.
///
/// Not an alias: it is a store's abbreviation, never reaches the vocabulary
/// matcher, and nothing is learned from it. Reading these back is how a
/// mis-transcription is spotted; correcting the receipt fixes it, because the
/// latest answer per name is what the next receipt recalls.
typedef ReceiptName = ({
  /// The name as the most recent line spells it. Lines are grouped
  /// case-insensitively.
  String namePrinted,

  /// How many live lines carry it, across every live receipt.
  int lineCount,

  /// The stores that have printed it, most recently first, each once. An
  /// unnamed store contributes nothing.
  List<String> stores,

  /// When it was last on a receipt — that receipt's own date, never a scan's.
  DateTime lastSeen,

  /// The most recent receipt carrying it. `/receipts/:id` is the editable
  /// review, so this is where a wrong match is answered.
  String receiptId,
});
