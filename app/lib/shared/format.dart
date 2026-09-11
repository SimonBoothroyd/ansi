/// Display formatting for quantities and amounts — the recipe lines it was
/// written for, and the six other features that print a number beside a
/// unit: the Library, the week, the shopping list, the cook plan, the
/// import review and the ingredient form.
library;

import '../core/units/number_format.dart';
import '../core/units/units.dart';

/// [formatAmount] for a quantity that may not be there: an empty string for a
/// numberless line ("to taste"), the kitchen fraction otherwise.
///
/// Use [formatQuantityIn] wherever the unit is in scope — a gram figure is a
/// decimal, and only the unit knows that.
String formatQuantity(double? amount) =>
    amount == null ? '' : formatAmount(amount);

/// [formatAmountIn] for a quantity that may not be there — the unit-aware
/// twin of [formatQuantity], and what a site with a [Unit] in hand should
/// call.
String formatQuantityIn(double? amount, Unit unit) =>
    amount == null ? '' : formatAmountIn(amount, unit);

/// Formats a density (g/ml) for display: at most three significant digits,
/// trailing zeros trimmed (1.03958 → "1.04", 0.5 → "0.5", 1 → "1") — the
/// conversion line cites the density it used without a raw double's tail.
/// A value ≥ 1000 (absurd for a real density, but stored data is stored
/// data) rounds to a plain integer — `toStringAsPrecision` would render it
/// in scientific notation ("1.23e+3"), which no kitchen reads.
String formatDensity(double value) {
  if (value >= 999.5) return value.round().toString();
  final s = value.toStringAsPrecision(3);
  if (!s.contains('.')) return s;
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
