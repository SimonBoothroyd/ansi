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
