/// The unit system: [Unit]s in a [UnitFamily], a [Quantity], and [convert] /
/// [scale] over them.
///
/// Pure Dart. Mass converts through grams and volume through ml; crossing
/// between them needs an ingredient's density. An undefined conversion is a
/// typed [Failure], never a throw.
library;

import 'package:meta/meta.dart';

import '../result/result.dart';

/// The five kinds of unit.
///
/// [mass] and [volume] convert within-family by a fixed ratio, and to each
/// other only with a density. [count] converts only to itself; [imprecise]
/// never converts or scales. [batch] is the sub-recipe denomination: a family
/// of one that reaches grams or cups only through the target recipe's yield
/// (`component_math.dart`), never through [convert].
enum UnitFamily {
  mass,
  volume,
  count,
  imprecise,
  batch;

  /// The family as a person says it: `weight`, never `mass`.
  String get said => this == mass ? 'weight' : name;
}

/// A unit of measure. Use the catalog constants ([g], [ml], …) or [unitById];
/// the private constructor keeps the set closed.
@immutable
class Unit {
  const Unit._(this.id, this.label, this.family, this.ratioToBase);

  /// Stable machine id, matching the `unit` string persisted in the database.
  final String id;

  /// Human label for display (e.g. `tbsp`, `kg`).
  final String label;

  final UnitFamily family;

  /// How many base units (grams for mass, ml for volume) one of this unit is
  /// worth. Null for count, imprecise and batch.
  final double? ratioToBase;

  /// Whether this is a metric mass or volume unit ([g], [kg], [ml], [l]), which
  /// prints as a decimal rather than a fraction.
  ///
  /// Not `family == mass || volume`: [oz], [lb] and [flOz] are said in halves
  /// and quarters.
  bool get isMetric => _metricIds.contains(id);

  @override
  String toString() => 'Unit($id)';
}

/// An [amount] of a [Unit]. Amounts are stored as `double`; integer literals
/// (`Quantity(1, kg)`) are widened on construction.
@immutable
class Quantity {
  Quantity(num amount, this.unit) : amount = amount.toDouble();

  final double amount;
  final Unit unit;

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => 'Quantity($amount ${unit.id})';
}

// --- Catalog -----------------------------------------------------------------
// Ratios are into the family's base (grams / ml). Volume uses US customary,
// exact by definition of the US gallon (3.785411784 L).

// Mass (base: gram).
const g = Unit._('g', 'g', UnitFamily.mass, 1);
const kg = Unit._('kg', 'kg', UnitFamily.mass, 1000);
const oz = Unit._('oz', 'oz', UnitFamily.mass, 28.349523125);
const lb = Unit._('lb', 'lb', UnitFamily.mass, 453.59237);

// Volume (base: ml).
const ml = Unit._('ml', 'ml', UnitFamily.volume, 1);
const l = Unit._('l', 'l', UnitFamily.volume, 1000);
const tsp = Unit._('tsp', 'tsp', UnitFamily.volume, 4.92892159375);
const tbsp = Unit._('tbsp', 'tbsp', UnitFamily.volume, 14.78676478125);
const flOz = Unit._('fl_oz', 'fl oz', UnitFamily.volume, 29.5735295625);
const cup = Unit._('cup', 'cup', UnitFamily.volume, 236.5882365);
const pint = Unit._('pt', 'pt', UnitFamily.volume, 473.176473);
const quart = Unit._('qt', 'qt', UnitFamily.volume, 946.352946);

// Count.
const pieces = Unit._('piece', 'piece', UnitFamily.count, null);

// Imprecise (non-scaling, non-converting).
const pinch = Unit._('pinch', 'pinch', UnitFamily.imprecise, null);
const dash = Unit._('dash', 'dash', UnitFamily.imprecise, null);
const handful = Unit._('handful', 'handful', UnitFamily.imprecise, null);
const toTaste = Unit._('to_taste', 'to taste', UnitFamily.imprecise, null);

/// Batch: the sub-recipe denomination, for component lines only. Never offered
/// for an ingredient line.
///
/// The database's `unit_family()` does not know the id and so treats it as its
/// own singleton family, which agrees with this declaration.
const batches = Unit._('batch', 'batch', UnitFamily.batch, null);

