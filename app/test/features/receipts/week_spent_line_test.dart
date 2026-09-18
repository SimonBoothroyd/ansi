/// The week band's **second figure** — what the week's receipts came to,
/// under what it plans to cook.
///
/// Two rules, and they are the point of the line: it appears **only when a
/// receipt is dated inside the week on screen**, and the two figures are
/// never reconciled (ADR-0017) — the gap between them is the pantry.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/planning/domain/week_macros.dart';
import 'package:ansi/features/planning/presentation/week_macro_widgets.dart';
import 'package:ansi/features/receipts/domain/receipt_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ReceiptSummary receipt({DateTime? on, int cents = 8412}) => ReceiptSummary(
  id: 'r1',
  store: "TJ's",
  purchasedAt: on ?? DateTime(2026, 9, 13),
  source: ReceiptSource.photo,
  totalCents: cents,
);

Future<void> pumpBand(
  WidgetTester tester, {
  List<ReceiptSummary> spent = const [],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => WeekMacroBand(
          // An empty week: the band says `no meals yet` above, and the spent
          // line is about the shop rather than about the plan, so it is drawn
          // all the same.
          macros: const MealSetMacros(),
          scope: 'Everyone',
          spent: spent,
        ),
      ),
      GoRoute(path: '/receipts', builder: (_, _) => const Text('the ledger')),
    ],
  );
  return tester.pumpWidget(
    ProviderScope(
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
  testWidgets('a week with no receipt says nothing about spending', (
    tester,
  ) async {
    await pumpBand(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('spent'), findsNothing);
  });

  testWidgets('a week with one names the figure, the count and the shop', (
    tester,
  ) async {
    await pumpBand(tester, spent: [receipt()]);
    await tester.pumpAndSettle();
    expect(find.text(r"$84.12 spent · 1 receipt · TJ's, Sun"), findsOneWidget);
  });

  testWidgets('the line is the door onto the ledger', (tester) async {
    await pumpBand(tester, spent: [receipt()]);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('spent'));
    await tester.pumpAndSettle();
    expect(find.text('the ledger'), findsOneWidget);
  });

  test('it never claims a free week', () {
    // The band draws nothing rather than `$0 spent`, which would read as a
    // week that cost nothing instead of one nobody shopped for.
    expect(weekSpentLine(const [], WeekShape.monday), isNull);
  });
}
