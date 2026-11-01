/// What of last week's spare food a row could take as already at home. Pure
/// Dart.
///
/// The Shop offers it and never takes it on its own: a guest or a forgotten
/// tick would leave the household short. An offer is the spare, never more
/// than the row still has to buy, in the row's basis unit; a row that cannot
/// weigh what it buys is offered nothing (invariant 3).
library;

import '../../recipes/domain/line_basis.dart';
import 'at_home.dart';
import 'shopping.dart';

/// The amount of [spare] (in [row]'s basis unit) [item] could take as at home,
/// or null: a ticked row, one something was already said about, one that
/// cannot be at home, one whose amount will not weigh, or under a gram.
double? spareOfferFor(
  ShoppingItem item, {
  required double spare,
  required IngredientBasis row,
}) {
  if (item.checked || item.atHome != null || !canBeAtHome(item)) return null;
  var toBuy = 0.0;
  for (final q in item.totals) {
    final amount = quantityInBasis(q.amount, q.unit, row);
    if (amount == null) return null;
    toBuy += amount;
  }
  final offer = spare < toBuy ? spare : toBuy;
  return offer < 1 ? null : offer;
}
