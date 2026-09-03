/// Display formatting for the Shop screen — pure Dart (no widgets), so the
/// quantity/total copy is unit-testable.
library;

import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart' show formatQuantity;
import '../domain/shopping.dart';

/// Formats one [Quantity] for the list, e.g. "500 g", "1.5 kg", "5 piece".
String formatTotal(Quantity q) => '${formatQuantity(q.amount)} ${q.unit.label}';

/// The week menu row's trailing label on the Shop tab — what that week holds
/// in this tab's own derivation, `6 items` / `1 item` / `nothing to buy`
/// (plan 0025 D7 frames g2/h), never the Week's meal count.
String formatItemCount(int items) => switch (items) {
  0 => 'nothing to buy',
  1 => '1 item',
  _ => '$items items',
};

/// An item's rolled-up total for the right-hand column. Joins honest subtotals
/// with " + " (a mass and a volume that couldn't be merged), and renders a
/// numberless non-food staple as an em dash.
String itemTotal(ShoppingItem item) {
  if (item.totals.isEmpty) return '—';
  return item.totals.map(formatTotal).join(' + ');
}

/// A provenance line's quantity ("300 g", or "2 potato, large" when counted
/// in a measure), or empty when it carries none.
String contributionQuantity(ShoppingContribution c) {
  final q = c.quantity;
  if (q == null) return '';
  final measure = c.measure;
  if (measure != null) return '${formatQuantity(q)} ${measure.label}';
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
