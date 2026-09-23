/// Reading and writing what the household paid. Pure Dart.
///
/// What was paid lives on `receipt` + `receipt_line`, which the photo
/// pipeline writes through its own door. A hand-typed price is the row's own
/// [BasePrice], on the `ingredient` row, and never a receipt.
library;

import 'cost_price.dart';
import 'price.dart';

abstract interface class PriceRepository {
  /// Every price the household has paid for [ingredientId], newest first. Lines
  /// that are not prices are left out (`observationFrom`), never shown as zero.
  /// Watched, so a synced shop lands without a refresh.
  Stream<List<PriceObservation>> watchPrices(String ingredientId);

  /// The latest price PAID for every ingredient, keyed by ingredient id. A row
  /// with no readable receipt price is absent.
  ///
  /// This is the pack a row was last bought in, for the receipt review to
  /// carry; it is not what a cost reads — that is [watchCostPrices].
  Stream<Map<String, PriceObservation>> watchLatestPrices();

  /// The price every cost reads, for every row that has one, keyed by
  /// ingredient id: [costPrices] over the newest receipt price and the row's
  /// base price. One map, because every cost surface prices many rows at once.
  /// Watched, so a synced shop or a new base price moves every figure.
  Stream<Map<String, UnitPrice>> watchCostPrices();

  /// [ingredientId]'s base price, or null when it states none. Watched.
  Stream<BasePrice?> watchBasePrice(String ingredientId);

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
  /// price sheet's and the receipt review's chip rows: every live receipt's
  /// store and every base price's. There is no store table.
  Stream<List<String>> watchStores();

  /// Sets [ingredientId]'s base price, replacing any it had. An UPDATE of the
  /// row, never an upsert: the local tables are PowerSync views.
  ///
  /// [cents] is what was paid and [packBasisAmount] what it bought, in the
  /// row's basis unit; the caller resolves the pack through `packInBasis`
  /// first. [packAmount] with [packUnitId] or [measureId] is the pack as
  /// entered (`packAsEntered`). [store] is where it is paid, trimmed; blank
  /// or null names none. The date it was set is now.
  ///
  /// Throws [ArgumentError] for a non-positive [cents] or [packBasisAmount].
  Future<void> setBasePrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    String? store,
    double? packAmount,
    String? packUnitId,
    String? measureId,
  });

  /// Takes back [ingredientId]'s base price, clearing it whole. Receipt prices
  /// are untouched.
  Future<void> clearBasePrice(String ingredientId);
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
