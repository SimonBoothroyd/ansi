/// The review screen, driven through the real controller and the replay
/// payload.
///
/// What is pinned here is that the screen says **one thing**: the header
/// count, the card flags, the join card and Save all read the same map, and
/// a line answered anywhere moves all four.
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/receipts/data/sample_receipt_payloads.dart';
import 'package:ansi/features/receipts/domain/receipt_repository.dart';
import 'package:ansi/features/receipts/domain/receipt_review.dart';
import 'package:ansi/features/receipts/presentation/receipt_date_sheet.dart';
import 'package:ansi/features/receipts/presentation/receipt_review_body.dart';
import 'package:ansi/features/receipts/presentation/receipt_view_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_price_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_harness.dart';

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(FScaffold).first),
  listen: false,
);

void main() {
  testWidgets('the reading checklist names the four receipt stages', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(
      scanHost(
        overrides: receiptOverrides(pace: const Duration(milliseconds: 20)),
      ),
    );
    await tester.pumpAndSettle();
    // Started, but not awaited: the checklist is what is on screen while the
    // server is still reading.
    unawaitedScan(containerOf(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    // The tense is the row's own: what happened, what is happening, and the
    // plan read muted.
    expect(find.text('Photos received'), findsOneWidget);
    expect(find.text('Reading the photos…'), findsOneWidget);
    expect(find.text('Receipt written out'), findsOneWidget);
    expect(find.text('Lines matched'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('the intake carries the overlap guidance', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
    await tester.pumpAndSettle();
    expect(find.textContaining('two or three shots'), findsOneWidget);
    expect(find.textContaining('overlapping a few lines'), findsOneWidget);
    expect(find.text('Scan a receipt'), findsOneWidget);
  });

  group('the review', () {
    testWidgets('a clean line reads money first, with its whole chain', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      expect(find.text('Review receipt'), findsOneWidget);
      // A by-weight line prices itself from the printed weight: no pack door.
      expect(find.text(r'$2.63'), findsOneWidget);
      expect(find.text('Yellow onion'), findsOneWidget);
      expect(find.textContaining('1.32 lb · '), findsOneWidget);
      // The deduction is named on the line it came off.
      expect(find.textContaining('−55¢ off'), findsOneWidget);
    });

    testWidgets('a matched line with no pack asks for one', (tester) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      expect(find.text('Sriracha'), findsOneWidget);
      expect(find.text('Say what the pack is'), findsWidgets);
    });

    testWidgets('an unmatched line offers the chips, the picker and Not food', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      expect(find.text('Match an ingredient'), findsWidgets);
      await tester.tap(find.text('TJ MED CHDR SHRD'));
      await tester.pumpAndSettle();
      expect(find.text('DID YOU MEAN'), findsOneWidget);
      expect(find.text('Cheddar'), findsOneWidget);
      expect(find.text('Cheddar, mild'), findsOneWidget);
      expect(find.text('Something else'), findsOneWidget);
      expect(find.text('Not food'), findsWidgets);
    });

    testWidgets('a did-you-mean chip resolves the line to that row', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      await tester.tap(find.text('TJ MED CHDR SHRD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheddar'));
      await tester.pumpAndSettle();

      final state =
          container.read(receiptScanControllerProvider) as ReceiptReviewing;
      final line = state.drafts.firstWhere((d) => d.index == 4);
      expect(line.ingredientId, 'vocab-cheddar');
      expect(line.ingredientName, 'Cheddar');
    });

    testWidgets('Not food folds the line under the list, with the way back', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      expect(find.text(r'Not food · 2 · $7.09'), findsOneWidget);
      expect(find.text('PAPER TOWELS  6.99'), findsOneWidget);
      expect(find.text('it is food'), findsWidgets);

      container.read(receiptScanControllerProvider.notifier).unfold(6);
      await tester.pumpAndSettle();
      expect(find.text('Not food · 1 · 10¢'), findsOneWidget);
    });

    testWidgets('the tax line is folded too, and never a price', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));
      expect(find.text('Tax · 82¢'), findsOneWidget);
    });

    testWidgets('the join card closes when the paper agrees', (tester) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      expect(find.byKey(kReceiptJoinKey), findsOneWidget);
      expect(find.text(r'The lines add up to $28.46'), findsOneWidget);
      expect(find.text('the receipt says the same'), findsOneWidget);
    });

    testWidgets('the join card flags a sum that is short, and still saves', (
      tester,
    ) async {
      final ledger = FakeReceiptRepo();
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(
          overrides: receiptOverrides(
            ledger: ledger,
            json: sampleReceiptJoinApartJson,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      expect(
        find.textContaining(
          r'$3.49 apart · Find the join — a line is missing, doubled or '
          'misread',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('The receipt saves either way'),
        findsOneWidget,
      );

      await answerEveryLine(tester, container);
      expect(find.text(r'Save receipt · $32.77'), findsOneWidget);
      // The header still counts the join, because somebody should look.
      expect(find.text('1 to review'), findsOneWidget);
    });

    testWidgets('the header, the flags and Save read one map', (tester) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      expect(find.text('4 to review'), findsOneWidget);
      expect(find.text('4 line(s) need you'), findsOneWidget);

      await answerEveryLine(tester, container);

      expect(find.text('looks good'), findsOneWidget);
      expect(find.text(r'Save receipt · $29.28'), findsOneWidget);
    });

    testWidgets('a dropped line greys out, leaves the count, and undoes', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      container.read(receiptScanControllerProvider.notifier).drop(5);
      await tester.pumpAndSettle();
      expect(find.textContaining('— dropped'), findsOneWidget);

      final dropped =
          (container.read(receiptScanControllerProvider) as ReceiptReviewing)
              .map;
      expect(
        dropped.outstanding,
        3,
        reason: 'the line stops being anybody’s problem',
      );
      // …and the receipt stops adding up, which is the join card's whole job:
      // a line the paper printed has left the sum, and it says so.
      expect(dropped.joinCloses, isFalse);
      expect(dropped.apartCents, 198);
      expect(dropped.headerCount, 4);

      await tester.tap(find.text('undo'));
      await tester.pumpAndSettle();
      expect(find.text('4 to review'), findsOneWidget);
      expect(
        (container.read(receiptScanControllerProvider) as ReceiptReviewing)
            .map
            .joinCloses,
        isTrue,
      );
    });

    testWidgets('the store is a chip over the paper’s own words', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      expect(find.text("TJ's"), findsWidgets);
      expect(find.text('Whole Foods'), findsWidgets);
      expect(
        find.textContaining("from receipt:  TRADER JOE'S #135"),
        findsOneWidget,
      );
    });

    testWidgets('an unnamed store holds Save, whatever the lines say', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(overrides: receiptOverrides(prices: FakePriceRepo())),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      await answerEveryLine(tester, container);

      expect(find.text('Say which shop this was'), findsOneWidget);
      final save = tester.widget<FButton>(find.byKey(kReceiptSaveKey));
      expect(save.onPress, isNull);
    });

    testWidgets('Bought is the receipt’s own date, and says so', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      expect(find.text('Sunday 13 Sep · 17:42'), findsOneWidget);
      expect(
        find.textContaining('the receipt’s own date, not the scan’s'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Bought is a door: a picked day moves the date, not the clock',
      (tester) async {
        final ledger = FakeReceiptRepo();
        tallSurface(tester);
        await tester.pumpWidget(
          scanHost(overrides: receiptOverrides(ledger: ledger)),
        );
        await tester.pumpAndSettle();
        final container = containerOf(tester);
        await runTheScan(tester, container);

        await tester.tap(find.byKey(kReceiptBoughtKey));
        await tester.pumpAndSettle();
        expect(find.text('When was this shop'), findsOneWidget);
        await tester.tap(
          find
              .descendant(
                of: find.byKey(kReceiptDateCalendarKey),
                matching: find.text('12'),
              )
              .first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Saturday 12 Sep · 17:42'), findsOneWidget);
        expect(find.textContaining('the day you said'), findsOneWidget);

        await answerEveryLine(tester, container);
        await tester.tap(find.byKey(kReceiptSaveKey));
        await tester.pumpAndSettle();
        expect(ledger.saved.single.purchasedAt, DateTime(2026, 9, 12, 17, 42));
      },
    );

    testWidgets('a figure read wrong is put right on the line', (tester) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      final before =
          (container.read(receiptScanControllerProvider) as ReceiptReviewing)
              .map
              .linesCents;

      await tester.tap(find.text('TJ MED CHDR SHRD'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-line-price-4')));
      await tester.pumpAndSettle();
      // The prompt opens on what was read.
      expect(find.text('3.79'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(FDialog),
          matching: find.byType(EditableText),
        ),
        '3.99',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Use it'));
      await tester.pumpAndSettle();

      final state =
          container.read(receiptScanControllerProvider) as ReceiptReviewing;
      expect(state.drafts.firstWhere((d) => d.index == 4).cents, 399);
      expect(state.map.linesCents, before + 20, reason: 'the join moves too');
    });

    testWidgets('what the reader could not read heads the screen', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(scanHost(overrides: receiptOverrides()));
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));
      expect(find.text('What we could not read'), findsOneWidget);
      expect(
        find.textContaining('The join between the second and third photo'),
        findsOneWidget,
      );
    });
  });

  group('a line the receipt printed again', () {
    // The owner's first real strip printed six tofu lines. Two of these four
    // arrive matched by the cascade and two arrive unanswered, which is what
    // lets one group be answered without reaching into the other.
    const twinsJson = '''
{
  "store_printed": "TRADER JOE'S #135",
  "purchased_at": "2026-09-13T17:42:00",
  "printed": { "subtotal_cents": 996, "tax_cents": 0, "total_cents": 996 },
  "lines": [
    {
      "index": 0, "printed_text": "TJ ORG TOFU FIRM  2.49",
      "name_printed": "TJ ORG TOFU FIRM", "cents": 249, "kind": "item",
      "match": { "ingredient_id": "vocab-sriracha", "confidence": 0.93,
        "kind": "auto" }
    },
    {
      "index": 1, "printed_text": "TJ ORG TOFU FIRM  2.49",
      "name_printed": "TJ ORG TOFU FIRM", "cents": 249, "kind": "item",
      "match": { "ingredient_id": "vocab-sriracha", "confidence": 0.93,
        "kind": "auto" }
    },
    {
      "index": 2, "printed_text": "ORG TRICOLOR QUINOA  2.49",
      "name_printed": "ORG TRICOLOR QUINOA", "cents": 249, "kind": "item"
    },
    {
      "index": 3, "printed_text": "ORG TRICOLOR QUINOA  2.49",
      "name_printed": "ORG TRICOLOR QUINOA", "cents": 249, "kind": "item"
    }
  ]
}
''';

    Future<ProviderContainer> openTwins(WidgetTester tester) async {
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(overrides: receiptOverrides(json: twinsJson)),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      return container;
    }

    List<ReceiptLineDraft> draftsOf(ProviderContainer container) =>
        (container.read(receiptScanControllerProvider) as ReceiptReviewing)
            .drafts;

    testWidgets('the open card says so before the answer is given', (
      tester,
    ) async {
      final container = await openTwins(tester);
      expect(draftsOf(container), hasLength(4));

      await tester.tap(find.text('ORG TRICOLOR QUINOA').first);
      await tester.pumpAndSettle();
      expect(
        find.text('×2 on this receipt — an answer here answers them all'),
        findsOneWidget,
      );
    });

    testWidgets('one match answers every line that is that line again', (
      tester,
    ) async {
      final container = await openTwins(tester);
      await container
          .read(receiptScanControllerProvider.notifier)
          .matchLine(2, bananas);
      await tester.pumpAndSettle();

      final drafts = draftsOf(container);
      expect(drafts[2].ingredientId, 'vocab-banana');
      expect(drafts[3].ingredientId, 'vocab-banana');
      expect(drafts[3].ingredientName, 'Bananas, organic');
      // …and never into the pair the cascade had already placed elsewhere.
      expect(drafts[0].ingredientId, 'vocab-sriracha');
      expect(drafts[1].ingredientId, 'vocab-sriracha');
    });

    testWidgets('and so does one pack, word and all', (tester) async {
      final container = await openTwins(tester);
      final notifier = container.read(receiptScanControllerProvider.notifier);
      await notifier.matchLine(2, bananas);
      await tester.pumpAndSettle();
      notifier.setPack(
        2,
        amount: 396,
        choice: const UnitOption(g),
        basisAmount: 396,
        keepAsMeasure: 'tub',
      );
      await tester.pumpAndSettle();

      final drafts = draftsOf(container);
      expect(drafts[3].packBasisAmount, 396);
      expect(drafts[3].keepAsMeasure, 'tub');
      expect(drafts[0].packBasisAmount, isNull, reason: 'a different answer');
    });

    testWidgets('Not food folds them together, and it is food brings them '
        'back', (tester) async {
      final container = await openTwins(tester);
      final notifier = container.read(receiptScanControllerProvider.notifier)
        ..fold(2);
      await tester.pumpAndSettle();
      expect(find.text(r'Not food · 2 · $4.98'), findsOneWidget);

      notifier.unfold(3);
      await tester.pumpAndSettle();
      expect(
        foldedHeading(
          (container.read(receiptScanControllerProvider) as ReceiptReviewing)
              .map,
        ),
        isNull,
      );
    });

    testWidgets('a correction to the paper is about ONE occurrence', (
      tester,
    ) async {
      // A drop and a re-read figure are not answers: a doubled line is dropped
      // precisely because its twin is staying, and a misread `2.49` was
      // misread on the line it was misread on.
      final container = await openTwins(tester);
      final notifier = container.read(receiptScanControllerProvider.notifier)
        ..drop(2);
      await tester.pumpAndSettle();
      expect(draftsOf(container).map((d) => d.dropped), [
        false,
        false,
        true,
        false,
      ]);

      notifier.setCents(0, 299);
      await tester.pumpAndSettle();
      expect(draftsOf(container).map((d) => d.cents), [299, 249, 249, 249]);
    });
  });

  group('a match the household has already made', () {
    // The strip this came off matched 0 of 29: a whole-string trigram cannot
    // score `ORG TRICOLOR QUINOA` against `Quinoa`. The server now recalls
    // what this household said last time and the line arrives resolved.
    const rememberedJson = '''
{
  "store_printed": "TRADER JOE'S #135",
  "purchased_at": "2026-09-13T17:42:00",
  "printed": { "total_cents": 449 },
  "lines": [
    {
      "index": 0, "printed_text": "ORG TRICOLOR QUINOA  4.49",
      "name_printed": "ORG TRICOLOR QUINOA", "cents": 449, "kind": "item",
      "match": { "ingredient_id": "vocab-banana", "confidence": 1,
        "kind": "auto", "remembered": true },
      "suggestions": [
        { "ingredient_id": "vocab-cheddar", "name": "Cheddar",
          "confidence": 0.41 }
      ]
    }
  ]
}
''';

    testWidgets('the card says where the answer came from', (tester) async {
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(overrides: receiptOverrides(json: rememberedJson)),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      expect(find.text('Bananas, organic'), findsOneWidget);
      await tester.tap(find.text('Bananas, organic'));
      await tester.pumpAndSettle();
      expect(find.text('as you matched it last time'), findsOneWidget);
      expect(find.text('tap to change'), findsOneWidget);
    });

    testWidgets('changing it makes it the person’s, and the note goes', (
      tester,
    ) async {
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(overrides: receiptOverrides(json: rememberedJson)),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      await tester.tap(find.text('Bananas, organic'));
      await tester.pumpAndSettle();

      await container
          .read(receiptScanControllerProvider.notifier)
          .matchLine(0, cheddar);
      await tester.pumpAndSettle();

      final draft =
          (container.read(receiptScanControllerProvider) as ReceiptReviewing)
              .drafts
              .single;
      expect(draft.ingredientId, 'vocab-cheddar');
      expect(draft.remembered, isFalse);
      expect(find.text('as you matched it last time'), findsNothing);
    });

    testWidgets('the paper’s name for the thing rides all the way to Save', (
      tester,
    ) async {
      final ledger = FakeReceiptRepo();
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(
          overrides: receiptOverrides(ledger: ledger, json: rememberedJson),
        ),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      await answerEveryLine(tester, container);
      await tester.tap(find.byKey(kReceiptSaveKey));
      await tester.pumpAndSettle();

      // It is the key the household's own answers are filed under, so a line
      // saved without it is a line the next receipt cannot learn from.
      expect(
        ledger.saved.single.lines.single.namePrinted,
        'ORG TRICOLOR QUINOA',
      );
    });
  });

  group('Save', () {
    testWidgets('writes the receipt and opens the ledger on it', (
      tester,
    ) async {
      final ledger = FakeReceiptRepo();
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(overrides: receiptOverrides(ledger: ledger)),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      await answerEveryLine(tester, container);

      await tester.tap(find.byKey(kReceiptSaveKey));
      await tester.pumpAndSettle();

      expect(ledger.saved, hasLength(1));
      final write = ledger.saved.single;
      expect(write.store, "TJ's");
      expect(write.purchasedAt, DateTime(2026, 9, 13, 17, 42));
      expect(write.subtotalCents, 2846);
      expect(write.totalCents, 2928);
      expect(write.lines, hasLength(9), reason: 'the paper is kept whole');
      expect(find.text('receipt r-1'), findsOneWidget);
    });

    testWidgets('writes nothing while a line still needs somebody', (
      tester,
    ) async {
      final ledger = FakeReceiptRepo();
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(overrides: receiptOverrides(ledger: ledger)),
      );
      await tester.pumpAndSettle();
      await runTheScan(tester, containerOf(tester));

      final save = tester.widget<FButton>(find.byKey(kReceiptSaveKey));
      expect(save.onPress, isNull);
      expect(ledger.saved, isEmpty);
    });
  });

  group('the pack opens on the size THIS shop sells', () {
    // One row bought at two shops in two sizes. The words are each shop's own,
    // and the row's latest price knows only whichever shop was last — so the
    // proof is that the TJ's words open on the TJ's bag while the row's latest
    // price is the Whole Foods one.
    const tjWords = 'TJ ORG TOFU FIRM';
    const wfWords = 'ORGANIC TOFU, FIRM';

    PriceObservation pack(double basisAmount, double said, String store) =>
        PriceObservation(
          lineId: 'l-$store',
          receiptId: 'r-$store',
          cents: 249,
          packBasisAmount: basisAmount,
          basis: MacrosBasis.perG,
          store: store,
          purchasedAt: DateTime.utc(2026, 9),
          packAmount: said,
          packUnit: oz,
        );

    /// The Whole Foods 12 oz tub as the row's latest price, and both shops'
    /// words filed with what each of them actually sells.
    FakePriceRepo twoShops() => FakePriceRepo(
      prices: [pack(340, 12, 'Whole Foods')],
      stores: const ["TJ's", 'Whole Foods'],
      packsByName: {
        tjWords: (ingredientId: 'vocab-sriracha', pack: pack(454, 16, "TJ's")),
        wfWords: (
          ingredientId: 'vocab-sriracha',
          pack: pack(340, 12, 'Whole Foods'),
        ),
        'TJ MED CHDR SHRD': (
          ingredientId: 'vocab-cheddar',
          pack: pack(227, 8, "TJ's"),
        ),
      },
    )..ingredientId = 'vocab-sriracha';

    const twoShopsJson =
        '''
{
  "store_printed": "TRADER JOE'S #135",
  "purchased_at": "2026-09-13T17:42:00",
  "printed": { "subtotal_cents": 877, "tax_cents": 0, "total_cents": 877 },
  "lines": [
    {
      "index": 0, "printed_text": "TJ ORG TOFU FIRM  2.49",
      "name_printed": "$tjWords", "cents": 249, "kind": "item",
      "match": { "ingredient_id": "vocab-sriracha", "confidence": 0.93,
        "kind": "auto" }
    },
    {
      "index": 1, "printed_text": "TJ ORG TOFU FIRM  2.49",
      "name_printed": "$tjWords", "cents": 249, "kind": "item",
      "match": { "ingredient_id": "vocab-sriracha", "confidence": 0.93,
        "kind": "auto" }
    },
    {
      "index": 2, "printed_text": "TJ MED CHDR SHRD  3.79",
      "name_printed": "TJ MED CHDR SHRD", "cents": 379, "kind": "item"
    }
  ]
}
''';

    Future<(ProviderContainer, FakePriceRepo)> openTwoShops(
      WidgetTester tester,
    ) async {
      final prices = twoShops();
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(
          overrides: receiptOverrides(json: twoShopsJson, prices: prices),
        ),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);
      return (container, prices);
    }

    List<ReceiptLineDraft> draftsOf(ProviderContainer container) =>
        (container.read(receiptScanControllerProvider) as ReceiptReviewing)
            .drafts;

    testWidgets('a line arriving matched lands the pack its own words bought', (
      tester,
    ) async {
      final (container, prices) = await openTwoShops(tester);

      final line = draftsOf(container).first;
      expect(line.packBasisAmount, 454, reason: 'the TJ’s bag, not the WF tub');
      expect(line.packAmount, 16);
      expect(find.textContaining('16 oz · '), findsWidgets);
      expect(find.textContaining('12 oz'), findsNothing);
      // One read for the whole receipt, and only of the words it matched.
      expect(prices.asked, hasLength(1));
      expect(prices.asked.single, {tjWords});
    });

    testWidgets('twins all land the same pack', (tester) async {
      final (container, _) = await openTwoShops(tester);
      expect(draftsOf(container).take(2).map((d) => d.packBasisAmount), [
        454,
        454,
      ]);
    });

    testWidgets('and so does a line matched by hand, on its own words', (
      tester,
    ) async {
      final (container, prices) = await openTwoShops(tester);
      await container
          .read(receiptScanControllerProvider.notifier)
          .matchLine(2, cheddar);
      await tester.pumpAndSettle();

      final line = draftsOf(container).last;
      expect(line.ingredientId, 'vocab-cheddar');
      expect(line.packBasisAmount, 227, reason: 'the words, not the row');
      expect(line.packAmount, 8);
      expect(prices.asked.last, {
        'TJ MED CHDR SHRD',
      }, reason: 'the answered line’s own words, asked for once');
    });

    testWidgets('words this household has not bought under fall back', (
      tester,
    ) async {
      // The same receipt read by a server that printed no name for the thing:
      // nothing to file a pack under, so the row's latest price answers.
      final prices = twoShops();
      tallSurface(tester);
      await tester.pumpWidget(
        scanHost(
          overrides: receiptOverrides(
            json: twoShopsJson.replaceAll('"name_printed": "$tjWords",', ''),
            prices: prices,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      await runTheScan(tester, container);

      expect(draftsOf(container).first.packBasisAmount, 340);
      expect(draftsOf(container).first.packAmount, 12);
    });
  });
}

/// Starts a scan without awaiting it, so the checklist can be looked at.
void unawaitedScan(ProviderContainer container) {
  unawaited(
    container
        .read(receiptScanControllerProvider.notifier)
        .scan(const ReceiptPhotos(['a.jpg'])),
  );
}

/// Answers every outstanding line the short way — the doors themselves are
/// exercised above; here the point is what the map does once they are shut.
Future<void> answerEveryLine(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final notifier = container.read(receiptScanControllerProvider.notifier);
  for (final draft
      in (container.read(receiptScanControllerProvider) as ReceiptReviewing)
          .drafts) {
    if (draft.kind.isFood && draft.ingredientId == null) {
      await notifier.matchLine(draft.index, bananas);
    }
  }
  await tester.pumpAndSettle();
  for (final draft
      in (container.read(receiptScanControllerProvider) as ReceiptReviewing)
          .drafts) {
    if (draft.kind.isFood && (draft.packBasisAmount ?? 0) <= 0) {
      notifier.setPack(
        draft.index,
        amount: 454,
        choice: const UnitOption(g),
        basisAmount: 454,
      );
    }
  }
  await tester.pumpAndSettle();
}
