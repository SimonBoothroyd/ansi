/// The two receipt seams — PURE DART (invariant 2).
///
/// [ReceiptImportRepository] is the server: photos in, a [ReceiptPayload]
/// out, narrated as it goes. It is the receipt twin of `ImportRepository`'s
/// extract→match half, and it is deliberately a seam rather than a direct
/// call, so every screen can be driven from a replay payload with no network
/// and no billed model call behind it.
///
/// [ReceiptRepository] is the ledger: the receipts the household has kept,
/// and the one write that adds another. Reads are watched queries over the
/// local PowerSync SQLite, like every other read in the app.
library;

import 'receipt_payload.dart';
import 'receipt_save.dart';
import 'receipt_stage.dart';

/// What the scan door handed over: the cropped pages, in the order they were
/// shot, top to bottom.
class ReceiptPhotos {
  const ReceiptPhotos(this.imagePaths);

  final List<String> imagePaths;
}

/// It is a SEAM, not a function: the app carries two implementations — the
/// edge function and the replay payload — and a third in every test, and
/// naming the seam is what lets a screen be driven without a server.
// ignore: one_member_abstracts
abstract interface class ReceiptImportRepository {
  /// Reads [photos] into a receipt.
  ///
  /// [onProgress] is called as the server reports each stage; it is a
  /// courtesy and never the result, so an implementation with nothing to
  /// report still answers with the same payload.
  ///
  /// Throws with a sentence a person can act on — the same four failure
  /// shapes the recipe import has, because they are the same four failures.
  Future<ReceiptPayload> readReceipt(
    ReceiptPhotos photos, {
    void Function(ReceiptProgress)? onProgress,
  });
}

abstract interface class ReceiptRepository {
  /// Every receipt the household has kept, newest first, with the two counts
  /// a ledger row prints. Watched, so a shop saved on the other phone lands
  /// without a refresh.
  Stream<List<ReceiptLedgerRow>> watchReceipts();

  /// One receipt and its live lines, for the read-only review a ledger row
  /// opens. Emits null when the id names nothing — a receipt deleted on the
  /// other phone is not an error, it is gone.
  Stream<StoredReceipt?> watchReceipt(String receiptId);

  /// Writes one receipt and all of its lines in a single transaction, minting
  /// any measure a line's *keep as a measure* asked for first, and returns
  /// the new receipt's id.
  ///
  /// Plain INSERTs, never `ON CONFLICT`: the local tables are SQLite views.
  ///
  /// Throws [ArgumentError] for an empty store or a receipt with no lines —
  /// the honesty rules hold at the repository, not only at the screen.
  Future<String> saveReceipt(ReceiptWrite write);

  /// Rewrites the saved receipt [receiptId] as [write] says it now stands:
  /// the store and the date move, a line carrying its
  /// [ReceiptLineWrite.lineId] is updated in place, a line without one is
  /// new, and a stored line [write] no longer carries is tombstoned.
  ///
  /// The printed totals and every line's printed words are the paper's, and
  /// are left as the scan wrote them. Refuses what [saveReceipt] refuses.
  Future<void> updateReceipt(String receiptId, ReceiptWrite write);

  /// Takes the receipt back — it and its lines are tombstoned, so every price
  /// it stated stops being one.
  Future<void> deleteReceipt(String receiptId);
}

/// One ledger row as the query answers it — the receipt's own columns plus
/// the counts, which are cheaper to ask the database for than to carry every
/// line up for.
typedef ReceiptLedgerRow = ({
  String id,
  String store,
  DateTime purchasedAt,
  String source,
  int? subtotalCents,
  int? taxCents,
  int? totalCents,
  int lineCount,
  int notFoodCount,
  int linesSumCents,
});

/// One stored receipt, read back for its read-only review.
typedef StoredReceipt = ({
  String id,
  String store,
  DateTime purchasedAt,
  String source,
  int? subtotalCents,
  int? taxCents,
  int? totalCents,
  List<StoredReceiptLine> lines,
});

/// One stored line, with the two words the review prints beside it — the
/// matched row's name and the pack's measure label — resolved by the join
/// rather than copied into the line.
typedef StoredReceiptLine = ({
  String id,
  String? ingredientId,
  String? ingredientName,
  String printedText,
  int cents,
  int discountCents,
  String kind,
  double? packBasisAmount,
  double? packAmount,
  String? packUnit,
  String? measureId,
  String? measureLabel,
  String? macrosBasis,
});
