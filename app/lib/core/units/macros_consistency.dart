/// Whether a macro panel argues with ITSELF — PURE DART (invariant 2), beside
/// `macros.dart` because it is a fact about a panel rather than about any one
/// screen.
///
/// **Nothing here corrects anything.** A panel is a reading off a label, and
/// the app's whole posture is that a label is what it says (spec §4, invariant
/// 3: never invent a number to make the math work). What this file does is
/// notice when the figures cannot all be true at once and hand the form a
/// sentence to show beside them — advice a person can act on, next to the
/// numbers they typed, while they still have the pack in their hand.
///
/// **Advice, never a refusal.** Real foods break both rules honestly: a
/// vinegar's calories are mostly acetic acid, a wine's are alcohol, and
/// neither is an Atwater macro. The thresholds are therefore deliberately
/// loose — they exist to catch a mistyped column and a panel of zeros, not to
/// audit a pantry.
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
///
/// Energy comes from somewhere. A panel like this is nearly always a row
/// whose macros were never filled in past the first field, and it would
/// otherwise count into a week's totals as pure, sourceless energy.
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
///
/// [impliedKcal] is the fibre-adjusted Atwater figure — `4P + 9F + 4C`, with
/// the fibre a row states moved off the 4 and onto a 2, because dietary fibre
/// is only partly fermented. It is the number the sentence quotes back, so a
/// person can see which column is wrong.
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

/// The energy [m]'s gram figures account for — fibre-adjusted Atwater.
///
/// `4` per gram of protein and of available carbohydrate, `9` per gram of
/// fat, and `2` per gram of the fibre inside that carbohydrate figure (a
/// panel's `carb` includes its fibre). An unstated fibre is not a zero, but
/// it is also not a correction to make here: the carbohydrate is simply
/// counted whole, which is what a label without a fibre line asserts.
double atwaterKcal(Macros m) {
  final fiber = m.fiber ?? 0;
  final available = math.max(0, m.carb - fiber);
  return 4 * m.protein + 9 * m.fat + 4 * available + 2 * fiber;
}

/// The doubt [m] raises about itself, or null.
///
/// The gap has to clear **both** a flat 150 kcal and half the stated energy
/// before it is said out loud. The flat floor is what keeps a vinegar (18
/// kcal, almost none of it Atwater) and a glass of red wine quiet; the
/// proportion is what keeps the floor from swallowing a real mistake on a
/// dense food, where 150 kcal is a rounding. A panel with no figures at all
/// says nothing — there is no arithmetic to doubt.
MacrosDoubt? macrosDoubt(Macros? m) {
  if (m == null) return null;
  if (m.kcal > 0 && m.protein == 0 && m.fat == 0 && m.carb == 0) {
    return const MacrosAllZero();
  }
  final implied = atwaterKcal(m);
  final slack = math.max(150, m.kcal.abs() / 2);
  return (m.kcal - implied).abs() > slack ? MacrosEnergyGap(implied) : null;
}
