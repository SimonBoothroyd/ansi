/// What is already at home, taken off a row's need. Pure Dart.
///
/// Somebody goes down the list in the kitchen before a trip and says what is
/// in the cupboard: all of a row, or an amount of it. The amount is stored as
/// said ([AtHomeInput]) and subtracted here from the need [buildShoppingList]
/// summed, so the row's total becomes what is left to buy.
///
/// The subtraction is honest (invariant 3). An amount comes off the row's one
/// measurable total through the bridges the sum itself uses — the ratio table,
/// a density, a measure's weight, the row's piece weight — or it does not come
/// off at all, and the row says why in the list's *not counted* grammar.
/// Imprecise words (`pinch`, `to taste`) are not amounts anybody buys, so they
/// ride along: once the measurable total is covered, the whole row is at home.
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'shopping.dart';

/// A stored amount at home, as `buildShoppingList` reads it: `quantity` in
/// `unit`, or counted in `measure` (then `unit` is `piece`). `unit` is null
/// when the stored id is unrecognised (`rawUnit` keeps it); `measureId` is the
/// stored FK verbatim, kept while the measure row is unsynced. `updatedAt`
/// (ISO-8601) picks the newest amount when two offline entries both carry one.
typedef AtHomeInput = ({
  String entryId,
  double quantity,
  Unit? unit,
  String? rawUnit,
  String? measureId,
  Measure? measure,
  String? updatedAt,
});

/// A row's need, before anything was taken off: the shape
/// [ShoppingItem.totals], [ShoppingItem.measureTotal] and
/// [ShoppingItem.pieceTotal] have.
typedef ShoppingNeed = ({
  List<Quantity> totals,
  MeasureAmount? measureTotal,
  PieceTotal? pieceTotal,
});

/// What [ShoppingItem.atHome] carries: the amount as said, the `need` it was
/// taken from, whether it covers the row (`all`) and, when it could not be
/// taken off honestly, the `refusal` the sub-line prints after it.
typedef AtHome = ({
  double quantity,
  Unit? unit,
  Measure? measure,
  String? measureId,
  ShoppingNeed need,
  bool all,
  String? refusal,
});

/// The amount `ShoppingRepository.setAtHome` stores for "all of it": the
/// need as it stands, in the words the row prints it. Null when the row
/// cannot take an amount (two measurable totals, or no total at all).
typedef AtHomeAmount = ({double quantity, Unit unit, Measure? measure});

/// The result of [leftToBuy].
sealed class LeftToBuy {
  const LeftToBuy();
}

/// Some of the row is still to buy: the row's new totals, recomputed counts.
final class SomeLeft extends LeftToBuy {
  const SomeLeft(this.left);
  final ShoppingNeed left;
}

/// The amount covers the row.
final class AllAtHome extends LeftToBuy {
  const AllAtHome();
}

/// The amount cannot come off honestly; [reason] reads after *not counted*.
final class NotCounted extends LeftToBuy {
  const NotCounted(this.reason);
  final String reason;
}

/// How much of a total counts as nothing left (float noise from conversions).
const _epsilon = 1e-9;

