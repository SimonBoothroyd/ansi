/// Which units a picker may offer for an ingredient — PURE DART (invariant 2).
///
/// Offering every unit in [kAllUnits] lets a user pick a pair that can never
/// convert honestly ("200 cup" of a mass-default ingredient with no density),
/// which splits aggregation into confusing subtotals. This filter keeps the
/// pickers to combinations the unit system can actually resolve
/// (tech-debt-tracker row `shopping/units`).
library;

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
