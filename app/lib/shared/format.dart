/// Display formatting for quantities and amounts, shared by every feature
/// that prints a number beside a unit.
library;

import '../core/units/number_format.dart';
import '../core/units/units.dart';

/// [formatAmount] for a quantity that may not be there: an empty string for a
/// numberless line ("to taste"). Use [formatQuantityIn] wherever the unit is
/// in scope.
String formatQuantity(double? amount) =>
    amount == null ? '' : formatAmount(amount);

/// [formatAmountIn] for a quantity that may not be there.
String formatQuantityIn(double? amount, Unit unit) =>
    amount == null ? '' : formatAmountIn(amount, unit);

/// Formats a density (g/ml): at most three significant digits, trailing zeros
/// trimmed (1.03958 → "1.04"). A value ≥ 1000 rounds to a plain integer,
/// which `toStringAsPrecision` would render in scientific notation.
String formatDensity(double value) {
  if (value >= 999.5) return value.round().toString();
  final s = value.toStringAsPrecision(3);
  if (!s.contains('.')) return s;
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
