/// The one rule for printing an amount and for reading one back. Pure Dart.
///
/// [formatAmountIn] chooses by unit: metric units print as trimmed decimals
/// ([formatNumber]), everything else as kitchen fractions ([formatAmount]).
library;

import 'units.dart';

/// `1`, `0.5`, `0.33`, `12.75`: [amount] with at most two decimals and no
/// trailing zeros.
String formatNumber(double amount) {
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// The fractions a kitchen says, smallest denominator first, each with its
/// glyph. Every numerator is coprime with its denominator.
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

/// How far a stored value may sit from a fraction and still print as it: `0.67`
/// reads `⅔`, but `0.26` stays `0.26`.
const _snap = 0.0075;

/// `½`, `⅔`, `1⅛`, `12.75`: [amount] as a cook says it.
///
/// Halves, thirds, quarters and eighths print as the vulgar glyph set tight
/// against its whole (`1½`); anything else falls through to [formatNumber].
/// `fonts_carry_vulgar_fractions_test.dart` checks every bundled face carries
/// the glyphs.
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

/// [amount] as it is said in [unit]: a decimal for a metric unit
/// ([Unit.isMetric], `213.5 g`), a fraction for everything else (`⅔ cup`). A
/// figure with no unit in scope calls [formatAmount] directly.
String formatAmountIn(double amount, Unit unit) =>
    unit.isMetric ? formatNumber(amount) : formatAmount(amount);

/// The vulgar fractions a page or keyboard can hand over, as values. Wider than
/// what [formatAmount] prints: fifths and sixths are read but never written.
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

/// [text] as an amount (`1.5`, `1,5`, `2/3`, `1 1/2`, `1½`, `½`), or null when
/// it is not one.
///
/// A fraction keeps its exact value (`2/3` is 0.666…, not 0.67), so scaling
/// stays exact and the field re-prints as `⅔`.
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
