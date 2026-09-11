/// Display formatting for the Shop screen — pure Dart (no widgets), so the
/// quantity/total copy is unit-testable.
library;

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart' show formatQuantity;
import '../domain/shopping.dart';

/// Formats one [Quantity] for the list, e.g. "500 g", "1.5 kg", "5 piece".
String formatTotal(Quantity q) => '${formatQuantity(q.amount)} ${q.unit.label}';

/// The week menu row's trailing label on the Shop tab — what that week holds in
/// this tab's own derivation, `6 items` / `1 item` / `nothing to buy`, never
/// the Week's meal count.
String formatItemCount(int items) => switch (items) {
  0 => 'nothing to buy',
  1 => '1 item',
  _ => '$items items',
};

/// A count of a [Measure], e.g. "2 can (400 g), drained".
String formatMeasureCount(double amount, Measure measure) =>
    '${formatQuantity(amount)} ${measure.label}';

/// An item's rolled-up total for the right-hand column. An item every
/// contribution asked for in one measure reads in that measure ("1 can
/// (400 g), drained") — it is what goes in the basket. Otherwise the honest
/// subtotals join with " + " (a mass and a volume that couldn't be merged),
/// and a numberless non-food staple renders as an em dash.
String itemTotal(ShoppingItem item) {
  final measured = item.measureTotal;
  if (measured != null) {
    return formatMeasureCount(measured.amount, measured.measure);
  }
  if (item.totals.isEmpty) return '—';
  return item.totals.map(formatTotal).join(' + ');
}

/// The small line under an item's total: what a measure-counted row weighs
/// ("400 g"), or the whole-unit round-up hint. Empty when the row has neither.
/// Never a replacement for [itemTotal] — always beside it (invariant 3).
String itemSecondary(ShoppingItem item) {
  if (item.measureTotal != null) {
    return item.totals.map(formatTotal).join(' + ');
  }
  final hint = item.wholeUnitHint;
  return hint == null ? '' : wholeUnitHintText(hint);
}

/// A provenance line's quantity ("300 g", or "2 potato, large" when counted
/// in a measure), or empty when it carries none. A line keeps its own words
/// whatever the item's total ended up in.
String contributionQuantity(ShoppingContribution c) {
  final q = c.quantity;
  if (q == null) return '';
  final measure = c.measure;
  if (measure != null) return formatMeasureCount(q, measure);
  final unit = c.unit;
  if (unit == null) return '';
  return '${formatQuantity(q)} ${unit.label}';
}

/// The whole-unit round-up hint under a count-food's total: "2.25 piece →
/// buy 3", or "≈ 2.25 potato, large → buy 3" when the count was derived from
/// a mass total via the measure's gram weight. Always beside the honest
/// total, never instead of it (invariant 3).
String wholeUnitHintText(WholeUnitHint h) =>
    '${h.approx ? '≈ ' : ''}${formatQuantity(h.count)} ${h.unitLabel} '
    '→ buy ${h.buy}';
