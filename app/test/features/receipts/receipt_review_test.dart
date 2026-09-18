/// The review's one map: the flags, the sums, the join and what Save is
/// called.
///
/// Everything the screen says is read from here, which is the point — the
/// header cannot say three while the button says two — so this is where the
/// rules are pinned.
library;

import 'dart:convert';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/receipts/data/sample_receipt_payloads.dart';
import 'package:ansi/features/receipts/domain/receipt_payload.dart';
import 'package:ansi/features/receipts/domain/receipt_review.dart';
import 'package:flutter_test/flutter_test.dart';

const bananas = Ingredient(
  id: 'vocab-banana',
  canonicalName: 'Bananas, organic',
  defaultUnit: g,
  status: IngredientStatus.complete,
  source: 'seed',
);

/// A per-100 ml row with no density: a pack said in POUNDS crosses the
/// mass↔volume boundary, and that crosses only through a density.
const oil = Ingredient(
  id: 'vocab-oil',
  canonicalName: 'Olive oil',
  defaultUnit: ml,
  macrosBasis: MacrosBasis.perMl,
  status: IngredientStatus.complete,
  source: 'seed',
);

const bag = Measure(id: 'm-bag', label: 'bag', amount: 454);

ReceiptPayload sample([String? json]) => ReceiptPayload.fromJson(
  Map<String, Object?>.from(jsonDecode(json ?? sampleReceiptJson) as Map),
);

ReceiptLineDraft item({
  int index = 0,
  int cents = 349,
  int discountCents = 0,
  String? ingredientId,
  double? pack,
  ReceiptKind kind = ReceiptKind.item,
  ReceiptWeight? weight,
  bool dropped = false,
}) => ReceiptLineDraft(
  index: index,
  printedText: 'TJ ORG BANANAS  3.49',
  cents: cents,
  discountCents: discountCents,
  kind: kind,
  weight: weight,
  ingredientId: ingredientId,
  packBasisAmount: pack,
  dropped: dropped,
);

