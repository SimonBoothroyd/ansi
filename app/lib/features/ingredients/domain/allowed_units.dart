/// Which units a picker may offer for an ingredient — PURE DART (invariant 2).
///
/// Offering every unit in [kAllUnits] lets a user pick a pair that can never
/// convert honestly ("200 cup" of a mass-default ingredient with no density),
/// which splits aggregation into confusing subtotals. This filter keeps the
/// pickers to combinations the unit system can actually resolve
/// (tech-debt-tracker row `shopping/units`).
library;

import 'package:meta/meta.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';

/// The units a unit picker should offer for [ingredient].
///
/// Derived from the ingredient's `default_unit` and density, in [kAllUnits]
/// order:
///
/// - every unit in the default unit's family (you can always convert
///   within-family);
/// - the opposite mass/volume family **only** when the ingredient carries a
///   density — without one, [convert] would fail with `unit/no_density`;
/// - the [UnitFamily.imprecise] units always ("a pinch" is valid of anything,
///   and never converts or scales anyway — invariant 3).
///
/// A count-default ingredient (eggs, tins) offers only count + imprecise:
/// count converts to nothing else, density or not, so mass/volume would only
/// invite an unresolvable line.
List<Unit> allowedUnitsFor(Ingredient ingredient) {
  final family = ingredient.defaultUnit.family;
  final crossFamily =
      ingredient.densityGPerMl != null &&
      (family == UnitFamily.mass || family == UnitFamily.volume);

  bool allowed(Unit u) => switch (u.family) {
    UnitFamily.imprecise => true,
    _ when u.family == family => true,
    UnitFamily.mass || UnitFamily.volume => crossFamily,
    _ => false,
  };

  return [
    for (final u in kAllUnits)
      if (allowed(u)) u,
  ];
}

// --- v2: units + the ingredient's live measures (step 7.6) -------------------

/// One entry of a unit picker: either a catalog [Unit] or one of the
/// ingredient's named [Measure]s ("potato, large (299 g)"). Sealed so a picker
/// can switch exhaustively.
@immutable
sealed class UnitChoice {
  const UnitChoice();

  /// The dropdown label.
  String get label;
}

final class UnitOption extends UnitChoice {
  const UnitOption(this.unit);

  final Unit unit;

  @override
  String get label => unit.label;

  @override
  bool operator ==(Object other) => other is UnitOption && other.unit == unit;

  @override
  int get hashCode => unit.hashCode;
}

final class MeasureOption extends UnitChoice {
  const MeasureOption(this.measure);

  final Measure measure;

  @override
  String get label {
    final g = measure.grams;
    final grams = g == g.roundToDouble() ? g.toStringAsFixed(0) : '$g';
    return '${measure.label} ($grams g)';
  }

  @override
  bool operator ==(Object other) =>
      other is MeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// [allowedUnitsFor] plus the ingredient's live [measures], as picker choices:
/// the same honest unit set first (stable positions), then one [MeasureOption]
/// per measure in the given order (callers pass them `sort_order`-sorted).
///
/// A measure needs no density gate — its gram weight IS the bridge — and it
/// applies to any ingredient that has one, count-default included (that's the
/// whole point: count foods finally reach mass honestly).
List<UnitChoice> allowedUnitChoicesFor(
  Ingredient ingredient,
  List<Measure> measures,
) => [
  for (final u in allowedUnitsFor(ingredient)) UnitOption(u),
  for (final m in measures) MeasureOption(m),
];
