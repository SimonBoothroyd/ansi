/// Portion counts as a kitchen says them. Pure Dart.
///
/// Every surface that prints a portion count goes through [formatFraction] /
/// [formatPortions]. Portion factors move in quarter steps, so only `¼ ½ ¾` are
/// used; any other value prints as a trimmed decimal.
library;

import 'number_format.dart';

/// `1¾`, `½`, `2`, `1.29`: a quarter as a glyph, a whole number plain, anything
/// else as at most two trimmed decimals.
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
  // Not a quarter: the printed-number rule, with the sign back in front.
  return '$sign${formatAmount(abs)}';
}

/// `1 portion`, `¾ portion`, `1¾ portions`: [formatFraction] with the noun,
/// singular at one or below.
String formatPortions(double count) {
  final noun = count > 0 && count <= 1 + _tolerance ? 'portion' : 'portions';
  return '${formatFraction(count)} $noun';
}

/// The step down from [n] on a `−` button: a part drops to the whole below it
/// (`1¾` → `1`), a whole drops by one (`2` → `1`). The caller keeps its own
/// floor.
double wholeBelow(double n) {
  final nearest = n.roundToDouble();
  return (n - nearest).abs() < _tolerance ? nearest - 1 : n.floorToDouble();
}

/// The step up from [n] on a `+` button: a part rises to the whole above it
/// (`1¾` → `2`, `¾` → `1`), a whole rises by one.
double wholeAbove(double n) {
  final nearest = n.roundToDouble();
  return (n - nearest).abs() < _tolerance ? nearest + 1 : n.ceilToDouble();
}

const _tolerance = 1e-6;
const _quarters = [(0.25, '¼'), (0.5, '½'), (0.75, '¾')];
