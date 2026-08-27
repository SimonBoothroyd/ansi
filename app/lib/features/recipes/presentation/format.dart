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
