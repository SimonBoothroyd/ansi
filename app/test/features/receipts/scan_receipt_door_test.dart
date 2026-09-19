/// The Shop's second foot door — the one that ends the trip.
///
/// Two things are pinned: it opens the scan, and it is the only receipts door
/// at the foot. The ledger's door is the header's receipt action, which
/// `shopping_screen_test.dart` holds.
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

  testWidgets('the ledger does not ride this row — it has the header', (
    tester,
  ) async {
    await pumpDoor(
      tester,
      overrides: receiptOverrides(
        ledger: FakeReceiptRepo(rows: [ledgerRow(on: DateTime(2026, 9, 13))]),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('receipts'),
      findsNothing,
      reason: 'one door, in the chrome — not a second link at the foot',
    );
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
