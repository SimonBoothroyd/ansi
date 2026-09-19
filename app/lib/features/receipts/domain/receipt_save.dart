/// What Save writes — PURE DART (invariant 2).
///
/// One `receipt` and every line it kept, in one transaction. The mapping is a
/// pure function so the rules can be read and tested without a database: what
/// counts as a line, what a non-food line may carry, and where a measure gets
/// minted.
///
/// **Nothing is written until Save**, exactly as the recipe review promises,
/// so a scan abandoned half way leaves nothing behind.
library;

import 'package:meta/meta.dart';

import '../../ingredients/domain/price.dart';
import 'receipt_payload.dart';
import 'receipt_review.dart';

/// One `receipt_line` row, as the repository will insert it.
@immutable
class ReceiptLineWrite {
  const ReceiptLineWrite({
    required this.sortOrder,
    required this.printedText,
    required this.cents,
    required this.kind,
    this.lineId,
    this.discountCents = 0,
    this.ingredientId,
    this.packBasisAmount,
    this.packAmount,
    this.packUnitId,
    this.measureId,
    this.mintMeasureLabel,
  });

  /// The stored row this line already is, when a SAVED receipt is being
  /// edited; null for a line no row holds yet — every line of a fresh scan.
  final String? lineId;

  final int sortOrder;
  final String printedText;
  final int cents;
  final int discountCents;
  final ReceiptLineKind kind;
  final String? ingredientId;
  final double? packBasisAmount;
  final double? packAmount;
  final String? packUnitId;
  final String? measureId;

  /// A word to mint on [ingredientId] as a measure weighing
  /// [packBasisAmount], before this line is written — the *keep as a measure*
  /// toggle. The line then points at the new measure instead of at a unit,
  /// which is what makes the next receipt for this row land on the word.
  ///
  /// Null on every other line, which is nearly all of them.
  final String? mintMeasureLabel;
}

/// One `receipt` row and its lines.
@immutable
class ReceiptWrite {
  const ReceiptWrite({
    required this.store,
    required this.purchasedAt,
    required this.lines,
    this.subtotalCents,
    this.taxCents,
    this.totalCents,
  });

  final String store;

  /// The receipt's own moment — the shop's, never the scan's. A receipt
  /// scanned on Tuesday for Sunday's shop files under Sunday's week.
  final DateTime purchasedAt;

  /// As printed, kept as printed and never re-derived from the lines.
  final int? subtotalCents;
  final int? taxCents;
  final int? totalCents;

  final List<ReceiptLineWrite> lines;
}

/// The review, as rows.
///
/// A dropped line is simply absent — nothing was ever written for it to be
/// removed from. A line that is not food carries **no ingredient and no
/// pack**: it counts toward what the trip cost and toward nothing else, and
/// letting a folded line keep a stale match would leave a price hanging off
/// a bag fee.
ReceiptWrite buildReceiptSave({
  required String store,
  required DateTime purchasedAt,
  required List<ReceiptLineDraft> drafts,
  int? subtotalCents,
  int? taxCents,
  int? totalCents,
}) {
  final lines = <ReceiptLineWrite>[];
  for (final draft in drafts) {
    if (draft.dropped) continue;
    final food = draft.kind.isFood;
    lines.add(
      ReceiptLineWrite(
        lineId: draft.lineId,
        sortOrder: lines.length,
        printedText: draft.printedText,
        cents: draft.cents,
        discountCents: draft.discountCents,
        kind: _kindOf(draft.kind),
        ingredientId: food ? draft.ingredientId : null,
        packBasisAmount: food ? draft.packBasisAmount : null,
        packAmount: food ? draft.packAmount : null,
        packUnitId: food ? draft.packUnit?.id : null,
        measureId: food ? draft.measureId : null,
        mintMeasureLabel:
            food &&
                draft.ingredientId != null &&
                (draft.packBasisAmount ?? 0) > 0
            ? draft.keepAsMeasure
            : null,
      ),
    );
  }
  return ReceiptWrite(
    store: store.trim(),
    purchasedAt: purchasedAt,
    subtotalCents: subtotalCents,
    taxCents: taxCents,
    totalCents: totalCents,
    lines: lines,
  );
}

/// The wire kind as the column stores it. They are the same four words; the
/// two enums stay apart because one is a payload's vocabulary and the other
/// is the ledger's.
ReceiptLineKind _kindOf(ReceiptKind kind) => switch (kind) {
  ReceiptKind.item => ReceiptLineKind.item,
  ReceiptKind.notFood => ReceiptLineKind.notFood,
  ReceiptKind.tax => ReceiptLineKind.tax,
  ReceiptKind.fee => ReceiptLineKind.fee,
};
