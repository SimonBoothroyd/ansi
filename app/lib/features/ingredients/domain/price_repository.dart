/// Reading and writing what the household paid — PURE DART (invariant 2).
///
/// The ledger is `receipt` + `receipt_line` (migration 0044) and a hand-typed
/// price is a one-line `manual` receipt, so this interface is deliberately
/// narrow: one write, and the two reads the ingredient page makes. The photo
/// pipeline writes the same two tables through its own door and everything
/// here goes on reading it without knowing which way a line arrived.
library;

import 'price.dart';

abstract interface class PriceRepository {
  /// Every price the household has paid for [ingredientId], **newest first**.
  ///
  /// The first element is what a recipe reads; the rest are what was paid
  /// before it, kept as paid. Lines that are not prices — a pack nobody has
  /// stated, a line whose ingredient was retired out from under it — are not
  /// in the list at all (`observationFrom`): a price that cannot be read is
  /// not shown as a zero.
  ///
  /// Watched, so a shop synced from the other phone lands on the page without
  /// a refresh.
  Stream<List<PriceObservation>> watchPrices(String ingredientId);

  /// The LATEST price for every ingredient the household has ever paid for,
  /// keyed by ingredient id — the one read every cost surface makes.
  ///
  /// One map rather than a stream per row: a recipe costs a dozen lines, a
  /// week costs every recipe it plans and the shop costs every aisle, so the
  /// question is always "what does everything cost right now". A row with no
  /// readable price is simply absent — never present with a zero.
  Stream<Map<String, PriceObservation>> watchLatestPrices();

  /// The store words this household has used, most recently first — the price
  /// sheet's chip row.
  ///
  /// A store is a word, not a row: there is no store table, so the offer is
  /// simply what has been typed before, and the sheet's `＋` names a new one.
  Stream<List<String>> watchStores();

  /// Writes one hand-typed price: a `manual` [Receipt] with a single item
  /// [ReceiptLine], in one transaction.
  ///
  /// [cents] is what was paid and [packBasisAmount] is what it bought, in the
  /// ingredient's basis unit — the caller resolves the pack through
  /// `packInBasis` first, so the density refusal happens where the person can
  /// see it rather than here. [measureId] is the pack's own word when one was
  /// picked; [purchasedAt] defaults to now, because a price typed today is a
  /// price seen today.
  ///
  /// Throws [ArgumentError] for a non-positive [cents] or [packBasisAmount],
  /// or an empty [store] — the honesty rules hold at the repository, not only
  /// at the sheet, because the receipt importer will write here too.
  Future<void> recordManualPrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    required String store,
    String? measureId,
    DateTime? purchasedAt,
  });
}
