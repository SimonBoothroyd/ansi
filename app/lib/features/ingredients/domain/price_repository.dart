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

  /// Every distinct name this household's receipts have carried for
  /// [ingredientId], most recently first — what the `On receipts` fold lists.
  ///
  /// This is the receipt door's memory read back (`name_printed`, migration
  /// 0047): a store's own printed words, grouped case-insensitively on the
  /// same key the server's recall uses, so a mis-transcription stands beside
  /// the line it is a mis-transcription of and somebody can see it.
  ///
  /// Live lines of live receipts only, and a line with **no printed name** is
  /// not one: a hand-typed price has no paper behind it, so there is nothing
  /// for the memory to be keyed by and nothing to spot-check.
  Stream<List<ReceiptName>> watchReceiptNames(String ingredientId);

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
  /// see it rather than here. [packAmount] with [packUnitId], or [packAmount]
  /// with [measureId], is the pack as the person SAID it — the pair
  /// `packAsEntered` builds, kept so the ledger can print it back and nothing
  /// derived from it. [purchasedAt] defaults to now, because a price typed
  /// today is a price seen today.
  ///
  /// Throws [ArgumentError] for a non-positive [cents] or [packBasisAmount],
  /// or an empty [store] — the honesty rules hold at the repository, not only
  /// at the sheet, because the receipt importer will write here too.
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

  /// Rewrites the stored price [lineId] in place — the same four answers the
  /// sheet asks, for a line that already exists.
  ///
  /// It is an **UPDATE, never an upsert**: the local tables are PowerSync
  /// views, which reject `INSERT … ON CONFLICT`.
  ///
  /// The line's own facts always move. Its receipt's do too **only when the
  /// receipt is this app's one-line `manual` kind** — store, `purchased_at`
  /// and the subtotal that is simply the line's cents. A photographed receipt
  /// is a piece of paper: correcting what one of its lines is understood to be
  /// worth must not restate what the paper printed, or which shop printed it.
  ///
  /// [purchasedAt] is passed rather than defaulted, because an edit is a
  /// correction and not a new shop: the caller hands back the date the price
  /// already carried unless the person changed it.
  ///
  /// Throws [ArgumentError] on the same three honesty rules
  /// [recordManualPrice] holds.
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

  /// Takes back the stored price [lineId] — a mistyped price, undone.
  ///
  /// **What that means depends on what is behind the line**, because the two
  /// cases are different objects:
  ///
  /// - A hand-typed price is a one-line `manual` receipt with no paper behind
  ///   it, so the line is tombstoned and its receipt goes with it: there is
  ///   nothing left for it to be.
  /// - A line of a **photographed** receipt stays. A receipt is a piece of
  ///   paper and the paper is still true — the cents were paid, the store and
  ///   the date stand, and the receipt has to go on adding up. So only its
  ///   **price facts** are cleared: `pack_basis_amount`, `pack_amount`,
  ///   `pack_unit` and `measure_id` become null and the line stops pricing
  ///   anything, while `ingredient_id` stays, because what was bought is not
  ///   in doubt — only what the pack was.
  Future<void> deletePrice(String lineId);
}

/// One name this household's receipts have carried for an ingredient — what
/// the receipt door's memory is filed under.
///
/// **It is not an alias.** An `ingredient_alias` is a word this household's
/// own language holds, and the recipe door, the picker and the search all see
/// it. This is a store's abbreviation, printed on paper, kept only beside the
/// answer somebody gave it once — nothing here ever reaches the vocabulary
/// matcher, and nothing here is learned. Reading these back is how a
/// mis-transcription (`SHELLER EDAMAME` beside `SHELLED EDAMAME`) is spotted;
/// correcting the receipt it is printed on is how it is answered, because the
/// latest answer per name is the one the next receipt recalls.
typedef ReceiptName = ({
  /// The name as the MOST RECENT line spells it.
  ///
  /// Lines are grouped case-insensitively, so one word in two cases is one
  /// entry and the newest spelling is the one shown: a printed name is a
  /// reading of paper, and the latest reading is the one this household last
  /// stood behind.
  String namePrinted,

  /// How many live lines carry it, across every live receipt.
  int lineCount,

  /// The stores that have printed it, most recently first, each named once. A
  /// receipt whose store nobody named contributes no word, rather than a blank
  /// one.
  List<String> stores,

  /// When it was last on a receipt — that receipt's own date, never a scan's.
  DateTime lastSeen,

  /// The most recent receipt carrying it. `/receipts/:id` is the editable
  /// review, so this is where a wrong match is answered.
  String receiptId,
});
