/// What Save writes: one `receipt` and every line it kept, in one transaction.
/// Pure Dart. The mapping is a pure function so its rules can be tested without
/// a database. Nothing is written until Save.
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
    this.namePrinted,
    this.count = 1,
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

  /// The paper's words for the thing, figures removed: the unmatched card's
  /// title and the recall key for past answers. Inserted with the line; no edit
  /// moves it.
  final String? namePrinted;
  final int cents;

  /// How many of the thing rang up on this line. Only a food line is counted:
  /// the count divides a price, and a bag fee prices nothing.
  final int count;
  final int discountCents;
  final ReceiptLineKind kind;
  final String? ingredientId;
  final double? packBasisAmount;
  final double? packAmount;
  final String? packUnitId;
  final String? measureId;

  /// A word to mint on [ingredientId] as a measure weighing [packBasisAmount]
  /// before this line is written (the *keep as a measure* toggle). The line
  /// then points at the new measure. Null on every other line.
  final String? mintMeasureLabel;
}

/// One `receipt` row and its lines.
@immutable
class ReceiptWrite {
  const ReceiptWrite({
    required this.store,
    required this.purchasedAt,
    required this.lines,
    this.droppedLineIds = const [],
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

  /// The stored lines the person dropped. Named rather than inferred from
  /// absence, because a line missing from [lines] may only be unsynced.
  final List<String> droppedLineIds;
}

/// The review, as rows. A dropped line is absent from the lines and named in
/// [ReceiptWrite.droppedLineIds] when a stored row is behind it. A non-food
/// line carries no ingredient, no pack and no count.
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
        namePrinted: draft.namePrinted,
        cents: draft.cents,
        count: food ? draft.count : 1,
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
    droppedLineIds: [
      for (final draft in drafts)
        if (draft.dropped && draft.lineId != null) draft.lineId!,
    ],
  );
}

/// The wire kind as the column stores it. Same four words; one enum is the
/// payload's, the other the ledger's.
ReceiptLineKind _kindOf(ReceiptKind kind) => switch (kind) {
  ReceiptKind.item => ReceiptLineKind.item,
  ReceiptKind.notFood => ReceiptLineKind.notFood,
  ReceiptKind.tax => ReceiptLineKind.tax,
  ReceiptKind.fee => ReceiptLineKind.fee,
};
