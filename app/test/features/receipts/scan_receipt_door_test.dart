/// The Shop's second foot door — the one that ends the trip.
///
/// Three things are pinned: it opens the scan, the ledger rides the same row
/// rather than taking a door of its own, and that ledger link appears **only
/// once the household has kept a receipt** — a door onto an empty page is
/// furniture.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '_harness.dart';

Future<void> pumpDoor(
  WidgetTester tester, {
  required List<Override> overrides,
  bool web = false,
}) {
  final router = GoRouter(
    initialLocation: '/shop',
    routes: [
      GoRoute(
        path: '/shop',
        builder: (_, _) => ScanReceiptDoor(web: web),
      ),
      GoRoute(
        path: '/receipts/review',
        builder: (_, _) => const Text('the scan'),
      ),
      GoRoute(path: '/receipts', builder: (_, _) => const Text('the ledger')),
    ],
  );
  return tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: ansiHostTheme(),
        routerConfig: router,
        builder: (context, child) =>
            FTheme(data: ansiThemeData(), child: child!),
      ),
    ),
  );
}

void main() {
  testWidgets('it opens the scan', (tester) async {
    await pumpDoor(tester, overrides: receiptOverrides());
    await tester.pumpAndSettle();
    expect(find.text('scan a receipt'), findsOneWidget);

    await tester.tap(find.text('scan a receipt'));
    await tester.pumpAndSettle();
    expect(find.text('the scan'), findsOneWidget);
  });

  testWidgets('with nothing kept there is no ledger door', (tester) async {
    await pumpDoor(tester, overrides: receiptOverrides());
    await tester.pumpAndSettle();
    expect(
      find.text('receipts'),
      findsNothing,
      reason: 'a door onto an empty page is furniture',
    );
  });

  testWidgets('once a receipt is kept, the ledger rides the same row', (
    tester,
  ) async {
    await pumpDoor(
      tester,
      overrides: receiptOverrides(
        ledger: FakeReceiptRepo(rows: [ledgerRow(on: DateTime(2026, 9, 13))]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('receipts'), findsOneWidget);
    await tester.tap(find.text('receipts'));
    await tester.pumpAndSettle();
    expect(find.text('the ledger'), findsOneWidget);
  });

  testWidgets('in a browser the door says what it can actually do', (
    tester,
  ) async {
    await pumpDoor(tester, overrides: receiptOverrides(), web: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('no camera and no crop step'), findsOneWidget);
    expect(
      find.textContaining('shoot the receipt on the phone'),
      findsOneWidget,
    );
  });
}
