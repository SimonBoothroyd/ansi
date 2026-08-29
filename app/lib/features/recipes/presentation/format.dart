/// Display formatting for recipe quantities.
library;

/// Formats a scaled quantity for display: no trailing `.0`, at most two
/// decimals, and an empty string for a numberless line ("to taste").
String formatQuantity(double? amount) {
  if (amount == null) return '';
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Formats a density (g/ml) for display: at most three significant digits,
/// trailing zeros trimmed (1.03958 → "1.04", 0.5 → "0.5", 1 → "1") — the
/// conversion line cites the density it used without a raw double's tail.
String formatDensity(double value) {
  final s = value.toStringAsPrecision(3);
  if (!s.contains('.')) return s;
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
