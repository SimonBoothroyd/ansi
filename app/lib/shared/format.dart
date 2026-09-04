/// Display formatting for quantities and amounts — the recipe lines it was
/// written for, and the six other features that print a number beside a
/// unit: the Library, the week, the shopping list, the cook plan, the
/// import review and the ingredient form.
library;

import '../core/units/number_format.dart';

/// [formatNumber] for a quantity that may not be there: an empty string for a
/// numberless line ("to taste"), the trimmed number otherwise.
String formatQuantity(double? amount) =>
    amount == null ? '' : formatNumber(amount);

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
