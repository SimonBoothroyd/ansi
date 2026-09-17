/// Display formatting for the Shop screen — pure Dart (no widgets), so the
/// quantity/total copy is unit-testable.
library;

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/cost_words.dart' show approxMoney;
import '../../../shared/format.dart' show formatQuantity, formatQuantityIn;
import '../domain/shopping.dart';

/// Formats one [Quantity] for the list, e.g. "500 g", "1.5 kg", "5 piece".
String formatTotal(Quantity q) =>
    '${formatQuantityIn(q.amount, q.unit)} ${q.unit.label}';

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

/// A count of pieces, e.g. "2½ piece", or "≈ 2½ piece" when the count was
/// read back from a weight rather than tallied.
String formatPieceCount(PieceTotal p) =>
    '${p.approx ? '≈ ' : ''}${formatQuantity(p.count)} ${pieces.label}';

/// An item's rolled-up total for the right-hand column. A piece-weighted row
/// reads its count of pieces ("2½ piece"); an item every contribution asked
/// for in one measure reads in that measure ("1 can (400 g), drained") — each
/// is what goes in the basket. Otherwise the honest subtotals join with " + "
/// (a mass and a volume that couldn't be merged), and a numberless non-food
/// staple renders as an em dash.
String itemTotal(ShoppingItem item) {
  final inPieces = item.pieceTotal;
  if (inPieces != null) return formatPieceCount(inPieces);
  final measured = item.measureTotal;
  if (measured != null) {
    return formatMeasureCount(measured.amount, measured.measure);
  }
  if (item.totals.isEmpty) return '—';
  return item.totals.map(formatTotal).join(' + ');
}

/// The small line under an item's total: what a piece- or measure-counted row
/// weighs ("400 g") — with the round-up after it when that count is
/// fractional ("167.5 g → buy 3"), because you buy whole limes and whole cans
/// alike — or the whole-unit round-up hint. Empty when the row has none of
/// these. Never a replacement for [itemTotal] — always beside it (invariant
/// 3).
String itemSecondary(ShoppingItem item) {
  final inPieces = item.pieceTotal;
  final measured = item.measureTotal;
  final count = inPieces?.count ?? measured?.amount;
  if (count != null) {
    final weighs = item.totals.map(formatTotal).join(' + ');
    final buy = count.ceil();
    return buy > count ? '$weighs → buy $buy' : weighs;
  }
  final hint = item.wholeUnitHint;
  return hint == null ? '' : wholeUnitHintText(hint);
}

/// [itemSecondary] with what the row costs on the end — `550 g · ≈ $2.42`,
/// or `350 g · no price yet` (ADR-0017).
///
/// The estimate wears `≈` because a price is the latest one seen and not a
/// quote. A row that cannot be priced SAYS so rather than leaving a gap: a
/// silent row would read as a free one, and the shopper is the person who can
/// fix it. A free-text item and a numberless staple say nothing — neither is a
/// vocabulary row with an amount, so neither has a price to be missing.
String itemSecondaryWithCost(ShoppingItem item, {double? cents}) {
  final base = itemSecondary(item);
  final money = cents != null
      ? approxMoney(cents)
      : (item.isFreeText || !item.hasTotal ? '' : 'no price yet');
  return [if (base.isNotEmpty) base, if (money.isNotEmpty) money].join(' · ');
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
  return '${formatQuantityIn(q, unit)} ${unit.label}';
}

/// The whole-unit round-up hint under a count-food's total: "2.25 piece →
/// buy 3", or "≈ 2.25 potato, large → buy 3" when the count was derived from
/// a mass total via the measure's gram weight. Always beside the honest
/// total, never instead of it (invariant 3).
String wholeUnitHintText(WholeUnitHint h) =>
    '${h.approx ? '≈ ' : ''}${formatQuantity(h.count)} ${h.unitLabel} '
    '→ buy ${h.buy}';
