/// Display formatting for the Shop screen — pure Dart (no widgets), so the
/// quantity/total copy is unit-testable.
library;

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/cost_words.dart' show shopRowCost;
import '../../../shared/format.dart' show formatQuantity, formatQuantityIn;
import '../../ingredients/domain/cost_price.dart';
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

/// An item's amount as the plan sums it, before any rounding. A
/// piece-weighted row reads its count ("2½ piece"); an item asked for in one
/// measure reads in it ("1 can (400 g), drained"). Otherwise the subtotals join
/// with " + ", and a numberless staple renders as an em dash. What the week
/// asks for is said in these words ([needTotal]), and so is what is left to
/// buy in the at-home sheet.
String itemAmount(ShoppingItem item) {
  final inPieces = item.pieceTotal;
  if (inPieces != null) return formatPieceCount(inPieces);
  final measured = item.measureTotal;
  if (measured != null) {
    return formatMeasureCount(measured.amount, measured.measure);
  }
  if (item.totals.isEmpty) return '—';
  return item.totals.map(formatTotal).join(' + ');
}

/// What a row that rounds is bought as: the whole count, the word it is
/// counted in, and the fractional need behind it (`approx` when that need was
/// read back from a weight). Null on a row that does not round.
typedef ItemRoundUp = ({int buy, String label, double need, bool approx});

/// The round-up of [item], or null. A row rounds when its count is
/// fractional: a measure count (`2½ lime, whole`), a piece count (`≈ 2½
/// piece`), or the whole-unit hint on a total that is not counted (`600 g`
/// with `≈ 2¼ potato, large`). You buy whole limes, so the whole number is
/// what the row leads with ([itemTotal]).
ItemRoundUp? itemRoundUp(ShoppingItem item) {
  final inPieces = item.pieceTotal;
  if (inPieces != null) {
    return _fractional(inPieces.count)
        ? (
            buy: inPieces.count.ceil(),
            label: pieces.label,
            need: inPieces.count,
            approx: inPieces.approx,
          )
        : null;
  }
  final measured = item.measureTotal;
  if (measured != null) {
    return _fractional(measured.amount)
        ? (
            buy: measured.amount.ceil(),
            label: measured.measure.label,
            need: measured.amount,
            approx: false,
          )
        : null;
  }
  final hint = item.wholeUnitHint;
  if (hint == null) return null;
  return (
    buy: hint.buy,
    label: hint.unitLabel,
    need: hint.count,
    approx: hint.approx,
  );
}

/// A count that is not a whole number, ignoring the float noise a sum of
/// fractions leaves behind (`2.9999999` is three limes, not a round-up).
bool _fractional(double v) => v > 0 && (v - v.round()).abs() > 1e-9;

/// An item's headline, the figure the row leads with. A row that rounds
/// prints the whole count bought (`3 lime, whole`), and its need moves to the
/// sub-line ([itemSecondary]); any other row prints [itemAmount].
String itemTotal(ShoppingItem item) {
  final round = itemRoundUp(item);
  if (round == null) return itemAmount(item);
  return '${round.buy} ${round.label}';
}

/// The need on a row that rounds, as the sub-line opens with it: `need 2½`,
/// or `need ≈ 2¼` when the count was read back from a weight. The `≈` stays
/// on the need, because the need is the approximate part. Empty on a row that
/// does not round.
String itemNeed(ShoppingItem item) {
  final round = itemRoundUp(item);
  if (round == null) return '';
  return 'need ${round.approx ? '≈ ' : ''}${formatQuantity(round.need)}';
}

/// The small line under an item's headline: the need on a row that rounds
/// ([itemNeed]), then what a counted row weighs (`167.5 g`). A rounded mass
/// total weighs what it says (`need ≈ 2¼ · 600 g`); a fractional plain count
/// says only its need, since its total is the need. Empty when none apply.
/// Always beside [itemTotal], never instead of it (invariant 3).
String itemSecondary(ShoppingItem item) {
  final counted = item.pieceTotal != null || item.measureTotal != null;
  final hint = item.wholeUnitHint;
  final weighs =
      counted ||
          (hint != null &&
              item.totals.every((t) => t.unit.family != UnitFamily.count))
      ? item.totals.map(formatTotal).join(' + ')
      : '';
  return [itemNeed(item), weighs].where((part) => part.isNotEmpty).join(' · ');
}

/// The row's whole sub-line, in its order: what is at home ([atHomeWords]),
/// then the need, the weight and the price ([itemSecondaryWithCost]), each
/// only when it applies — `5 at home · need 1½ · 165 g · $1.54 at Aldi`.
String itemSubLine(
  ShoppingItem item, {
  double? cents,
  ShopPrice? price,
  bool anyPriced = false,
}) => [
  atHomeWords(item),
  itemSecondaryWithCost(item, cents: cents, price: price, anyPriced: anyPriced),
].where((part) => part.isNotEmpty).join(' · ');

/// [itemSecondary] with the row's cost on the end: `550 g · $1.80 at Aldi`,
/// or `350 g · no price yet` (ADR-0017). [cents] is the row's figure and
/// [price] the price it was read at ([shopRowCost] says which).
///
/// `no price yet` appears only when [anyPriced]: a household with no prices at
/// all is not nagged row by row. A free-text item and a numberless staple say
/// nothing either way.
String itemSecondaryWithCost(
  ShoppingItem item, {
  double? cents,
  ShopPrice? price,
  bool anyPriced = false,
}) {
  final base = itemSecondary(item);
  final missing = anyPriced && !item.isFreeText && item.hasTotal;
  final money = cents != null && price != null
      ? shopRowCost(cents, price)
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

// --- What is already at home ----------------------------------------------

/// [item]'s total before anything at home came off it — what the week asks
/// for, in the words [itemAmount] uses, never rounded up: the at-home pass
/// weighs what is here against the need.
String needTotal(ShoppingItem item) {
  final need = item.need;
  return itemAmount(
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
