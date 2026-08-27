/// Display formatting for the Shop screen — pure Dart (no widgets), so the
/// quantity/total copy is unit-testable.
library;

import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart' show formatQuantity;
import '../domain/shopping.dart';

/// Formats one [Quantity] for the list, e.g. "500 g", "1.5 kg", "5 piece".
String formatTotal(Quantity q) => '${formatQuantity(q.amount)} ${q.unit.label}';

/// An item's rolled-up total for the right-hand column. Joins honest subtotals
/// with " + " (a mass and a volume that couldn't be merged), and renders a
/// numberless non-food staple as an em dash.
String itemTotal(ShoppingItem item) {
  if (item.totals.isEmpty) return '—';
  return item.totals.map(formatTotal).join(' + ');
}

/// A provenance line's quantity ("300 g"), or empty when it carries none.
String contributionQuantity(ShoppingContribution c) {
  final q = c.quantity;
  final unit = c.unit;
  if (q == null || unit == null) return '';
  return '${formatQuantity(q)} ${unit.label}';
}
