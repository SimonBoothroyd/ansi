/// Portion counts said the way a kitchen says them — PURE DART.
///
/// A portion count became fractional with the per-member portion factor
/// (plan 0027, front P): "my wife eats ¾ what I do" makes a meal for both
/// `1¾ portions`, and the ruling (P-D4) is that the fraction is PRINTED as one
/// — `½ ¾ ¼` glyphs, never `1.75`, never rounded silently to a whole. Every
/// surface that says a portion count — the meal editor, the cook session row,
/// the whole-batch nudge, the per-person macro lens — goes through
/// [formatFraction] / [formatPortions] so they cannot drift into three
/// spellings of the same number.
///
/// Only the quarter glyphs are used (`¼ ½ ¾`, Latin-1, present in every
/// bundled face). The factor is set in quarter steps and any sum of quarters
/// is a quarter, so those cover every demand the household can state; a value
/// that is NOT a quarter (a person's share under an override — `3 × ¾ ⁄ 1¾ =
/// 1.29`, or a leftover against a `serves 2.5` recipe) prints as a trimmed
/// decimal rather than a glyph the fonts might lack
/// ([[mise-forui-icons-not-unicode-glyphs]]).
library;

/// `1¾`, `½`, `2`, `1.29` — a count with its quarter as a glyph, a whole
/// number plain, and anything else as at most two trimmed decimals. Never
/// `1.75`, never `2.0`.
String formatFraction(double value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  final whole = abs.floor();
  final rem = abs - whole;
  // Float noise on a whole (0.1 + 0.2 shapes) rounds to the whole.
  if (rem < _tolerance) return '$sign$whole';
  if (1 - rem < _tolerance) return '$sign${whole + 1}';
  for (final (quarter, glyph) in _quarters) {
    if ((rem - quarter).abs() < _tolerance) {
      return '$sign${whole == 0 ? '' : whole}$glyph';
    }
  }
  // Not a quarter: at most two decimals, trimmed.
  final fixed = abs.toStringAsFixed(2);
  return sign +
      fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

/// `1 portion`, `¾ portion`, `1¾ portions`, `4 portions` — [formatFraction]
/// with the noun. A count of one or less than one is singular ("half a
/// portion"); everything above one is plural.
String formatPortions(double count) {
  final noun = count > 0 && count <= 1 + _tolerance ? 'portion' : 'portions';
  return '${formatFraction(count)} $noun';
}

const _tolerance = 1e-6;
const _quarters = [(0.25, '¼'), (0.5, '½'), (0.75, '¾')];
