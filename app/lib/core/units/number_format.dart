/// The one rule for printing a number — PURE DART.
///
/// Every amount the app prints follows it: no trailing `.0`, at most two
/// decimals, no trailing zeros inside those two. A third of a pack is `0.33`,
/// not `0.3333333333333333`; a whole one is `1`, not `1.00`.
///
/// It lives here, under the units, because the surfaces that print a number
/// are spread across every feature — a recipe line, a method chip, a measure
/// label, a batch multiplier, a portion count — and a rule copied into five
/// files is a rule that will hold in four of them.
library;

/// `1`, `0.5`, `0.33`, `12.75` — the trimmed, capped rendering of [amount].
String formatNumber(double amount) {
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}
