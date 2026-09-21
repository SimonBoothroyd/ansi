/// The two receipt seams. Pure Dart.
///
/// [ReceiptImportRepository] is the server: photos in, a [ReceiptPayload] out,
/// narrated as it goes. A seam so every screen can be driven from a replay
/// payload with no network. [ReceiptRepository] is the ledger: watched reads
/// over the local PowerSync SQLite, and the writes.
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

/// A seam rather than a function: the app has two implementations (the edge
/// function and the replay payload) and tests add more.
// ignore: one_member_abstracts
abstract interface class ReceiptImportRepository {
  /// Reads [photos] into a receipt. [onProgress] is called as the server
  /// reports each stage; an implementation with nothing to report still answers
  /// with the same payload. Throws with a sentence a person can act on.
  Future<ReceiptPayload> readReceipt(
    ReceiptPhotos photos, {
    void Function(ReceiptProgress)? onProgress,
  });
}

abstract interface class ReceiptRepository {
  /// Every receipt the household has kept, newest first, with the two counts a
  /// ledger row prints. Watched.
  Stream<List<ReceiptLedgerRow>> watchReceipts();

  /// One receipt and its live lines. Emits null when the id names nothing, e.g.
  /// a receipt deleted on another device.
  Stream<StoredReceipt?> watchReceipt(String receiptId);

  /// Writes one receipt and all of its lines in a single transaction, first
  /// minting any measure a line's *keep as a measure* asked for. Returns the
  /// new receipt's id. Plain INSERTs, never `ON CONFLICT`: the local tables are
  /// views.
  ///
  /// Throws [ArgumentError] for an empty store or a receipt with no lines.
  Future<String> saveReceipt(ReceiptWrite write);

  /// Rewrites the saved receipt [receiptId] as [write] says: the store and date
  /// move, a line with a [ReceiptLineWrite.lineId] is updated in place, one
  /// without is new, and each of [ReceiptWrite.droppedLineIds] is tombstoned. A
  /// receipt no longer live is left alone.
  ///
  /// Printed totals and printed words stand; a hand-typed receipt's subtotal
  /// follows its lines. Refuses what [saveReceipt] refuses.
  Future<void> updateReceipt(String receiptId, ReceiptWrite write);

  /// Takes the receipt back — it and its lines are tombstoned, so every price
  /// it stated stops being one.
  Future<void> deleteReceipt(String receiptId);
}

/// One ledger row as the query answers it: the receipt's columns plus the
/// counts.
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
  int taxLinesCents,
});

/// One stored receipt, read back for its review.
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

/// One stored line, with the matched row's name and the pack's measure label
/// resolved by the join.
typedef StoredReceiptLine = ({
  String id,
  String? ingredientId,
  String? ingredientName,
  String printedText,
  String? namePrinted,
  int cents,
  int count,
  int discountCents,
  String kind,
  double? packBasisAmount,
  double? packAmount,
  String? packUnit,
  String? measureId,
  String? measureLabel,
});
