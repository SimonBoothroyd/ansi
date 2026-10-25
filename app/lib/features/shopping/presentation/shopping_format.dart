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

/// The week menu row's trailing label on the Shop tab: `6 items` / `1 item` /
/// `nothing to buy`.
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
/// reads its count ("2½ piece"); an item asked for in one measure reads in it
/// ("1 can (400 g), drained"). Otherwise the subtotals join with " + ", and a
/// numberless staple renders as an em dash.
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
/// weighs ("400 g"), with the round-up after a fractional count ("167.5 g → buy
/// 3"), or the whole-unit hint. Empty when none apply. Always beside
/// [itemTotal], never instead of it.
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

/// [itemSecondary] with the row's cost on the end: `550 g · ≈ $2.42`, or `350 g
/// · no price yet` (ADR-0017). `≈` because a price is the latest seen, not a
/// quote.
///
/// `no price yet` appears only when [anyPriced]: a household with no prices at
/// all is not nagged row by row. A free-text item and a numberless staple say
/// nothing either way.
String itemSecondaryWithCost(
  ShoppingItem item, {
  double? cents,
  bool anyPriced = false,
}) {
  final base = itemSecondary(item);
  final missing = anyPriced && !item.isFreeText && item.hasTotal;
  final money = cents != null
      ? approxMoney(cents)
      : (missing ? 'no price yet' : '');
  return [if (base.isNotEmpty) base, if (money.isNotEmpty) money].join(' · ');
}

/// A provenance line's quantity ("300 g", or "2 potato, large" when counted in
/// a measure), or empty when it carries none.
String contributionQuantity(ShoppingContribution c) {
  final q = c.quantity;
  if (q == null) return '';
  final measure = c.measure;
  if (measure != null) return formatMeasureCount(q, measure);
  final unit = c.unit;
  if (unit == null) return '';
  return '${formatQuantityIn(q, unit)} ${unit.label}';
}

/// The whole-unit hint under a count-food's total: "2.25 piece → buy 3", or "≈
/// 2.25 potato, large → buy 3" when the count was derived from a mass total.
/// Always beside the total.
String wholeUnitHintText(WholeUnitHint h) =>
    '${h.approx ? '≈ ' : ''}${formatQuantity(h.count)} ${h.unitLabel} '
    '→ buy ${h.buy}';

// --- What is already at home ----------------------------------------------

/// [item]'s total before anything at home came off it — what the week asks
/// for, in the words [itemTotal] uses.
String needTotal(ShoppingItem item) {
  final need = item.need;
  return itemTotal(
    item.copyWith(
      totals: need.totals,
      measureTotal: need.measureTotal,
      pieceTotal: need.pieceTotal,
    ),
  );
}

/// The amount said at home, as briefly as the row allows: a bare count when
/// it is counted in the measure the row itself is counted in (`5`), else the
/// amount with its words (`200 g`, `1 cup`, `2 onion, medium`). An imprecise
/// word says nothing (`to taste` has no amount to repeat).
String atHomeAmount(ShoppingItem item, {bool bare = false}) {
  final a = item.atHome;
  if (a == null) return '';
  final measure = a.measure;
  if (measure != null) {
    final sameMeasure = item.need.measureTotal?.measure.id == measure.id;
    return sameMeasure
        ? formatQuantity(a.quantity)
        : formatMeasureCount(a.quantity, measure);
  }
  final unit = a.unit;
  if (unit == null) return formatQuantity(a.quantity);
  if (unit.family == UnitFamily.imprecise) return '';
  if (bare && _needUnit(item) == unit) {
    return formatQuantityIn(a.quantity, unit);
  }
  return '${formatQuantityIn(a.quantity, unit)} ${unit.label}';
}

Unit? _needUnit(ShoppingItem item) {
  final totals = item.need.totals;
  return totals.length == 1 ? totals.single.unit : null;
}

/// What the sub-line opens with on a row that is partly at home: `200 g at
/// home`, `5 at home`, or `1 cup at home · not counted (no density)` when the
/// amount could not come off honestly. Empty when nothing was said.
String atHomeWords(ShoppingItem item) {
  final a = item.atHome;
  if (a == null) return '';
  final amount = atHomeAmount(item);
  final words = amount.isEmpty ? 'at home' : '$amount at home';
  final refusal = a.refusal;
  return refusal == null ? words : '$words · not counted ($refusal)';
}

/// The amount chip in the checking pass: the need when nothing is said
/// (`500 g`), `all 5` or `all 500 g` when it is all at home, `200 of 500 g`
/// for a part, and `1 cup · not counted` when the amount could not come off.
String atHomeChip(ShoppingItem item) {
  final a = item.atHome;
  final need = needTotal(item);
  if (a == null) return need;
  if (a.refusal != null) return '${atHomeAmount(item)} · not counted';
  if (a.all) {
    final counted = item.need.measureTotal;
    if (counted != null) return 'all ${formatQuantity(counted.amount)}';
    final measurable = item.need.totals.where(
      (t) => t.unit.family != UnitFamily.imprecise,
    );
    return measurable.isEmpty ? 'got it' : 'all $need';
  }
  return '${atHomeAmount(item, bare: true)} of $need';
}
