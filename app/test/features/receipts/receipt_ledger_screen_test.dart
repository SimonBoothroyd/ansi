/// The ledger, and one receipt read back.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/receipts/domain/receipt_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

StoredReceiptLine storedLine({
  String id = 'l1',
  String? ingredientId = 'vocab-banana',
  String? name = 'Bananas, organic',
  String printed = 'TJ ORG BANANAS  3.49',
  int cents = 349,
  int discountCents = 0,
  String kind = 'item',
  double? packBasis = 454,
  double? packAmount = 1,
  String? packUnit,
  String? measureId = 'm-bag',
  String? measureLabel = 'bag',
}) => (
  id: id,
  ingredientId: ingredientId,
  ingredientName: name,
  printedText: printed,
  cents: cents,
  discountCents: discountCents,
  kind: kind,
  packBasisAmount: packBasis,
  packAmount: packAmount,
  packUnit: packUnit,
  measureId: measureId,
  measureLabel: measureLabel,
  macrosBasis: 'g',
);

void main() {
  testWidgets('an empty ledger says where receipts come from', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(ledgerHost(overrides: receiptOverrides()));
    await tester.pumpAndSettle();
    expect(find.textContaining('no receipts yet'), findsOneWidget);
  });

  testWidgets('receipts file by week, newest first, with a month on top', (
    tester,
  ) async {
    tallSurface(tester);
    final ledger = FakeReceiptRepo(
      rows: [
        ledgerRow(id: 'a', on: DateTime(2026, 9, 13)),
        ledgerRow(
          id: 'b',
          store: 'Whole Foods',
          on: DateTime(2026, 9, 16),
          total: 2340,
          lines: 6,
          notFood: 0,
        ),
        ledgerRow(
          id: 'c',
          on: DateTime(2026, 9, 6),
          total: 9106,
          lines: 27,
          notFood: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      ledgerHost(overrides: receiptOverrides(ledger: ledger)),
    );
    await tester.pumpAndSettle();

    expect(find.text('SEPTEMBER · SO FAR'), findsOneWidget);
    expect(
      find.text(
        r"$198.58 spent · 3 receipts · TJ's $175.18 · Whole Foods $23.40",
      ),
      findsOneWidget,
    );
    expect(find.text('Week of 14 Sep'), findsOneWidget);
    expect(find.text('Week of 7 Sep'), findsOneWidget);
    expect(find.text('Sun 13 Sep · 24 lines · 2 not food'), findsOneWidget);
    expect(find.text('Wed 16 Sep · 6 lines'), findsOneWidget);
    expect(find.text(r'$84.12 spent'), findsOneWidget);
  });

  testWidgets('a hand-typed price is the same fact in the same ledger', (
    tester,
  ) async {
    tallSurface(tester);
    final ledger = FakeReceiptRepo(
      rows: [
        ledgerRow(
          id: 'm',
          store: 'Whole Foods',
          on: DateTime(2026, 9, 5),
          source: 'manual',
          total: null,
          lines: 1,
          notFood: 0,
          linesSum: 8702,
        ),
      ],
    );
    await tester.pumpWidget(
      ledgerHost(overrides: receiptOverrides(ledger: ledger)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sat 5 Sep · typed by hand'), findsOneWidget);
    expect(
      find.text(r'$87.84'),
      findsOneWidget,
      reason: 'no printed total, so the lines plus the tax it carried',
    );
  });

  testWidgets('a row opens its receipt', (tester) async {
    tallSurface(tester);
    final ledger = FakeReceiptRepo(
      rows: [ledgerRow(id: 'a', on: DateTime(2026, 9, 13))],
    );
    await tester.pumpWidget(
      ledgerHost(overrides: receiptOverrides(ledger: ledger)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("TJ's"));
    await tester.pumpAndSettle();
    expect(find.text('receipt a'), findsOneWidget);
  });

  group('one receipt, read back', () {
    testWidgets('the read-only review names the paper and its lines', (
      tester,
    ) async {
      tallSurface(tester);
      final ledger = FakeReceiptRepo()
        ..stored['a'] = (
          id: 'a',
          store: "TJ's",
          purchasedAt: DateTime(2026, 9, 13, 17, 42),
          source: 'photo',
          subtotalCents: 1048,
          taxCents: 82,
          totalCents: 1130,
          lines: [
            storedLine(),
            storedLine(
              id: 'l2',
              printed: 'YELLOW ONIONS  1.32 lb @ 1.99/lb  2.63',
              cents: 263,
              ingredientId: 'vocab-onion',
              name: 'Yellow onion',
              packBasis: 598.74,
              packAmount: 1.32,
              packUnit: 'lb',
              measureId: null,
              measureLabel: null,
            ),
            storedLine(
              id: 'l3',
              printed: 'PAPER TOWELS  6.99',
              cents: 699,
              kind: 'not_food',
              ingredientId: null,
              name: null,
              packBasis: null,
              packAmount: null,
              measureId: null,
              measureLabel: null,
            ),
          ],
        );
      await tester.pumpWidget(
        storedReceiptHost(
          overrides: receiptOverrides(ledger: ledger),
          receiptId: 'a',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("TJ's"), findsWidgets);
      expect(find.text(r'Sunday 13 Sep · $11.30'), findsOneWidget);
      expect(find.text('Bananas, organic'), findsOneWidget);
      expect(find.textContaining('bag (454 g) · 77¢ / 100 g'), findsOneWidget);
      expect(find.text('Yellow onion'), findsOneWidget);
      expect(find.textContaining('1.32 lb · '), findsOneWidget);
      expect(find.text(r'Not food · 1 · $6.99'), findsOneWidget);
      expect(find.text('Tax · 82¢'), findsOneWidget);
      expect(
        find.text('Say what the pack is'),
        findsNothing,
        reason: 'a saved receipt asks nothing',
      );
      expect(
        find.textContaining('edited on the ingredient’s own page'),
        findsOneWidget,
      );
    });

    testWidgets('a receipt that is gone says so', (tester) async {
      await tester.pumpWidget(
        storedReceiptHost(overrides: receiptOverrides(), receiptId: 'nope'),
      );
      await tester.pumpAndSettle();
      expect(find.text('this receipt is gone'), findsOneWidget);
    });

    testWidgets('a hand-typed one says it was typed', (tester) async {
      tallSurface(tester);
      final ledger = FakeReceiptRepo()
        ..stored['m'] = (
          id: 'm',
          store: 'Whole Foods',
          purchasedAt: DateTime(2026, 9, 5, 12),
          source: 'manual',
          subtotalCents: 349,
          taxCents: null,
          totalCents: null,
          lines: [storedLine()],
        );
      await tester.pumpWidget(
        storedReceiptHost(
          overrides: receiptOverrides(ledger: ledger),
          receiptId: 'm',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(r'Saturday 5 Sep · $3.49 · typed by hand'),
        findsOneWidget,
      );
    });
  });

  test('the unit catalog reads a stored pack unit back', () {
    expect(unitById('lb'), lb);
  });
}
