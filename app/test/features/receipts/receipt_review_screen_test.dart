/// The review screen, driven through the real controller and the replay
/// payload.
///
/// What is pinned here is that the screen says **one thing**: the header
/// count, the card flags, the join card and Save all read the same map, and
/// a line answered anywhere moves all four.
library;

import 'dart:async';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/receipts/data/sample_receipt_payloads.dart';
import 'package:ansi/features/receipts/domain/receipt_repository.dart';
import 'package:ansi/features/receipts/presentation/receipt_review_body.dart';
import 'package:ansi/features/receipts/presentation/receipt_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_price_repository.dart';
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
      await tester.tap(find.text('TJ MED CHDR SHRD  3.79').first);
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

      await tester.tap(find.text('TJ MED CHDR SHRD  3.79').first);
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
          r'$3.49 apart · Find the join — a line is missing or doubled',
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
