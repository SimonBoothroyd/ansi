/// The ledger's main action, **Scan a receipt** — the scan lives with what it
/// makes, so it heads the ledger whether or not anything has filed there yet.
///
/// Pinned here: the action stands under the header, above the month band, in
/// the empty ledger too; a tap opens the scan; and in a browser the line under
/// it says what the scan can do there. Save coming back to the ledger is in
/// `receipt_review_screen_test.dart`, beside the other Save tests.
library;

import 'package:ansi/features/receipts/presentation/receipt_ledger_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '_harness.dart';

void main() {
  testWidgets('the empty ledger offers the scan over the line that says '
      'where receipts come from', (tester) async {
    await tester.pumpWidget(ledgerHost(overrides: receiptOverrides()));
    await tester.pumpAndSettle();

    final action = find.byKey(kReceiptScanActionKey);
    expect(action, findsOneWidget);
    expect(
      find.descendant(of: action, matching: find.byIcon(FLucideIcons.camera)),
      findsOneWidget,
    );
    expect(find.text('Scan a receipt'), findsOneWidget);
    final line = find.text(
      'no receipts yet — a scanned shop files here by week; a price typed on '
      'an ingredient stays on the ingredient',
    );
    expect(line, findsOneWidget);
    expect(tester.getTopLeft(action).dy, lessThan(tester.getTopLeft(line).dy));
    expect(find.textContaining('from the Shop'), findsNothing);
  });

  testWidgets('a filled ledger keeps the action at the top, above the month', (
    tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(
      ledgerHost(
        overrides: receiptOverrides(
          ledger: FakeReceiptRepo(rows: [ledgerRow(on: DateTime(2026, 9, 13))]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(kReceiptScanActionKey);
    expect(action, findsOneWidget);
    expect(
      tester.getBottomLeft(action).dy,
      lessThan(tester.getTopLeft(find.text('SEPTEMBER · SO FAR')).dy),
    );
    // Full width: it spans the ledger's column, as the receipt rows do.
    expect(
      tester.getSize(action).width,
      closeTo(tester.getSize(find.byKey(kReceiptLedgerKey)).width - 40, 0.5),
    );
  });

  testWidgets('a tap opens the scan', (tester) async {
    await tester.pumpWidget(ledgerHost(overrides: receiptOverrides()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(kReceiptScanActionKey));
    await tester.pumpAndSettle();
    expect(find.text('the scan'), findsOneWidget);
  });

  testWidgets('in a browser the action says what it can actually do', (
    tester,
  ) async {
    await tester.pumpWidget(
      ledgerHost(overrides: receiptOverrides(), web: true),
    );
    await tester.pumpAndSettle();
    final words = find.textContaining('no camera and no crop step');
    expect(words, findsOneWidget);
    expect(
      find.textContaining('shoot the receipt on the phone'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(words).dy,
      greaterThan(tester.getBottomLeft(find.byKey(kReceiptScanActionKey)).dy),
    );
  });

  testWidgets('on the phone there is nothing to explain', (tester) async {
    await tester.pumpWidget(ledgerHost(overrides: receiptOverrides()));
    await tester.pumpAndSettle();
    expect(find.textContaining('no camera'), findsNothing);
  });
}
