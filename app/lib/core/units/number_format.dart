/// The one rule for printing an amount, and the one rule for reading one
/// back — PURE DART.
///
/// Every amount the app prints follows it: a kitchen fraction where the
/// number is one ([formatAmount]), and otherwise no trailing `.0`, at most
/// two decimals, no trailing zeros inside those two ([formatNumber]). A third
/// of a pack is `⅓`, not `0.3333333333333333`; a whole one is `1`, not
/// `1.00`.
///
/// Which of the two a figure gets depends on its unit, and [formatAmountIn]
/// is the door that knows: a scale and a jug read decimals, a cook's hand
/// reads fractions.
///
/// It lives here, under the units, because the surfaces that print a number
/// are spread across every feature — a recipe line, a method chip, a measure
/// label, a batch multiplier, a portion count — and a rule copied into five
/// files is a rule that will hold in four of them.
library;

import 'units.dart';

/// `1`, `0.5`, `0.33`, `12.75` — the trimmed, capped rendering of [amount].
///
/// The fallback under [formatAmount], and the right rule on its own only for
/// a figure no kitchen says in halves.
String formatNumber(double amount) {
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// The fractions a kitchen says out loud, smallest denominator first — so a
/// half is offered as `½` before a quarter can claim `2/4` — each paired with
/// the glyph it prints as. Every numerator here is coprime with its
/// denominator: `2/4` is a half, and the half is already in the list.
const _fractions = <(int, int, String)>[
  (1, 2, '½'),
  (1, 3, '⅓'),
  (2, 3, '⅔'),
  (1, 4, '¼'),
  (3, 4, '¾'),
  (1, 8, '⅛'),
  (3, 8, '⅜'),
  (5, 8, '⅝'),
  (7, 8, '⅞'),
];

/// How far a stored value may sit from a fraction and still BE it.
///
/// Wide enough that a value already rounded on its way in prints as the
/// fraction it came from — `0.67` reads `2/3`, `0.13` reads `1/8` — and tight
/// enough that a number somebody actually meant survives: `0.26` is `0.26`,
/// not a quarter.
const _snap = 0.0075;

/// `½`, `⅔`, `1⅛`, `12.75` — [amount] as a cook says it.
///
/// Halves, thirds, quarters and eighths print as the **vulgar glyph**, set
/// tight against its whole: `1½`, never `1 ½` and never `1 1/2`. A slash is
/// two characters pretending to be one, and it wraps; the glyph is the
/// typographic form a recipe is printed in. Every bundled face carries all
/// nine — `test/structure/fonts_carry_vulgar_fractions_test.dart` reads each
/// font's `cmap` and fails if one stops. Anything else falls through to
/// [formatNumber].
String formatAmount(double amount) {
  if (!amount.isFinite) return formatNumber(amount);
  final sign = amount.isNegative ? '-' : '';
  final magnitude = amount.abs();
  final whole = magnitude.floorToDouble();
  final part = magnitude - whole;
  for (final (numerator, denominator, glyph) in _fractions) {
    if ((part - numerator / denominator).abs() > _snap) continue;
    final lead = whole == 0 ? '' : formatNumber(whole);
    return '$sign$lead$glyph';
  }
  return formatNumber(amount);
}

/// [amount] as it is said **in [unit]** — the door every site with a unit in
/// scope prints through.
///
/// A metric mass or volume ([Unit.isMetric] — `g`, `kg`, `ml`, `l`) is a
/// reading off a scale or a jug, so it prints as a decimal: `213.5 g`, never
/// `213½ g`; `1.5 l`, never `1½ l`. Every other unit is something a cook says
/// by hand — cups, spoons, fl oz, oz, lb, pieces, measures, servings, batches
/// — and keeps its fractions: `⅔ cup`, `2¼ potato, large`.
///
/// A figure with no unit in scope (a bare count, a scale factor) calls
/// [formatAmount] directly; it is the kitchen rule, and a unitless number in
/// this app is always a kitchen one.
String formatAmountIn(double amount, Unit unit) =>
    unit.isMetric ? formatNumber(amount) : formatAmount(amount);

/// The vulgar fractions a page (or a keyboard) can offer, as their values.
///
/// Wider than the nine [formatAmount] prints: fifths and sixths are read back
/// because a source page or an iOS keyboard can hand one over, even though no
/// kitchen rule writes them.
const _vulgar = <String, double>{
  '¼': 0.25,
  '½': 0.5,
  '¾': 0.75,
  '⅓': 1 / 3,
  '⅔': 2 / 3,
  '⅕': 0.2,
  '⅖': 0.4,
  '⅗': 0.6,
  '⅘': 0.8,
  '⅙': 1 / 6,
  '⅛': 0.125,
  '⅜': 0.375,
  '⅝': 0.625,
  '⅞': 0.875,
};

/// [text] as an amount: `1.5`, `1,5`, `2/3`, `1 1/2`, `1½`, `½`. Null when it
/// is not one — which is the parser's whole refusal path.
///
/// It reads **both** forms on purpose: the app prints glyphs, and a person
/// types `2/3` on a keyboard that has no `½` key.
///
/// A fraction stores its own value, not its printed rounding: `2/3` is
/// 0.666…, never 0.67, so scaling a recipe by it stays honest and the field
/// it came from re-prints as `⅔`.
double? parseAmount(String text) {
  var rest = text.trim().replaceAll(',', '.');
  if (rest.isEmpty) return null;
  final negative = rest.startsWith('-');
  if (negative) rest = rest.substring(1).trimLeft();
  final value = _unsigned(rest);
  if (value == null) return null;
  return negative ? -value : value;
}

double? _unsigned(String text) {
  final plain = double.tryParse(text);
  if (plain != null) return plain;

  // A vulgar glyph, alone ("½") or after a whole number ("1½", "1 ½").
  final glyph = _vulgar[text.substring(text.length - 1)];
  if (glyph != null) {
    final whole = text.substring(0, text.length - 1).trim();
    if (whole.isEmpty) return glyph;
    final leading = double.tryParse(whole);
    return leading == null ? null : leading + glyph;
  }

  final typed = RegExp(
    r'^(?:([0-9]+)\s+)?([0-9]+)\s*/\s*([0-9]+)$',
  ).firstMatch(text);
  if (typed == null) return null;
  final denominator = double.parse(typed.group(3)!);
  if (denominator == 0) return null;
  final whole = typed.group(1) == null ? 0.0 : double.parse(typed.group(1)!);
  return whole + double.parse(typed.group(2)!) / denominator;
}
