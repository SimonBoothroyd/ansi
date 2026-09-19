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
  String? namePrinted,
}) => ReceiptLineDraft(
  index: index,
  printedText: 'TJ ORG BANANAS  3.49',
  namePrinted: namePrinted,
  cents: cents,
  discountCents: discountCents,
  kind: kind,
  weight: weight,
  ingredientId: ingredientId,
  packBasisAmount: pack,
  dropped: dropped,
);

/// A pack the household has already bought, as every price read hands it over.
PriceObservation bought(
  double basisAmount, {
  double? amount,
  Unit? unit,
  String? measureId,
  String store = "TJ's",
  int cents = 349,
  DateTime? on,
}) => PriceObservation(
  lineId: 'l-$basisAmount',
  receiptId: 'r-$basisAmount',
  cents: cents,
  packBasisAmount: basisAmount,
  basis: MacrosBasis.perG,
  store: store,
  purchasedAt: on ?? DateTime(2026, 8),
  packAmount: amount,
  packUnit: unit,
  measureId: measureId,
);

void main() {
  group('a card is titled without the money', () {
    const printed = r'T BGT PETITE SEASONAL $4.99';
    ReceiptLineDraft line({String? name, String? matched}) => ReceiptLineDraft(
      index: 0,
      printedText: printed,
      namePrinted: name,
      ingredientName: matched,
      cents: 499,
      kind: ReceiptKind.item,
    );

    test('the paper’s name for the thing, where the server split one out', () {
      expect(
        line(name: 'T BGT PETITE SEASONAL').displayName,
        'T BGT PETITE SEASONAL',
      );
    });

    test('the whole line from a server that sends no name', () {
      expect(line().displayName, printed);
    });

    test('the matched row wins, and the edits keep the name', () {
      final named = line(name: 'T BGT PETITE SEASONAL');
      expect(line(name: 'x', matched: 'Bouquet').displayName, 'Bouquet');
      expect(named.withCents(1).namePrinted, 'T BGT PETITE SEASONAL');
      expect(
        named.copyWith(dropped: true).namePrinted,
        'T BGT PETITE SEASONAL',
      );
    });
  });

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

    group('the words on the paper are the better answer', () {
      // One store's 16 oz bag and another's 12 oz, on one row. The words name
      // the product AT A SHOP; the row's latest price names only whichever
      // shop was last.
      const quinoa = 'ORG TRICOLOR QUINOA';
      final theirs = (
        ingredientId: 'vocab-banana',
        pack: bought(454, amount: 16, unit: oz),
      );
      final lastAnywhere = bought(340, amount: 12, unit: oz, store: 'WF');

      ReceiptLineDraft landed({
        String? name = quinoa,
        PackLastBoughtAs? sameName,
        PriceObservation? last,
        ReceiptWeight? weight,
      }) => landPack(
        item(
          ingredientId: 'vocab-banana',
          cents: 449,
          namePrinted: name,
          weight: weight,
        ),
        ingredient: bananas,
        sameName: sameName,
        last: last,
      );

      test('the pack these words were last bought in beats the row’s', () {
        final draft = landed(sameName: theirs, last: lastAnywhere);
        expect(draft.packBasisAmount, 454);
        expect(draft.packAmount, 16);
        expect(draft.packUnit, oz);
      });

      test('the paper’s own printed weight still beats both', () {
        final draft = landed(
          sameName: theirs,
          last: lastAnywhere,
          weight: const ReceiptWeight(amount: 1, unit: lb, rateCents: 449),
        );
        expect(draft.packBasisAmount, closeTo(453.6, 0.1));
        expect(draft.packUnit, lb, reason: 'the paper said pounds');
      });

      test('words last bought as another row carry nothing', () {
        // Re-pointed since: the size of somebody else's pack says nothing
        // about this one, so the row's own latest price answers.
        final draft = landed(
          sameName: (ingredientId: 'vocab-oil', pack: bought(454)),
          last: lastAnywhere,
        );
        expect(draft.packBasisAmount, 340);
      });

      test('words that state no pack carry nothing, and swallow nothing', () {
        final draft = landed(
          sameName: (ingredientId: 'vocab-banana', pack: bought(0)),
          last: lastAnywhere,
        );
        expect(draft.packBasisAmount, 340);
      });

      test('a line the server printed no words for skips its own step', () {
        // An older server sends no `name_printed`: there is nothing to file a
        // pack under, so the row's latest price is the only carry-over left.
        final draft = landed(name: null, sameName: theirs, last: lastAnywhere);
        expect(draft.packBasisAmount, 340);
      });

      test('words nobody has bought under fall through to the row', () {
        expect(landed(last: lastAnywhere).packBasisAmount, 340);
      });

      test('neither answers and the line asks, as it always did', () {
        final draft = landed();
        expect(draft.packBasisAmount, isNull);
        expect(receiptLineIssues(draft), [ReceiptLineIssue.packMissing]);
      });

      test('the carried basis figure is the stored one, never re-derived', () {
        // A bag re-weighed at 500 g since does not re-price this shop: what
        // the words bought is what the saved line said it bought.
        final draft = landed(
          sameName: (
            ingredientId: 'vocab-banana',
            pack: bought(454, amount: 1, measureId: 'm-bag'),
          ),
        );
        expect(draft.packBasisAmount, 454);
        expect(draft.measureId, 'm-bag');
      });
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

  group('a line the receipt printed again', () {
    // Six tubs of tofu print six identical lines, and every one of them wants
    // the same answer.
    ReceiptLineDraft tofu({
      required int index,
      String printed = 'TJ ORG TOFU FIRM  2.49',
      int cents = 249,
      int discountCents = 0,
      String? ingredientId,
      double? pack,
      String? keepAsMeasure,
      ReceiptKind kind = ReceiptKind.item,
      ReceiptWeight? weight,
      bool dropped = false,
    }) => ReceiptLineDraft(
      index: index,
      printedText: printed,
      cents: cents,
      discountCents: discountCents,
      kind: kind,
      weight: weight,
      ingredientId: ingredientId,
      packBasisAmount: pack,
      keepAsMeasure: keepAsMeasure,
      dropped: dropped,
    );

    test(
      'the twins are the lines one answer answers, and the card says so',
      () {
        final drafts = [tofu(index: 0), tofu(index: 1), tofu(index: 2)];
        expect(linesAnsweredWith(drafts, 1), {0, 1, 2});
        expect(
          sameLineAgainNote(drafts, 1),
          '×3 on this receipt — an answer here answers them all',
        );
      },
    );

    test('a line that stands alone answers for itself, and says nothing', () {
      final drafts = [tofu(index: 0), tofu(index: 1, printed: 'TJ SRIRACHA')];
      expect(linesAnsweredWith(drafts, 0), {0});
      expect(sameLineAgainNote(drafts, 0), isNull);
      expect(linesAnsweredWith(drafts, 99), {99}, reason: 'no such line');
    });

    test('a different figure is a different line', () {
      final drafts = [tofu(index: 0), tofu(index: 1, cents: 299)];
      expect(linesAnsweredWith(drafts, 0), {0});
      final discounted = [tofu(index: 0), tofu(index: 1, discountCents: 55)];
      expect(linesAnsweredWith(discounted, 0), {0});
    });

    test('a twin answered differently is left exactly as it was', () {
      // The fence that makes this safe: *standing where it stands now*. Two of
      // the six were matched to another row, and an answer on the fourth
      // cannot reach back and overwrite theirs.
      final drafts = [
        tofu(index: 0, ingredientId: 'vocab-tofu'),
        tofu(index: 1, ingredientId: 'vocab-tofu'),
        tofu(index: 2),
        tofu(index: 3),
      ];
      expect(linesAnsweredWith(drafts, 3), {2, 3});
      expect(linesAnsweredWith(drafts, 0), {0, 1});
    });

    test('a pack said one way is not a fact about a pack said another', () {
      final drafts = [
        tofu(index: 0, ingredientId: 'vocab-tofu', pack: 396),
        tofu(index: 1, ingredientId: 'vocab-tofu', pack: 454),
        tofu(index: 2, ingredientId: 'vocab-tofu', pack: 396),
      ];
      expect(linesAnsweredWith(drafts, 0), {0, 2});
    });

    test('a word kept as a measure on one is not kept on the other', () {
      final drafts = [
        tofu(index: 0, ingredientId: 'vocab-tofu', pack: 396),
        tofu(
          index: 1,
          ingredientId: 'vocab-tofu',
          pack: 396,
          keepAsMeasure: 'tub',
        ),
      ];
      expect(linesAnsweredWith(drafts, 0), {0});
    });

    test(
      'a folded line rides with the other folded lines, never with an item',
      () {
        final drafts = [
          tofu(index: 0, kind: ReceiptKind.notFood),
          tofu(index: 1, kind: ReceiptKind.notFood),
          tofu(index: 2),
        ];
        expect(linesAnsweredWith(drafts, 0), {0, 1});
        expect(linesAnsweredWith(drafts, 2), {2});
      },
    );

    test('a dropped line is nobody’s twin, in either direction', () {
      // It is leaving, and a doubled line is dropped precisely BECAUSE the
      // other one is staying.
      final drafts = [
        tofu(index: 0),
        tofu(index: 1, dropped: true),
        tofu(index: 2),
      ];
      expect(linesAnsweredWith(drafts, 0), {0, 2});
      expect(linesAnsweredWith(drafts, 1), {1});
    });

    test('a line sold by weight answers for itself', () {
      // Its printed weight IS its pack, so a pack said on one is not a fact
      // about the other, however alike the two read.
      const weighed = ReceiptWeight(amount: 1.32, unit: lb, rateCents: 199);
      final drafts = [
        tofu(index: 0, printed: 'ONIONS 1.32 lb', weight: weighed),
        tofu(index: 1, printed: 'ONIONS 1.32 lb', weight: weighed),
      ];
      expect(linesAnsweredWith(drafts, 0), {0});
      expect(sameLineAgainNote(drafts, 0), isNull);
    });

    test('a line the reader read no words off is nobody’s twin', () {
      final drafts = [tofu(index: 0, printed: ''), tofu(index: 1, printed: '')];
      expect(linesAnsweredWith(drafts, 0), {0});
    });
  });

  group('a match the household has already made', () {
    ReceiptPayload payloadWith(Map<String, Object?> match) =>
        ReceiptPayload.fromJson({
          'lines': [
            {
              'index': 0,
              'printed_text': 'ORG TRICOLOR QUINOA  4.49',
              'name_printed': 'ORG TRICOLOR QUINOA',
              'cents': 449,
              'kind': 'item',
              'match': match,
            },
          ],
        });

    test('arrives resolved, and says it is the household’s own', () {
      // The line the cascade could not place: a whole-string trigram cannot
      // score four of a store's abbreviations against `Quinoa`. Once somebody
      // has said it, it does not have to.
      final draft = initialReceiptDrafts(
        payloadWith(const {
          'ingredient_id': 'vocab-quinoa',
          'confidence': 1,
          'kind': 'auto',
          'remembered': true,
        }),
      ).single;
      expect(draft.ingredientId, 'vocab-quinoa');
      expect(draft.remembered, isTrue);
    });

    test('the cascade’s own auto is not remembered', () {
      final draft = initialReceiptDrafts(
        payloadWith(const {
          'ingredient_id': 'vocab-quinoa',
          'confidence': 0.91,
          'kind': 'auto',
        }),
      ).single;
      expect(draft.ingredientId, 'vocab-quinoa');
      expect(draft.remembered, isFalse);
    });

    test('a suggestion is an offer whoever made it', () {
      // `suggest` never starts a line resolved (ADR-0004), so there is nothing
      // for the note to be about either.
      final draft = initialReceiptDrafts(
        payloadWith(const {
          'ingredient_id': 'vocab-quinoa',
          'confidence': 0.6,
          'kind': 'suggest',
          'remembered': true,
        }),
      ).single;
      expect(draft.ingredientId, isNull);
      expect(draft.remembered, isFalse);
    });

    test('a match the person changes is theirs now', () {
      final draft = item(ingredientId: 'vocab-banana').copyWith();
      const recalled = ReceiptLineDraft(
        index: 0,
        printedText: 'x',
        cents: 1,
        kind: ReceiptKind.item,
        ingredientId: 'vocab-banana',
        remembered: true,
      );
      expect(
        recalled
            .copyWith(clearMatch: true)
            .copyWith(ingredientId: 'vocab-oil')
            .remembered,
        isFalse,
      );
      // A correction to the PAPER says nothing about where the match came
      // from, so it survives one.
      expect(recalled.withCents(299).remembered, isTrue);
      expect(recalled.copyWith(dropped: true).remembered, isTrue);
      expect(draft.remembered, isFalse);
    });

    test('the pack lands on it exactly as on any other auto match', () {
      // So a remembered line whose row has a remembered pack arrives needing
      // nothing at all.
      final landed = landPack(
        const ReceiptLineDraft(
          index: 0,
          printedText: 'ORG TRICOLOR QUINOA  4.49',
          cents: 449,
          kind: ReceiptKind.item,
          ingredientId: 'vocab-banana',
          remembered: true,
        ),
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
      expect(landed.packBasisAmount, 454);
      expect(landed.remembered, isTrue);
      expect(receiptLineIssues(landed), isEmpty);
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
        r'$3.49 apart · Find the join — a line is missing, doubled or '
        'misread',
      );
      expect(
        map.headerCount,
        map.outstanding + 1,
        reason: 'the header counts it',
      );
    });

    test('a paper that printed neither figure is nothing to disagree with', () {
      final map = receiptReviewMap(drafts());
      expect(map.joinCloses, isTrue);
      expect(joinNote(map), 'the receipt printed no subtotal and no total');
    });

    test('with no subtotal the lines are held against the total less tax', () {
      final closes = receiptReviewMap(
        drafts(),
        printedTaxCents: 82,
        printedTotalCents: 2846 + 82,
      );
      expect(closes.expectedLinesCents, 2846);
      expect(closes.joinCloses, isTrue);
      expect(joinNote(closes), 'the receipt’s total less tax says the same');

      // The strip this was found on: lines at $96.62 under a printed total of
      // $91.54 with 65¢ of tax, and a green tick beside the sum.
      final apart = receiptReviewMap(
        drafts(),
        printedTaxCents: 65,
        printedTotalCents: 2846 - 573 + 65,
      );
      expect(apart.joinCloses, isFalse);
      expect(apart.apartCents, 573);
      expect(apart.headerCount, apart.outstanding + 1);
      expect(
        joinNote(apart),
        r'$5.73 apart from the total less tax ($22.73) · Find the join — a '
        'line is missing, doubled or misread',
      );
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

    test('a pack whose word already says its size says it once (owner)', () {
      final draft = item(
        ingredientId: 'vocab-banana',
        pack: 411,
      ).copyWith(packAmount: 1, measureId: 'm-can', packLabel: 'can (14.5 oz)');
      expect(packWords(draft, basis: MacrosBasis.perG), 'can (14.5 oz)');
      expect(
        packAndUnitPrice(draft, basis: MacrosBasis.perG),
        'can (14.5 oz) · 85¢ / 100 g',
      );
      // A word that says nothing about size still earns the weight.
      expect(
        packWords(draft.copyWith(packLabel: 'jar'), basis: MacrosBasis.perG),
        'jar (411 g)',
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
