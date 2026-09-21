/// Whether a macro panel contradicts itself. Pure Dart.
///
/// Advice only: nothing here corrects or refuses a panel. Thresholds are loose
/// because real foods (vinegar, wine) break Atwater honestly; they exist to
/// catch a mistyped column or a panel of zeros.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'macros.dart';

/// What one panel's own arithmetic says about it, or null when the figures
/// are consistent enough to be left alone.
@immutable
sealed class MacrosDoubt {
  const MacrosDoubt();
}

/// Every gram figure is zero on a food that states calories.
final class MacrosAllZero extends MacrosDoubt {
  const MacrosAllZero();

  @override
  bool operator ==(Object other) => other is MacrosAllZero;

  @override
  int get hashCode => (MacrosAllZero).hashCode;

  @override
  String toString() => 'MacrosAllZero()';
}

/// The energy the macros account for is nowhere near the energy stated.
/// [impliedKcal] is the fibre-adjusted Atwater figure ([atwaterKcal]).
final class MacrosEnergyGap extends MacrosDoubt {
  const MacrosEnergyGap(this.impliedKcal);

  final double impliedKcal;

  @override
  bool operator ==(Object other) =>
      other is MacrosEnergyGap && other.impliedKcal == impliedKcal;

  @override
  int get hashCode => Object.hash(MacrosEnergyGap, impliedKcal);

  @override
  String toString() => 'MacrosEnergyGap($impliedKcal)';
}

/// The energy [m]'s gram figures account for: 4 kcal/g protein and
/// carbohydrate, 9 kcal/g fat, with stated fibre (included in `carb`) counted
/// at 2 instead of 4. An unstated fibre leaves the carbohydrate counted whole.
double atwaterKcal(Macros m) {
  final fiber = m.fiber ?? 0;
  final available = math.max(0, m.carb - fiber);
  return 4 * m.protein + 9 * m.fat + 4 * available + 2 * fiber;
}

/// The doubt [m] raises about itself, or null. The energy gap must exceed both
/// a flat 150 kcal and half the stated energy; a panel with no figures raises
/// none.
MacrosDoubt? macrosDoubt(Macros? m) {
  if (m == null) return null;
  if (m.kcal > 0 && m.protein == 0 && m.fat == 0 && m.carb == 0) {
    return const MacrosAllZero();
  }
  final implied = atwaterKcal(m);
  final slack = math.max(150, m.kcal.abs() / 2);
  return (m.kcal - implied).abs() > slack ? MacrosEnergyGap(implied) : null;
}
