/// The unit system — the foundation everything else scales against (spec §4).
///
/// Pure Dart, no `package:flutter` (enforced in CI): recipes, week planning,
/// cook-plan aggregation, and the shopping list all lean on these conversions,
/// so they must be trustworthy and testable in isolation.
///
/// Model (spec §4):
///
/// - [UnitFamily] — `mass`, `volume`, `count`, `imprecise`, `batch`.
/// - [Unit] — an id, a label, its [UnitFamily], and (mass/volume only) a fixed
///   [Unit.ratioToBase] into the family's canonical base: **grams** for mass,
///   **ml** for volume. `count`, `imprecise` and `batch` have no ratio.
/// - [Quantity] — an [Quantity.amount] paired with a [Unit].
/// - [convert] — moves a [Quantity] to another [Unit], across the mass↔volume
///   boundary via an ingredient's `density_g_per_ml`. Returns a [Result] so a
///   missing density or an incompatible pair is a typed [Failure], never a
///   throw.
/// - [scale] — multiplies an amount, leaving `imprecise` units untouched
///   (a "pinch" doubled is still a pinch — invariant 3, honest numbers).
library;

import 'package:meta/meta.dart';

import '../result/result.dart';

/// The five kinds of unit. Conversion rules differ per family:
///
/// - [mass] and [volume] convert within-family by a fixed ratio, and across to
///   each other only when a density is supplied.
/// - [count] (e.g. "3 eggs") has no ratio; it converts only to itself.
/// - [imprecise] ("pinch", "dash", "to taste") never converts and never scales.
/// - [batch] is the sub-recipe denomination (step 8.6) — "1 batch of the
///   aioli". It is a family of one ([batches]) and converts to nothing: a
///   batch reaches grams or cups only through the target recipe's stated
///   *yield*, which is `features/recipes/domain/component_math.dart`'s job,
///   not [convert]'s. Keeping it its own family is what makes
///   `1 batch == 1 piece` impossible to write by accident.
enum UnitFamily { mass, volume, count, imprecise, batch }

/// A unit of measure. Construct via the catalog constants ([g], [ml], …) or
/// look one up by id with [unitById]; the private constructor keeps the set
/// closed so `==` can stay identity-cheap and ids stay canonical.
@immutable
class Unit {
  const Unit._(this.id, this.label, this.family, this.ratioToBase);

  /// Stable machine id, matching the `unit` string persisted in the database.
  final String id;

  /// Human label for display (e.g. `tbsp`, `kg`).
  final String label;

  final UnitFamily family;

  /// How many canonical base units one of this unit is worth — grams for
  /// [UnitFamily.mass], ml for [UnitFamily.volume]. `null` for the ratio-less
  /// [UnitFamily.count], [UnitFamily.imprecise] and [UnitFamily.batch].
  final double? ratioToBase;

  /// Whether this is a metric mass or volume unit — [g], [kg], [ml], [l].
  ///
  /// These are the units a scale or a jug reads out, and a decimal is what
  /// they read: `213.5 g`, never `213 1/2 g`. Everything else in the catalog
  /// is something a cook says by hand — a cup, a spoon, a piece, a batch —
  /// and those keep their fractions. It is what `formatAmountIn` asks.
  ///
  /// Deliberately not `family == mass || family == volume`: [oz], [lb] and
  /// [flOz] are in those families and are said in halves and quarters.
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
// Ratios are into the canonical base of the family (grams / ml). Volume figures
// use the US customary system; they are exact by definition of the US gallon
// (3.785411784 L), so conversions are reproducible rather than rounded.

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

/// Batch — the sub-recipe denomination (step 8.6 / D2), for **component lines
/// only**. Never offered for an ingredient line: the admission rules in
/// `features/ingredients/domain/allowed_units.dart` are built from the
/// mass/volume/count/imprecise catalogues, so nothing reaches an ingredient
/// picker with this in it.
///
/// The database's `unit_family()` mirror (migration 0017) does not know the id
/// and therefore treats it as its own singleton family — which is exactly what
/// this declaration says, so the yield CHECK and this table still agree.
const batches = Unit._('batch', 'batch', UnitFamily.batch, null);

/// The units an **ingredient** line may be denominated in, in a stable order —
/// everything except [batches], which belongs to component lines alone
/// (step 8.6 / D2 non-goal). Ingredient admission rules and pickers read this.
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

// --- Conversion --------------------------------------------------------------

/// Converts [q] into [to], returning an [Err] rather than throwing when the
/// conversion isn't defined.
///
/// - Within a family, converts by the fixed ratio table.
/// - Across the mass↔volume boundary, converts using [densityGPerMl] (grams per
///   ml); without it, returns an `unit/no_density` [Failure]. A non-positive
///   (or NaN) density is treated exactly like a missing one — dividing by zero
///   would fabricate `Infinity`/`0` totals (invariant 3, honest numbers).
/// - [UnitFamily.count] converts only to the same unit; [UnitFamily.imprecise]
///   never converts (`unit/imprecise`). Any other cross-family pair (e.g. count
///   to mass) is an `unit/incompatible` [Failure].
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
/// — the spoon-mapping entry style (ADR-0008: a volume-named weight mapping
/// IS a density, so `1 tbsp = 15 g` ⇒ `15 / 14.787` g/ml and volume-named
/// measures never exist).
///
/// Returns null (never a fabricated number — invariant 3) when [volumeUnit]
/// is not a volume unit or [grams] is non-positive/NaN.
double? densityFromVolumeWeight(Unit volumeUnit, double grams) {
  if (volumeUnit.family != UnitFamily.volume) return null;
  if (!(grams > 0)) return null;
  return grams / volumeUnit.ratioToBase!;
}

/// What one [volumeUnit] of something at [densityGPerMl] weighs, in grams —
/// the exact inverse of [densityFromVolumeWeight].
///
/// A stored density is a ratio, and a ratio is not a thing a kitchen holds:
/// this is how `0.66 g/ml` is read back as the sentence it was entered as,
/// "1 cup weighs 156.15 g". Nothing new is asserted — the same one stored
/// fact, said the other way round.
///
/// Returns null on the same terms its inverse does: a non-volume unit, or a
/// density that is not a positive number (invariant 3 — never a fabricated
/// number).
double? volumeWeightFromDensity(Unit volumeUnit, double densityGPerMl) {
  if (volumeUnit.family != UnitFamily.volume) return null;
  if (!(densityGPerMl > 0)) return null;
  return densityGPerMl * volumeUnit.ratioToBase!;
}

/// Multiplies [q] by [factor], keeping the unit.
///
/// [UnitFamily.imprecise] quantities are returned unchanged: a recipe scaled ×2
/// still calls for a pinch, not two (invariant 3 — never invent a number).
Quantity scale(Quantity q, num factor) {
  if (q.unit.family == UnitFamily.imprecise) return q;
  return Quantity(q.amount * factor, q.unit);
}
