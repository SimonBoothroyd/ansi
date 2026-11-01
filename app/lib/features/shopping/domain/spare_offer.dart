/// What of last week's spare food a row could take as already at home. Pure
/// Dart.
///
/// The Shop offers it and never takes it on its own: a guest or a forgotten
/// tick would leave the household short. An offer is the spare, never more
/// than the row still has to buy, said in the row's own words — a count of
/// its measure (`½ onion, medium`), a count of pieces, or its one total's
/// unit — the same words an at-home amount is stored in. A count never rounds
/// up past what is spare: it comes down to the quarter below. A row that
/// cannot weigh what it buys is offered nothing (invariant 3).
library;

import '../../../core/units/units.dart';
import '../../recipes/domain/line_basis.dart';
import 'at_home.dart';
import 'shopping.dart';

/// What [item] could take as at home of [spare] (in [row]'s basis unit), in
/// the row's own words, or null: a ticked row, one something was already said
/// about, one that cannot be at home, one whose amount will not weigh, or one
/// offered less than a gram or a quarter.
AtHomeAmount? spareOfferFor(
  ShoppingItem item, {
  required double spare,
  required IngredientBasis row,
}) {
  if (item.checked || item.atHome != null || !canBeAtHome(item)) return null;
  final all = amountForAll(item);
  final toBuy = _inBasis(item.totals, row);
  final need = _inBasis(item.need.totals, row);
  if (all == null || toBuy == null || need == null || need <= 0) return null;
  final offer = spare < toBuy ? spare : toBuy;
  if (offer < 1) return null;
  // The row's own words for its need, scaled to the offer.
  var quantity = all.quantity * offer / need;
  if (all.measure != null || all.unit.family == UnitFamily.count) {
    quantity = (quantity * 4 + 1e-9).floor() / 4;
  }
  if (quantity <= 0) return null;
  return (quantity: quantity, unit: all.unit, measure: all.measure);
}

double? _inBasis(List<Quantity> totals, IngredientBasis row) {
  var sum = 0.0;
  for (final q in totals) {
    final amount = quantityInBasis(q.amount, q.unit, row);
    if (amount == null) return null;
    sum += amount;
  }
  return sum;
}
