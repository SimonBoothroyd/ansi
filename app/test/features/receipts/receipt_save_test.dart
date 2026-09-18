/// What Save writes, as a pure mapping.
///
/// Three rules are pinned here and all three are about what a row may carry:
/// a dropped line is simply absent, a folded line keeps **no ingredient and
/// no pack**, and a by-weight line stores the printed weight AS the pack — in
/// both denominations, because the ledger prints one and derives from the
/// other.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/receipts/domain/receipt_payload.dart';
import 'package:ansi/features/receipts/domain/receipt_review.dart';
import 'package:ansi/features/receipts/domain/receipt_save.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptLineDraft draft({
  int index = 0,
  String printed = 'TJ ORG BANANAS  3.49',
  int cents = 349,
  int discountCents = 0,
  ReceiptKind kind = ReceiptKind.item,
  String? ingredientId,
  double? packBasis,
  double? packAmount,
  Unit? packUnit,
  String? measureId,
  String? keepAsMeasure,
  bool dropped = false,
}) => ReceiptLineDraft(
  index: index,
  printedText: printed,
  cents: cents,
  discountCents: discountCents,
  kind: kind,
  ingredientId: ingredientId,
  packBasisAmount: packBasis,
  packAmount: packAmount,
  packUnit: packUnit,
  measureId: measureId,
  keepAsMeasure: keepAsMeasure,
  dropped: dropped,
);

ReceiptWrite saveOf(List<ReceiptLineDraft> drafts) => buildReceiptSave(
  store: "  TJ's  ",
  purchasedAt: DateTime(2026, 9, 13, 17, 42),
  drafts: drafts,
  subtotalCents: 2846,
  taxCents: 82,
  totalCents: 2928,
);

void main() {
  test('the receipt keeps the paper’s own figures, and the store trimmed', () {
    final write = saveOf([draft(ingredientId: 'b', packBasis: 454)]);
    expect(write.store, "TJ's");
    expect(write.purchasedAt, DateTime(2026, 9, 13, 17, 42));
    expect(write.subtotalCents, 2846);
    expect(write.taxCents, 82);
    expect(write.totalCents, 2928);
  });

  test('a matched, packed line is written as a price', () {
    final line = saveOf([
      draft(
        ingredientId: 'b',
        packBasis: 454,
        packAmount: 1,
        measureId: 'm-bag',
      ),
    ]).lines.single;
    expect(line.kind, ReceiptLineKind.item);
    expect(line.ingredientId, 'b');
    expect(line.packBasisAmount, 454);
    expect(line.packAmount, 1);
    expect(line.packUnitId, isNull);
    expect(line.measureId, 'm-bag');
  });

  test('a by-weight line stores the printed weight as the pack', () {
    final line = saveOf([
      draft(
        printed: 'YELLOW ONIONS  1.32 lb @ 1.99/lb  2.63',
        cents: 263,
        ingredientId: 'onion',
        packBasis: 598.74,
        packAmount: 1.32,
        packUnit: lb,
      ),
    ]).lines.single;
    expect(line.packBasisAmount, 598.74, reason: 'what every figure reads');
    expect(line.packAmount, 1.32, reason: 'what the paper printed');
    expect(line.packUnitId, 'lb');
    expect(line.measureId, isNull);
  });

  test('a discount stays beside the cents, so both printed figures live', () {
    final line = saveOf([
      draft(cents: 604, discountCents: 55, ingredientId: 's', packBasis: 500),
    ]).lines.single;
    expect(line.cents, 604);
    expect(line.discountCents, 55);
  });

  test('a folded line keeps its cents and loses everything else', () {
    // It counts toward what the trip cost and toward nothing else; a price
    // hanging off a bag fee would be a price nobody could explain.
    final line = saveOf([
      draft(
        printed: 'PAPER TOWELS  6.99',
        cents: 699,
        kind: ReceiptKind.notFood,
        ingredientId: 'stale-match',
        packBasis: 100,
        packAmount: 1,
        packUnit: lb,
        keepAsMeasure: 'roll',
      ),
    ]).lines.single;
    expect(line.kind, ReceiptLineKind.notFood);
    expect(line.cents, 699);
    expect(line.ingredientId, isNull);
    expect(line.packBasisAmount, isNull);
    expect(line.packAmount, isNull);
    expect(line.packUnitId, isNull);
    expect(line.measureId, isNull);
    expect(line.mintMeasureLabel, isNull);
  });

  test('the tax line is kept, so the paper is kept whole', () {
    final line = saveOf([
      draft(printed: 'TAX  0.82', cents: 82, kind: ReceiptKind.tax),
    ]).lines.single;
    expect(line.kind, ReceiptLineKind.tax);
    expect(line.cents, 82);
  });

  test('a dropped line is absent, and the rest keep a contiguous order', () {
    final write = saveOf([
      draft(ingredientId: 'a', packBasis: 100),
      draft(index: 1, ingredientId: 'b', dropped: true),
      draft(index: 2, ingredientId: 'c', packBasis: 100),
    ]);
    expect(write.lines, hasLength(2));
    expect(write.lines.map((l) => l.sortOrder), [0, 1]);
  });

  test('keep as a measure rides only a matched, packed food line', () {
    final kept = saveOf([
      draft(
        ingredientId: 'sriracha',
        packBasis: 482,
        packAmount: 482,
        packUnit: g,
        keepAsMeasure: 'bottle',
      ),
    ]).lines.single;
    expect(kept.mintMeasureLabel, 'bottle');

    final unpacked = saveOf([
      draft(ingredientId: 'sriracha', keepAsMeasure: 'bottle'),
    ]).lines.single;
    expect(
      unpacked.mintMeasureLabel,
      isNull,
      reason: 'there is no weight to mint the word against',
    );
  });

  test('every wire kind maps onto its stored twin', () {
    for (final (wire, stored) in const [
      (ReceiptKind.item, ReceiptLineKind.item),
      (ReceiptKind.notFood, ReceiptLineKind.notFood),
      (ReceiptKind.tax, ReceiptLineKind.tax),
      (ReceiptKind.fee, ReceiptLineKind.fee),
    ]) {
      expect(saveOf([draft(kind: wire)]).lines.single.kind, stored);
    }
  });
}
