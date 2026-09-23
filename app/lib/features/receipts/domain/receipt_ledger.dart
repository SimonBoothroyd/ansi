/// The receipts ledger, filed by week. Pure Dart.
///
/// A receipt files under the week its own date falls in, read through the
/// household's week shape. Each week shows spent against planned, and a month
/// line sums the receipts by store. The two figures are shown, never reconciled
/// (ADR-0017).
library;

import 'package:meta/meta.dart';

import '../../../core/money.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';

/// One receipt as the ledger lists it — the paper's own facts plus the two
/// counts a row prints.
@immutable
class ReceiptSummary {
  const ReceiptSummary({
    required this.id,
    required this.store,
    required this.purchasedAt,
    required this.totalCents,
    this.lineCount = 0,
    this.notFoodCount = 0,
  });

  final String id;
  final String store;
  final DateTime purchasedAt;

  /// What the trip cost: the paper's printed total where it printed one, and
  /// the sum of the lines where it did not.
  final int totalCents;

  final int lineCount;
  final int notFoodCount;

  /// `Sun 13 Sep · 24 lines · 2 not food`.
  String subLine(WeekShape shape) {
    final day = shape.labelShort(shape.offsetOf(purchasedAt));
    return [
      '$day ${formatDayMonth(purchasedAt)}',
      '$lineCount ${plural(lineCount, 'line')}',
      if (notFoodCount > 0) '$notFoodCount not food',
    ].join(' · ');
  }
}

/// One week of the ledger.
@immutable
class ReceiptWeek {
  const ReceiptWeek({required this.weekStart, required this.receipts});

  /// The first day of the week, as [WeekShape.weekStartOf] answers it.
  final DateTime weekStart;

  /// Newest first inside the week, then by store — the order a person who
  /// shopped twice reads them in.
  final List<ReceiptSummary> receipts;

  int get spentCents {
    var total = 0;
    for (final r in receipts) {
      total += r.totalCents;
    }
    return total;
  }
}

/// One month's line at the top of the ledger.
@immutable
class ReceiptMonth {
  const ReceiptMonth({
    required this.month,
    required this.spentCents,
    required this.count,
    required this.byStore,
  });

  /// The first day of the month it stands for.
  final DateTime month;
  final int spentCents;
  final int count;

  /// Each store and what it took, biggest first.
  final List<({String store, int cents})> byStore;
}

/// [receipts] filed by the household's week, newest week first. The receipt's
/// `purchased_at` decides the week, never the scan's date.
List<ReceiptWeek> fileByWeek(List<ReceiptSummary> receipts, WeekShape shape) {
  final byWeek = <DateTime, List<ReceiptSummary>>{};
  for (final receipt in receipts) {
    (byWeek[shape.weekStartOf(receipt.purchasedAt)] ??= []).add(receipt);
  }
  final weeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final week in weeks)
      ReceiptWeek(
        weekStart: week,
        receipts: byWeek[week]!
          ..sort((a, b) {
            final byDate = b.purchasedAt.compareTo(a.purchasedAt);
            return byDate != 0 ? byDate : a.store.compareTo(b.store);
          }),
      ),
  ];
}

/// The newest month present in [receipts], summed and split by store — the
/// ledger's top line. Null when there is nothing to sum.
ReceiptMonth? newestMonth(List<ReceiptSummary> receipts) {
  DateTime? newest;
  for (final r in receipts) {
    final month = DateTime(r.purchasedAt.year, r.purchasedAt.month);
    if (newest == null || month.isAfter(newest)) newest = month;
  }
  if (newest == null) return null;
  final byStore = <String, int>{};
  var total = 0;
  var count = 0;
  for (final r in receipts) {
    if (r.purchasedAt.year != newest.year ||
        r.purchasedAt.month != newest.month) {
      continue;
    }
    byStore[r.store] = (byStore[r.store] ?? 0) + r.totalCents;
    total += r.totalCents;
    count++;
  }
  final stores = [
    for (final e in byStore.entries) (store: e.key, cents: e.value),
  ]..sort((a, b) => b.cents.compareTo(a.cents));
  return ReceiptMonth(
    month: newest,
    spentCents: total,
    count: count,
    byStore: stores,
  );
}

/// The receipts dated inside the week beginning [weekStart].
List<ReceiptSummary> receiptsInWeek(
  List<ReceiptSummary> receipts,
  DateTime weekStart,
  WeekShape shape,
) => [
  for (final r in receipts)
    if (shape.weekStartOf(r.purchasedAt) == weekStart) r,
];

/// `$84.12 spent · 1 receipt · TJ's, Sun`: the band's second figure. Null when
/// no receipt is dated inside the week, rather than `$0 spent`. The trailing
/// clause names one store and its day, or the count of stores.
String? weekSpentLine(List<ReceiptSummary> inWeek, WeekShape shape) {
  if (inWeek.isEmpty) return null;
  var total = 0;
  final stores = <String>{};
  for (final r in inWeek) {
    total += r.totalCents;
    stores.add(r.store);
  }
  final newest = inWeek.reduce(
    (a, b) => a.purchasedAt.isAfter(b.purchasedAt) ? a : b,
  );
  final day = shape.labelShort(shape.offsetOf(newest.purchasedAt));
  final where = stores.length == 1
      ? '${newest.store}, $day'
      : '${stores.length} stores';
  return '${formatMoney(total)} spent · ${inWeek.length} '
      '${plural(inWeek.length, 'receipt')} · $where';
}

/// `$107.52 spent` — a ledger week's own figure, to be read beside the same
/// week's `≈ $71 to cook`.
String weekSpentTotal(ReceiptWeek week) =>
    '${formatMoney(week.spentCents)} spent';

/// `$412.16 spent · 5 receipts · TJ's $301.74 · Whole Foods $110.42`.
String monthLine(ReceiptMonth month) => [
  '${formatMoney(month.spentCents)} spent',
  '${month.count} ${plural(month.count, 'receipt')}',
  for (final store in month.byStore)
    '${store.store} ${formatMoney(store.cents)}',
].join(' · ');

/// `September · so far` — the month heading. A month that has ended says its
/// name alone; the current one says it is not finished.
String monthHeading(ReceiptMonth month, {required DateTime today}) {
  final name = kMonthFull[month.month.month - 1];
  final current =
      today.year == month.month.year && today.month == month.month.month;
  return current ? '$name · so far' : '$name ${month.month.year}';
}
