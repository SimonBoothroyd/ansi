/// How the app prints money. Pure Dart.
///
/// Money is integer cents, USD: exact, summable, and what the database
/// stores. Under a dollar reads in cents (`77¢`); a dollar or more reads
/// with both places (`$3.49`, `$12.00`).
library;

/// `$3.49`, `77¢`, `$12.00`, `-$1.00`, `0¢`. The sign leads the whole
/// figure.
String formatMoney(int cents) {
  final sign = cents.isNegative ? '-' : '';
  final magnitude = cents.abs();
  if (magnitude < 100) return '$sign$magnitude¢';
  final dollars = magnitude ~/ 100;
  final remainder = (magnitude % 100).toString().padLeft(2, '0');
  return '$sign\$$dollars.$remainder';
}

/// [formatMoney] for a derived figure (a price per 100 g, a line's share of
/// a pack), rounded to the nearest cent. A non-finite value must never reach
/// here: derivations return a refusal instead.
String formatMoneyRounded(double cents) => formatMoney(cents.round());

/// [formatMoneyRounded] to the whole dollar (`$71`, `-$8`), for a figure
/// summed over many prices, where cents would claim false precision. Under a
/// dollar it falls back to [formatMoney], because `$0` would read as free.
String formatMoneyWhole(double cents) {
  final rounded = cents.round();
  if (rounded.abs() < 100) return formatMoney(rounded);
  final sign = rounded.isNegative ? '-' : '';
  return '$sign\$${(rounded.abs() / 100).round()}';
}

/// [cents] as a price field takes it back: `349` → `3.49`, `300` → `3.00`.
/// The round trip of [parseMoney]. Integer arithmetic; non-negative.
String dollarsTyped(int cents) {
  final pennies = (cents % 100).toString().padLeft(2, '0');
  return '${cents ~/ 100}.$pennies';
}

/// A typed sum of dollars as whole cents (`3.49` → 349, `3` → 300, `.5` →
/// 50), or null when [text] is not one.
///
/// Not the kitchen amount parser: a fraction and a third decimal place are
/// refused, not rounded. A comma reads as the decimal separator and a
/// leading `\$` is tolerated. Nothing negative.
int? parseMoney(String text) {
  final trimmed = text.trim().replaceAll(',', '.');
  final digits = trimmed.startsWith(r'$')
      ? trimmed.substring(1).trimLeft()
      : trimmed;
  final match = RegExp(r'^([0-9]*)(?:\.([0-9]{0,2}))?$').firstMatch(digits);
  if (match == null) return null;
  final whole = match.group(1) ?? '';
  final fraction = match.group(2);
  // `.` alone or an empty field is not a sum, which differs from zero.
  if (whole.isEmpty && (fraction == null || fraction.isEmpty)) return null;
  final dollars = whole.isEmpty ? 0 : int.parse(whole);
  final cents = fraction == null || fraction.isEmpty
      ? 0
      : int.parse(fraction.padRight(2, '0'));
  return dollars * 100 + cents;
}
