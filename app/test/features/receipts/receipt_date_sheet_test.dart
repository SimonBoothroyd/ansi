/// *When was this shop* — the day and the clock, committed together.
///
/// Pinned: a day moved alone keeps the clock (seconds and all), a moved clock
/// starts its minute, a moment later than now holds *Use it*, and the X hands
/// back nothing.
library;

import 'package:ansi/features/receipts/presentation/receipt_date_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/pump_app.dart';
import '_harness.dart';

/// Sunday 13 Sep 2026, a quarter past six in the evening.
final now = DateTime(2026, 9, 13, 18, 15);

/// What the sheet resolved to, and whether it has resolved at all.
class Outcome {
  bool resolved = false;
  DateTime? picked;
}

Future<Outcome> openSheet(WidgetTester tester, DateTime current) async {
  tallSurface(tester);
  final outcome = Outcome();
  await tester.pumpAnsiApp(
    FScaffold(
      child: Builder(
        builder: (context) => Center(
          child: FButton(
            onPress: () async {
              final picked = await showReceiptDateSheet(
                context,
                current: current,
                now: now,
              );
              outcome
                ..picked = picked
                ..resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return outcome;
}

Future<void> tapDay(WidgetTester tester, String day) async {
  await tester.tap(
    find
        .descendant(
          of: find.byKey(kReceiptDateCalendarKey),
          matching: find.text(day),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

FButton useIt(WidgetTester tester) =>
    tester.widget<FButton>(find.byKey(kReceiptDateUseKey));

void main() {
  testWidgets('a day alone is not the commit; Use it is, clock kept', (
    tester,
  ) async {
    final outcome = await openSheet(tester, DateTime(2026, 9, 13, 17, 42, 9));
    expect(find.text('When was this shop'), findsOneWidget);

    await tapDay(tester, '12');
    expect(outcome.resolved, isFalse, reason: 'the clock may still move');

    await tester.tap(find.byKey(kReceiptDateUseKey));
    await tester.pumpAndSettle();
    expect(outcome.picked, DateTime(2026, 9, 12, 17, 42, 9));
  });

  testWidgets('only the time moves, and the minute starts clean', (
    tester,
  ) async {
    final outcome = await openSheet(tester, DateTime(2026, 9, 13, 17, 42, 9));

    await turnReceiptClock(tester, 0, 9);
    await turnReceiptClock(tester, 1, 5);
    await tester.tap(find.byKey(kReceiptDateUseKey));
    await tester.pumpAndSettle();

    expect(outcome.picked, DateTime(2026, 9, 13, 9, 5));
  });

  testWidgets('the day and the time move together', (tester) async {
    final outcome = await openSheet(tester, DateTime(2026, 9, 13, 17, 42));

    await tapDay(tester, '10');
    await turnReceiptClock(tester, 0, 20);
    await turnReceiptClock(tester, 1, 30);
    await tester.tap(find.byKey(kReceiptDateUseKey));
    await tester.pumpAndSettle();

    expect(outcome.picked, DateTime(2026, 9, 10, 20, 30));
  });

  testWidgets('a time later than now today holds Use it, and says why', (
    tester,
  ) async {
    await openSheet(tester, DateTime(2026, 9, 13, 17, 42));
    expect(useIt(tester).onPress, isNotNull);

    await turnReceiptClock(tester, 0, 19);
    expect(useIt(tester).onPress, isNull);
    expect(find.text('that is later than now'), findsOneWidget);

    // The same hour on an earlier day is in the past, so it is fine.
    await tapDay(tester, '12');
    expect(useIt(tester).onPress, isNotNull);
    expect(find.text('that is later than now'), findsNothing);
  });

  testWidgets('a day after today cannot be picked', (tester) async {
    final outcome = await openSheet(tester, DateTime(2026, 9, 13, 17, 42));

    await tapDay(tester, '14');
    await tester.tap(find.byKey(kReceiptDateUseKey));
    await tester.pumpAndSettle();
    // Still the receipt's own day: the 14th was never selected.
    expect(outcome.picked, DateTime(2026, 9, 13, 17, 42));
  });

  testWidgets('the X hands back nothing', (tester) async {
    final outcome = await openSheet(tester, DateTime(2026, 9, 13, 17, 42));

    await turnReceiptClock(tester, 0, 9);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(outcome.resolved, isTrue);
    expect(outcome.picked, isNull);
  });

  test('a day moved alone keeps the seconds; a moved clock drops them', () {
    final at = DateTime(2026, 9, 13, 17, 42, 9);
    final day = DateTime(2026, 9, 11);
    expect(
      pickedMoment(at, day, const FTime(17, 42)),
      DateTime(2026, 9, 11, 17, 42, 9),
    );
    expect(
      pickedMoment(at, day, const FTime(17, 43)),
      DateTime(2026, 9, 11, 17, 43),
    );
  });
}
