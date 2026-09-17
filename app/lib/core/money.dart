/// How the app prints money — PURE DART.
///
/// It sits in `core/`, beside `words.dart` and the amount rules under
/// `units/`, for the reason those do: a figure in dollars is printed by the
/// ingredient page,
/// the recipe's cost panel, the week's band, the shop's rows and the receipts
/// ledger, and a rule copied into five files is a rule that will hold in four
/// of them.
///
/// **Money is integer cents, USD.** There is no currency column and no
/// `Money` type: a `double` of dollars accumulates a rounding error nobody
/// asked for, and a second currency is not a thing this household has. Cents
/// are exact, they add up, and they are what the database stores.
///
/// Two spellings, and the size of the figure picks between them: **under a
/// dollar reads in cents** — `77¢`, the way a shelf tag and a receipt both
/// print it — and a dollar or more reads in dollars with both places,
/// `$3.49`, `$12.00`. Never `$0.77`, which is a spreadsheet's way of saying
/// it, and never `$3.5`.
library;

/// `$3.49`, `77¢`, `$12.00`, `-$1.00`, `0¢` — [cents] as a person says it.
///
/// The sign leads the whole figure (`-$1.00`, `-50¢`) rather than sitting
/// inside it: a negative is a deduction — an unattached discount kept as its
/// own line — and it reads as one.
String formatMoney(int cents) {
  final sign = cents.isNegative ? '-' : '';
  final magnitude = cents.abs();
  if (magnitude < 100) return '$sign$magnitude¢';
  final dollars = magnitude ~/ 100;
  final remainder = (magnitude % 100).toString().padLeft(2, '0');
  return '$sign\$$dollars.$remainder';
}

/// [formatMoney] for a **derived** figure — a price per 100 g, one line's
/// share of a pack, a week's estimate — which is a real number of cents
/// rather than a sum anybody handed over.
///
/// It rounds to the nearest whole cent, because that is the smallest thing
/// money comes in and printing a third of one would be precision the figure
/// does not have. A non-finite value (a derivation that divided by nothing)
/// has no reading at all and must never reach here: the derivations return a
/// refusal instead (invariant 3).
String formatMoneyRounded(double cents) => formatMoney(cents.round());

/// [formatMoneyRounded] to the whole DOLLAR — `$71`, `-$8` — for a figure
/// that stands for a whole list rather than for one thing.
///
/// A week's cooking and a shop's remaining trip are sums over a dozen latest
/// prices, none of them a quote; printing `$71.34` there would claim a
/// precision the figure does not have, and the two extra digits are the two a
/// person reading "about how much is this week" never wanted. A ROW keeps its
/// cents, because a row is one thing at one price and `$2.42` is checkable
/// against a shelf.
///
/// Under a dollar it falls back to [formatMoney]'s cents spelling: `$0` would
/// read as free.
String formatMoneyWhole(double cents) {
  final rounded = cents.round();
  if (rounded.abs() < 100) return formatMoney(rounded);
  final sign = rounded.isNegative ? '-' : '';
  return '$sign\$${(rounded.abs() / 100).round()}';
}

/// [cents] as the **Paid** field takes it back — `349` → `3.49`, `300` →
/// `3.00`.
///
/// The round trip of [parseMoney], and the one spelling a field can be seeded
/// with: both places, never [formatMoney]'s reading, because a field that
/// opened on `77¢` would be a field nobody could edit. It stays integer
/// arithmetic — money is cents, and dividing by 100 to print it would put a
/// float where the exactness is the whole point. Non-negative, because a price
/// is what was paid.
String dollarsTyped(int cents) {
  final pennies = (cents % 100).toString().padLeft(2, '0');
  return '${cents ~/ 100}.$pennies';
}

/// A typed sum of **dollars** as whole cents — `3.49` → 349, `3` → 300,
/// `.5` → 50 — or null when [text] is not one.
///
/// It is the twin of [formatMoney] on the way in, and it is deliberately not
/// the amount parser under `units/`: a sum of money is not a kitchen amount.
/// Nobody pays ⅔ of a dollar, a `/` in a price field is a typo rather than a
/// fraction, and a third decimal is money that does not exist — so a fraction
/// and a third place are both refused rather than rounded into something the
/// person did not type.
///
/// A comma reads as the decimal separator, the way the amount parser reads it,
/// and a leading `\$` is tolerated for the person who types the symbol the
/// field already prints. Nothing negative: a price is what was paid.
int? parseMoney(String text) {
  final trimmed = text.trim().replaceAll(',', '.');
  final digits = trimmed.startsWith(r'$')
      ? trimmed.substring(1).trimLeft()
      : trimmed;
  final match = RegExp(r'^([0-9]*)(?:\.([0-9]{0,2}))?$').firstMatch(digits);
  if (match == null) return null;
  final whole = match.group(1) ?? '';
  final fraction = match.group(2);
  // `.` alone, or an empty field: not a sum, which is different from zero.
  if (whole.isEmpty && (fraction == null || fraction.isEmpty)) return null;
  final dollars = whole.isEmpty ? 0 : int.parse(whole);
  final cents = fraction == null || fraction.isEmpty
      ? 0
      : int.parse(fraction.padRight(2, '0'));
  return dollars * 100 + cents;
}