/// Takes [quantity] of [unit] (or of [measure]) off [need], the row's summed
/// total. [densityGPerMl] and [pieceMeasure] (the row's piece weight as a
/// measure, ADR-0015) are the only bridges across units.
///
/// - The need's **imprecise words** are not amounts: they never block, and
///   they stay on what is left.
/// - A row of **words only** (`to taste`) is all at home whatever was said.
/// - A row with **two measurable totals** (mass and volume with no density,
///   or a bare `piece` beside a weight) cannot take an amount.
/// - An amount counted in the measure the row is **counted in** comes off the
///   count; anything else converts into the total's unit first.
LeftToBuy leftToBuy({
  required ShoppingNeed need,
  required double quantity,
  required Unit? unit,
  required Measure? measure,
  double? densityGPerMl,
  Measure? pieceMeasure,
}) {
  final words = [
    for (final t in need.totals)
      if (t.unit.family == UnitFamily.imprecise) t,
  ];
  final measurable = [
    for (final t in need.totals)
      if (t.unit.family != UnitFamily.imprecise) t,
  ];
  if (measurable.isEmpty) {
    return need.totals.isEmpty
        ? const NotCounted('nothing to take it from')
        : const AllAtHome();
  }
  if (measurable.length > 1) {
    final families = {for (final t in measurable) t.unit.family};
    return NotCounted(
      families.contains(UnitFamily.count) ? 'no piece weight' : 'no density',
    );
  }
  if (unit == null && measure == null) {
    return const NotCounted('unrecognised unit');
  }
  final total = measurable.single;

  // Counted in the row's own measure: a count off a count.
  final counted = need.measureTotal;
  if (counted != null && measure != null && measure.id == counted.measure.id) {
    final left = counted.amount - quantity;
    if (left <= _epsilon * counted.amount.abs().clamp(1, double.infinity)) {
      return const AllAtHome();
    }
    final ratio = left / counted.amount;
    return SomeLeft((
      totals: [Quantity(total.amount * ratio, total.unit), ...words],
      measureTotal: (amount: left, measure: counted.measure),
      pieceTotal: null,
    ));
  }

  // Anything else converts into the total's own unit.
  final Result<Quantity> said;
  if (measure != null) {
    said = convertMeasure(
      quantity,
      measure,
      to: total.unit,
      densityGPerMl: densityGPerMl,
    );
  } else if (unit == pieces && total.unit != pieces && pieceMeasure != null) {
    said = convertMeasure(
      quantity,
      pieceMeasure,
      to: total.unit,
      densityGPerMl: densityGPerMl,
    );
  } else {
    said = convert(
      Quantity(quantity, unit!),
      to: total.unit,
      densityGPerMl: densityGPerMl,
    );
  }
  final double off;
  switch (said) {
    case Ok(:final value):
      off = value.amount;
    case Err(:final failure):
      return NotCounted(_reasonFor(failure.code, unit, total.unit));
  }

  final left = total.amount - off;
  if (left <= _epsilon * total.amount.abs().clamp(1, double.infinity)) {
    return const AllAtHome();
  }
  final leftTotal = Quantity(left, total.unit);

  // A row bought in a measure keeps being bought in it.
  MeasureAmount? measureTotal;
  if (counted != null) {
    final inMeasure = amountInMeasure(
      leftTotal,
      counted.measure,
      densityGPerMl: densityGPerMl,
    );
    if (inMeasure case Ok(:final value)) {
      measureTotal = (amount: value, measure: counted.measure);
    }
  }
  PieceTotal? pieceTotal;
  final pieceNeed = need.pieceTotal;
  if (pieceNeed != null && pieceMeasure != null && measureTotal == null) {
    final inPieces = amountInMeasure(
      leftTotal,
      pieceMeasure,
      densityGPerMl: densityGPerMl,
    );
    if (inPieces case Ok(:final value)) {
      pieceTotal = (count: value, approx: pieceNeed.approx);
    }
  }
  return SomeLeft((
    totals: [leftTotal, ...words],
    measureTotal: measureTotal,
    pieceTotal: pieceTotal,
  ));
}

String _reasonFor(String code, Unit? said, Unit total) => switch (code) {
  'unit/no_density' => 'no density',
  'unit/imprecise' => 'not an amount',
  'measure/invalid_amount' => 'invalid measure',
  _ when said == pieces || total == pieces => 'no piece weight',
  _ => '${said?.label ?? 'unit'} does not convert to ${total.label}',
};

/// The amount "all of it" stores for [item]: its need as the row prints it —
/// a count of its measure, a count of pieces, its one measurable total, or,
/// on a row of words only, one of its first word. Null when the row has two
/// measurable totals (it cannot take an amount) or no total at all.
AtHomeAmount? amountForAll(ShoppingItem item) {
  final need = item.need;
  final counted = need.measureTotal;
  if (counted != null) {
    return (quantity: counted.amount, unit: pieces, measure: counted.measure);
  }
  final measurable = [
    for (final t in need.totals)
      if (t.unit.family != UnitFamily.imprecise) t,
  ];
  if (measurable.length > 1) return null;
  final piecesNeed = need.pieceTotal;
  if (piecesNeed != null) {
    return (quantity: piecesNeed.count, unit: pieces, measure: null);
  }
  if (measurable.length == 1) {
    final t = measurable.single;
    return (quantity: t.amount, unit: t.unit, measure: null);
  }
  if (need.totals.isEmpty) return null;
  return (quantity: 1, unit: need.totals.first.unit, measure: null);
}

/// Why [item] cannot take an amount, or null when it can: its need is two
/// measurable totals with no bridge between them. Printed in the checking
/// pass beside the muted house, so the row is never silently left out.
String? whyNotAtHome(ShoppingItem item) {
  if (item.isFreeText || amountForAll(item) != null) return null;
  final measurable = {
    for (final t in item.need.totals)
      if (t.unit.family != UnitFamily.imprecise) t.unit.family,
  };
  if (measurable.length < 2 && item.need.totals.length < 2) {
    return 'nothing to take it from';
  }
  return measurable.contains(UnitFamily.count)
      ? 'two units · no piece weight'
      : 'two units · no density';
}

/// Whether [item] can take an amount at home at all: an ingredient row, not
/// ticked, whose need is one measurable total (with any words beside it) or
/// words only.
bool canBeAtHome(ShoppingItem item) =>
    !item.isFreeText && !item.checked && amountForAll(item) != null;

/// Picks the amount [entries] carry for one ingredient: the most recently
/// updated, so a later say on either phone wins over an offline duplicate.
AtHomeInput? newestAtHome(Iterable<AtHomeInput> entries) {
  AtHomeInput? newest;
  for (final e in entries) {
    if (newest == null ||
        (e.updatedAt ?? '').compareTo(newest.updatedAt ?? '') > 0) {
      newest = e;
    }
  }
  return newest;
}
