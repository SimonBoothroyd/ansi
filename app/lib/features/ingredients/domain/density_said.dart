/// A density as it was said: "⅓ cup weighs 40 g". Pure Dart.
///
/// The row stores the number every conversion reads (`density_g_per_ml`) AND
/// the sentence it came from (`density_amount`, `density_unit`,
/// `density_weighs_amount`, `density_weighs_unit`, migration 0053), the way a
/// price keeps its pack as entered beside the figure derived from it. The g/ml
/// is derived from the sentence at write time; nothing reads the sentence to
/// convert. A density set by a door that said no sentence (a USDA pick, the
/// seed, an older build) carries none, and every surface then shows the g/ml.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';
import 'serving_measure.dart';

/// "[amount] [unit] weighs [weighs] [weighsUnit]", in the order it was said:
/// one side a volume and the other a weight, either way round.
@immutable
class DensitySaid {
  const DensitySaid({
    required this.amount,
    required this.unit,
    required this.weighs,
    required this.weighsUnit,
  });

  /// The stored four columns, or null unless all four are present, both
  /// amounts are positive and the units are a volume and a weight this build
  /// knows.
  static DensitySaid? fromColumns({
    required num? amount,
    required String? unit,
    required num? weighs,
    required String? weighsUnit,
  }) {
    final u = unit == null ? null : unitById(unit);
    final w = weighsUnit == null ? null : unitById(weighsUnit);
    if (amount == null || weighs == null || u == null || w == null) {
      return null;
    }
    final said = DensitySaid(
      amount: amount.toDouble(),
      unit: u,
      weighs: weighs.toDouble(),
      weighsUnit: w,
    );
    return said.gPerMl == null ? null : said;
  }

  final double amount;
  final Unit unit;
  final double weighs;
  final Unit weighsUnit;

  /// The density this sentence states, or null when it states none.
  double? get gPerMl => densityForPair(amount, unit, weighs, weighsUnit);

  /// Whether [density] is the number this sentence states. A row whose g/ml
  /// was rewritten without its sentence — by an older build, or by the server
  /// — no longer agrees, and the sentence is then not shown.
  bool agreesWith(double? density) {
    final stated = gPerMl;
    if (stated == null || density == null) return false;
    // Relative, and loose enough for a round trip through Postgres `numeric`
    // and the sync's JSON; any edit a person makes moves it far more.
    return (stated - density).abs() <= 1e-6 * stated;
  }

  /// `⅓ cup weighs 40 g`, each side said in its own unit's way.
  String get sentence =>
      '${formatServingPhrase(amount, unit)} weighs '
      '${formatServingPhrase(weighs, weighsUnit)}';

  @override
  bool operator ==(Object other) =>
      other is DensitySaid &&
      other.amount == amount &&
      other.unit == unit &&
      other.weighs == weighs &&
      other.weighsUnit == weighsUnit;

  @override
  int get hashCode => Object.hash(amount, unit, weighs, weighsUnit);

  @override
  String toString() => 'DensitySaid($sentence)';
}

/// The sentence [ingredient]'s density was said as, or null when it has none
/// or the stored sentence no longer states the stored number.
DensitySaid? densitySaidOf(Ingredient ingredient) {
  final said = ingredient.densitySaid;
  if (said == null || !said.agreesWith(ingredient.densityGPerMl)) return null;
  return said;
}

/// The density the sentence "[a] [ua] weighs [b] [ub]" states, in g/ml, with
/// the volume and the weight in either order. Null when both units are of one
/// family, a unit is neither mass nor volume, or an amount is not positive.
double? densityForPair(double a, Unit ua, double b, Unit ub) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(a > 0) || !(b > 0)) return null;
  final ({double amount, Unit unit}) volume;
  final ({double amount, Unit unit}) mass;
  if (ua.family == UnitFamily.volume && ub.family == UnitFamily.mass) {
    volume = (amount: a, unit: ua);
    mass = (amount: b, unit: ub);
  } else if (ua.family == UnitFamily.mass && ub.family == UnitFamily.volume) {
    volume = (amount: b, unit: ub);
    mass = (amount: a, unit: ua);
  } else {
    return null;
  }
  final inMl = convert(Quantity(volume.amount, volume.unit), to: ml);
  final inGrams = convert(Quantity(mass.amount, mass.unit), to: g);
  if (inMl case Ok(value: final v) when v.amount > 0) {
    if (inGrams case Ok(value: final w)) return w.amount / v.amount;
  }
  return null;
}
