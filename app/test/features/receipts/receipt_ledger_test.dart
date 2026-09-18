/// The ledger's filing: which week a receipt belongs to, what a month line
/// says, and the band's second figure.
///
/// The load-bearing rule is that a receipt files by **its own date** and by
/// the **household's** week start — so a Sunday shop sits inside the week it
/// feeds under one household and in the week before it under another, and
/// both are right.
library;

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/receipts/domain/receipt_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptSummary receipt({
  required DateTime on,
  String id = 'r1',
  String store = "TJ's",
  int cents = 8412,
  ReceiptSource source = ReceiptSource.photo,
  int lines = 24,
  int notFood = 2,
}) => ReceiptSummary(
  id: id,
  store: store,
  purchasedAt: on,
  source: source,
  totalCents: cents,
  lineCount: lines,
  notFoodCount: notFood,
);

void main() {
  group('a row says what it is', () {
    test('a photographed receipt counts its lines', () {
      expect(
        receipt(on: DateTime(2026, 9, 13)).subLine(WeekShape.monday),
        'Sun 13 Sep · 24 lines · 2 not food',
      );
    });

    test('a row with nothing but food says so by staying quiet', () {
      expect(
        receipt(
          on: DateTime(2026, 9, 16),
          notFood: 0,
          lines: 6,
        ).subLine(WeekShape.monday),
        'Wed 16 Sep · 6 lines',
      );
    });

    test('a hand-typed price says it was typed, and counts nothing', () {
      expect(
        receipt(
          on: DateTime(2026, 9, 5),
          source: ReceiptSource.manual,
          lines: 1,
          notFood: 0,
        ).subLine(WeekShape.monday),
        'Sat 5 Sep · typed by hand',
      );
    });

    test('the weekday is the household’s, never a Monday-first index', () {
      final sunday = receipt(on: DateTime(2026, 9, 13));
      expect(sunday.subLine(WeekShape.monday), startsWith('Sun'));
      expect(sunday.subLine(WeekShape.sunday), startsWith('Sun'));
    });
  });

  group('filing by week', () {
    final receipts = [
      receipt(id: 'a', on: DateTime(2026, 9, 13)),
      receipt(id: 'b', store: 'Whole Foods', on: DateTime(2026, 9, 16)),
      receipt(id: 'c', on: DateTime(2026, 9, 6)),
    ];

    test('a Sunday shop files with the week it feeds, under each shape', () {
      final monday = fileByWeek(receipts, WeekShape.monday);
      // Sun 13 Sep belongs to the week beginning Mon 7 Sep…
      expect(monday.map((w) => w.weekStart), [
        DateTime.utc(2026, 9, 14),
        DateTime.utc(2026, 9, 7),
        DateTime.utc(2026, 8, 31),
      ]);
      expect(monday.first.receipts.map((r) => r.id), ['b'], reason: 'Wed 16');

      final sunday = fileByWeek(receipts, WeekShape.sunday);
      // …and under a Sunday-start household it opens the week of 13 Sep.
      expect(sunday.first.weekStart, DateTime.utc(2026, 9, 13));
      expect(sunday.first.receipts.map((r) => r.id), ['b', 'a']);
    });

    test('weeks come newest first, receipts newest first inside one', () {
      final weeks = fileByWeek([
        receipt(id: 'x', on: DateTime(2026, 9, 14)),
        receipt(id: 'y', store: 'Whole Foods', on: DateTime(2026, 9, 18)),
      ], WeekShape.monday);
      expect(weeks.single.receipts.map((r) => r.id), ['y', 'x']);
    });

    test('a week sums what it holds', () {
      final weeks = fileByWeek([
        receipt(id: 'a', on: DateTime(2026, 9, 13)),
        receipt(
          id: 'b',
          store: 'Whole Foods',
          on: DateTime(2026, 9, 9),
          cents: 2340,
        ),
      ], WeekShape.monday);
      expect(weeks.single.spentCents, 8412 + 2340);
      expect(weekSpentTotal(weeks.single), r'$107.52 spent');
    });

    test('nothing files to no weeks at all', () {
      expect(fileByWeek(const [], WeekShape.monday), isEmpty);
    });
  });

  group('the month line', () {
    test('sums the newest month and splits it by store, biggest first', () {
      final month = newestMonth([
        receipt(id: 'a', on: DateTime(2026, 9, 13)),
        receipt(
          id: 'b',
          store: 'Whole Foods',
          on: DateTime(2026, 9, 16),
          cents: 2340,
        ),
        receipt(id: 'c', on: DateTime(2026, 9, 6), cents: 9106),
        receipt(id: 'd', on: DateTime(2026, 8, 30), cents: 6222),
      ])!;
      expect(month.month, DateTime(2026, 9));
      expect(month.count, 3, reason: 'August is a month of its own');
      expect(month.spentCents, 8412 + 2340 + 9106);
      expect(month.byStore.map((s) => s.store), ["TJ's", 'Whole Foods']);
      expect(
        monthLine(month),
        r"$198.58 spent · 3 receipts · TJ's $175.18 · Whole Foods $23.40",
      );
    });

    test('the current month says it is not finished; a past one does not', () {
      final month = newestMonth([receipt(on: DateTime(2026, 9, 13))])!;
      expect(
        monthHeading(month, today: DateTime(2026, 9, 17)),
        'September · so far',
      );
      expect(
        monthHeading(month, today: DateTime(2026, 10, 2)),
        'September 2026',
      );
    });

    test('nothing to sum is no line', () {
      expect(newestMonth(const []), isNull);
    });
  });

  group('the band’s second figure', () {
    test('names the store and the day when the week held one shop', () {
      final week = receiptsInWeek(
        [receipt(on: DateTime(2026, 9, 13))],
        DateTime.utc(2026, 9, 7),
        WeekShape.monday,
      );
      expect(
        weekSpentLine(week, WeekShape.monday),
        r"$84.12 spent · 1 receipt · TJ's, Sun",
      );
    });

    test('counts the stores when the week held more than one', () {
      final week = [
        receipt(id: 'a', on: DateTime(2026, 9, 13)),
        receipt(
          id: 'b',
          store: 'Whole Foods',
          on: DateTime(2026, 9, 16),
          cents: 2340,
        ),
      ];
      expect(
        weekSpentLine(week, WeekShape.monday),
        r'$107.52 spent · 2 receipts · 2 stores',
      );
    });

    test(
      'a week with no shop stays silent rather than claiming a free one',
      () {
        expect(weekSpentLine(const [], WeekShape.monday), isNull);
      },
    );

    test('only the receipts dated inside the week are in it', () {
      final all = [
        receipt(id: 'in', on: DateTime(2026, 9, 13)),
        receipt(id: 'out', on: DateTime(2026, 9, 16)),
      ];
      expect(
        receiptsInWeek(
          all,
          DateTime.utc(2026, 9, 7),
          WeekShape.monday,
        ).map((r) => r.id),
        ['in'],
      );
    });
  });
}