void main() {
  group('a line says what it still wants', () {
    test('food nobody has named wants a match', () {
      expect(receiptLineIssues(item()), [ReceiptLineIssue.unmatched]);
      expect(
        receiptAttentionLabel(receiptLineIssues(item())),
        'Match an ingredient',
      );
    });

    test('matched food with no pack wants one', () {
      final draft = item(ingredientId: 'vocab-banana');
      expect(receiptLineIssues(draft), [ReceiptLineIssue.packMissing]);
      expect(
        receiptAttentionLabel(receiptLineIssues(draft)),
        'Say what the pack is',
      );
    });

    test('matched and packed wants nothing', () {
      expect(
        receiptLineIssues(item(ingredientId: 'vocab-banana', pack: 454)),
        isEmpty,
      );
    });

    test('a figure the reader could not make out wants reading', () {
      // Never a free line that quietly counts as $0 — it is a line somebody
      // has to read off the paper.
      final draft = item(ingredientId: 'vocab-banana', cents: 0);
      expect(
        receiptLineIssues(draft),
        contains(ReceiptLineIssue.amountMissing),
      );
      expect(receiptAttentionLabel(receiptLineIssues(draft)), 'Set the amount');
      expect(
        receiptLineIssues(draft),
        isNot(contains(ReceiptLineIssue.packMissing)),
        reason: 'a pack is only owed by a line with a figure to divide',
      );
    });

    test('a line that is not food, and a dropped one, want nothing', () {
      expect(receiptLineIssues(item(kind: ReceiptKind.notFood)), isEmpty);
      expect(receiptLineIssues(item(kind: ReceiptKind.tax)), isEmpty);
      expect(receiptLineIssues(item(dropped: true)), isEmpty);
    });

    test('only a matched, packed, paid food line is a price', () {
      expect(item(ingredientId: 'vocab-banana', pack: 454).isPrice, isTrue);
      expect(item(ingredientId: 'vocab-banana').isPrice, isFalse);
      expect(item(pack: 454).isPrice, isFalse);
      expect(
        item(ingredientId: 'vocab-banana', pack: 454, cents: 0).isPrice,
        isFalse,
      );
      expect(
        item(
          ingredientId: 'vocab-banana',
          pack: 454,
          kind: ReceiptKind.notFood,
        ).isPrice,
        isFalse,
      );
    });
  });

  group('the pack a line can state without asking', () {
    test('the paper’s printed weight IS the pack', () {
      final draft = landPack(
        item(
          ingredientId: 'vocab-banana',
          cents: 263,
          weight: const ReceiptWeight(amount: 1, unit: lb, rateCents: 199),
        ),
        ingredient: bananas,
      );
      expect(draft.packBasisAmount, closeTo(453.6, 0.1));
      expect(draft.packAmount, 1);
      expect(draft.packUnit, lb);
      expect(receiptLineIssues(draft), isEmpty);
    });

    test('a weight the row cannot carry leaves the line asking', () {
      // A volume weight on a ml-basis row is fine; a MASS one is not, without
      // a density. The refusal is the price sheet's own gate.
      final draft = landPack(
        item(
          ingredientId: 'vocab-oil',
          weight: const ReceiptWeight(amount: 2, unit: lb, rateCents: 199),
        ),
        ingredient: oil,
      );
      expect(draft.packBasisAmount, isNull);
      expect(receiptLineIssues(draft), [ReceiptLineIssue.packMissing]);
    });

    test('with no printed weight it opens on the pack last bought', () {
      final draft = landPack(
        item(ingredientId: 'vocab-banana', cents: 399),
        ingredient: bananas,
        measures: const [bag],
        last: PriceObservation(
          lineId: 'l-old',
          receiptId: 'r-old',
          cents: 349,
          packBasisAmount: 454,
          basis: MacrosBasis.perG,
          store: "TJ's",
          purchasedAt: DateTime(2026, 8),
          packAmount: 1,
          measureId: 'm-bag',
        ),
      );
      expect(draft.packBasisAmount, 454);
      expect(draft.packAmount, 1);
      expect(draft.measureId, 'm-bag');
      expect(draft.packLabel, 'bag', reason: 'the measure’s own word');
      expect(receiptLineIssues(draft), isEmpty);
      expect(
        packAndUnitPrice(draft, basis: MacrosBasis.perG),
        'bag (454 g) · 88¢ / 100 g',
        reason: 'this receipt’s cents over last month’s pack',
      );
    });

    test('nothing to go on leaves the line asking, and invents no pack', () {
      final draft = landPack(
        item(ingredientId: 'vocab-banana'),
        ingredient: bananas,
      );
      expect(draft.packBasisAmount, isNull);
      expect(receiptLineIssues(draft), [ReceiptLineIssue.packMissing]);
    });

    test('a line that is not food lands no pack at all', () {
      final draft = landPack(
        item(
          kind: ReceiptKind.notFood,
          weight: const ReceiptWeight(amount: 1, unit: lb),
        ),
        ingredient: bananas,
      );
      expect(draft.packBasisAmount, isNull);
    });
  });

  group('the map', () {
    List<ReceiptLineDraft> drafts() => initialReceiptDrafts(sample());

    test('the lines sum excludes tax and includes what is not food', () {
      final map = receiptReviewMap(drafts());
      // 349 + 263 + 549 + 399 + 379 + 198 + 699 + 10
      expect(map.linesCents, 2846);
      expect(map.foldedCents, 709);
      expect(map.foldedCount, 2);
      expect(foldedHeading(map), r'Not food · 2 · $7.09');
    });

    test('the printed tax wins over the tax line that was read', () {
      final map = receiptReviewMap(drafts(), printedTaxCents: 90);
      expect(map.taxCents, 90);
      expect(taxHeading(map), 'Tax · 90¢');
    });

    test('a dropped line leaves every figure', () {
      final kept = [
        for (final d in drafts())
          if (d.index == 0) d.copyWith(dropped: true) else d,
      ];
      expect(receiptReviewMap(kept).linesCents, 2846 - 349);
    });

    test('the join closes when the paper agrees', () {
      final map = receiptReviewMap(
        drafts(),
        printedSubtotalCents: 2846,
        printedTotalCents: 2928,
      );
      expect(map.joinCloses, isTrue);
      expect(map.apartCents, isNull);
      expect(joinSumLine(map), r'The lines add up to $28.46');
      expect(joinNote(map), 'the receipt says the same');
    });

    test('the join is a flag, and says how far apart and what to look for', () {
      final map = receiptReviewMap(
        drafts(),
        printedSubtotalCents: 3195,
        printedTotalCents: 3277,
      );
      expect(map.joinCloses, isFalse);
      expect(map.apartCents, 349);
      expect(
        joinNote(map),
        r'$3.49 apart · Find the join — a line is missing or doubled',
      );
      expect(
        map.headerCount,
        map.outstanding + 1,
        reason: 'the header counts it',
      );
    });

    test('no printed subtotal is nothing to disagree with', () {
      final map = receiptReviewMap(drafts());
      expect(map.joinCloses, isTrue);
      expect(joinNote(map), 'the receipt printed no subtotal');
    });

    test('Save is gated on the lines, never on the join', () {
      final answered = [
        for (final d in drafts())
          if (d.kind.isFood)
            d.copyWith(ingredientId: 'x', packBasisAmount: 100)
          else
            d,
      ];
      final map = receiptReviewMap(
        answered,
        printedSubtotalCents: 3195,
        printedTotalCents: 3277,
      );
      expect(map.outstanding, 0);
      expect(map.canSave, isTrue, reason: 'the printed total is the paper’s');
      expect(map.headerCount, 1, reason: 'but somebody should still look');
      expect(receiptSaveLabel(map), r'Save receipt · $32.77');
    });

    test('Save says how many lines still need you', () {
      final map = receiptReviewMap(drafts());
      // Four food lines: two by weight with no match resolved… all six want
      // something at arrival, before any pack is landed.
      expect(receiptSaveLabel(map), '${map.outstanding} line(s) need you');
      expect(map.outstanding, 6);
    });

    test('the total falls back to the lines when nothing printed one', () {
      final map = receiptReviewMap(drafts(), printedTaxCents: 82);
      expect(map.totalCents, 2928);
    });
  });

  group('what a card prints', () {
    test('a pack typed as a plain amount reads as itself', () {
      final draft = item(
        ingredientId: 'vocab-banana',
        pack: 454,
      ).copyWith(packAmount: 1, packUnit: lb);
      expect(packWords(draft, basis: MacrosBasis.perG), '1 lb');
      expect(
        packAndUnitPrice(draft, basis: MacrosBasis.perG),
        '1 lb · 77¢ / 100 g',
      );
    });

    test('a deduction is named on the line it was taken off', () {
      expect(discountWords(item(cents: 604, discountCents: 55)), '−55¢ off');
      expect(discountWords(item()), isNull);
    });

    test('a line with no pack has no chain to print', () {
      expect(
        packAndUnitPrice(
          item(ingredientId: 'vocab-banana'),
          basis: MacrosBasis.perG,
        ),
        isNull,
      );
    });
  });

  test(
    'a suggest match starts the line unmatched — an offer, not a choice',
    () {
      final drafts = initialReceiptDrafts(sample());
      expect(drafts[0].ingredientId, 'vocab-banana');
      expect(drafts[4].ingredientId, isNull);
      expect(drafts[4].suggestions, hasLength(2));
    },
  );
}