/// The units an ingredient line may be denominated in, in a stable order:
/// everything except [batches].
const kIngredientUnits = <Unit>[
  g, kg, oz, lb, //
  ml, l, tsp, tbsp, flOz, cup, pint, quart, //
  pieces, //
  pinch, dash, handful, toTaste,
];

/// Every unit the system knows, in a stable order — [kIngredientUnits] plus
/// the component-line-only [batches].
const kAllUnits = <Unit>[...kIngredientUnits, batches];

/// The ids behind [Unit.isMetric] — the decimal-reading units.
const _metricIds = {'g', 'kg', 'ml', 'l'};

final Map<String, Unit> _byId = {for (final u in kAllUnits) u.id: u};

/// Looks up a [Unit] by its persisted [Unit.id], or `null` if unknown.
Unit? unitById(String id) => _byId[id];

// Reading a written unit name (`tbsp`, `Cups `) is `unitFromLabel` in
// `unit_words.dart`.

// --- Conversion --------------------------------------------------------------

/// Converts [q] into [to], returning an [Err] where the conversion is
/// undefined.
///
/// Within a family it uses the ratio table. Across mass↔volume it needs a
/// positive [densityGPerMl], else `unit/no_density`. Count converts only to the
/// same unit, imprecise never (`unit/imprecise`), and any other cross-family
/// pair is `unit/incompatible`.
Result<Quantity> convert(
  Quantity q, {
  required Unit to,
  double? densityGPerMl,
}) {
  final from = q.unit;
  if (from == to) return Ok(q);

  if (from.family == UnitFamily.imprecise ||
      to.family == UnitFamily.imprecise) {
    return const Err(
      Failure('unit/imprecise', 'imprecise units cannot be converted'),
    );
  }

  if (from.family == to.family) {
    // count has no ratio; anything else here is mass↔mass or volume↔volume.
    if (from.ratioToBase == null || to.ratioToBase == null) {
      return Err(
        Failure(
          'unit/incompatible',
          'no conversion between ${from.id} and ${to.id}',
        ),
      );
    }
    final base = q.amount * from.ratioToBase!;
    return Ok(Quantity(base / to.ratioToBase!, to));
  }

  // Cross-family is only defined between mass and volume, via density.
  final massVolume =
      (from.family == UnitFamily.mass && to.family == UnitFamily.volume) ||
      (from.family == UnitFamily.volume && to.family == UnitFamily.mass);
  if (!massVolume) {
    return Err(
      Failure(
        'unit/incompatible',
        'cannot convert ${from.family.name} to ${to.family.name}',
      ),
    );
  }
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (densityGPerMl == null || !(densityGPerMl > 0)) {
    return const Err(
      Failure('unit/no_density', 'mass↔volume conversion needs a density'),
    );
  }

  if (from.family == UnitFamily.volume) {
    // ml → g: multiply by density.
    final grams = (q.amount * from.ratioToBase!) * densityGPerMl;
    return Ok(Quantity(grams / to.ratioToBase!, to));
  }
  // g → ml: divide by density.
  final millilitres = (q.amount * from.ratioToBase!) / densityGPerMl;
  return Ok(Quantity(millilitres / to.ratioToBase!, to));
}

/// The density (g/ml) implied by "one [volumeUnit] weighs [grams] g"
/// (ADR-0008). Null when [volumeUnit] is not a volume unit or [grams] is
/// non-positive or NaN.
double? densityFromVolumeWeight(Unit volumeUnit, double grams) {
  if (volumeUnit.family != UnitFamily.volume) return null;
  if (!(grams > 0)) return null;
  return grams / volumeUnit.ratioToBase!;
}

/// What one [volumeUnit] at [densityGPerMl] weighs, in grams: the inverse of
/// [densityFromVolumeWeight], null on the same terms.
double? volumeWeightFromDensity(Unit volumeUnit, double densityGPerMl) {
  if (volumeUnit.family != UnitFamily.volume) return null;
  if (!(densityGPerMl > 0)) return null;
  return densityGPerMl * volumeUnit.ratioToBase!;
}

/// Multiplies [q] by [factor], keeping the unit. Imprecise quantities are
/// returned unchanged: a doubled pinch is still a pinch.
Quantity scale(Quantity q, num factor) {
  if (q.unit.family == UnitFamily.imprecise) return q;
  return Quantity(q.amount * factor, q.unit);
}
