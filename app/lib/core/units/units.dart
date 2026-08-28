/// The unit system — the foundation everything else scales against (spec §4).
///
/// Pure Dart, no `package:flutter` (enforced in CI): recipes, week planning,
/// cook-plan aggregation, and the shopping list all lean on these conversions,
/// so they must be trustworthy and testable in isolation.
///
/// Model (spec §4):
///
/// - [UnitFamily] — `mass`, `volume`, `count`, `imprecise`.
/// - [Unit] — an id, a label, its [UnitFamily], and (mass/volume only) a fixed
///   [Unit.ratioToBase] into the family's canonical base: **grams** for mass,
///   **ml** for volume. `count` and `imprecise` have no ratio.
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

/// The four kinds of unit. Conversion rules differ per family:
///
/// - [mass] and [volume] convert within-family by a fixed ratio, and across to
///   each other only when a density is supplied.
/// - [count] (e.g. "3 eggs") has no ratio; it converts only to itself.
/// - [imprecise] ("pinch", "dash", "to taste") never converts and never scales.
enum UnitFamily { mass, volume, count, imprecise }

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
  /// [UnitFamily.count] and [UnitFamily.imprecise].
  final double? ratioToBase;

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
const mg = Unit._('mg', 'mg', UnitFamily.mass, 0.001);
const oz = Unit._('oz', 'oz', UnitFamily.mass, 28.349523125);
const lb = Unit._('lb', 'lb', UnitFamily.mass, 453.59237);

// Volume (base: ml).
const ml = Unit._('ml', 'ml', UnitFamily.volume, 1);
const l = Unit._('l', 'l', UnitFamily.volume, 1000);
const tsp = Unit._('tsp', 'tsp', UnitFamily.volume, 4.92892159375);
const tbsp = Unit._('tbsp', 'tbsp', UnitFamily.volume, 14.78676478125);
const flOz = Unit._('fl_oz', 'fl oz', UnitFamily.volume, 29.5735295625);
const cup = Unit._('cup', 'cup', UnitFamily.volume, 236.5882365);

// Count.
const pieces = Unit._('piece', 'piece', UnitFamily.count, null);

// Imprecise (non-scaling, non-converting).
const pinch = Unit._('pinch', 'pinch', UnitFamily.imprecise, null);
const dash = Unit._('dash', 'dash', UnitFamily.imprecise, null);
const toTaste = Unit._('to_taste', 'to taste', UnitFamily.imprecise, null);

/// Every unit the system knows, in a stable order.
const kAllUnits = <Unit>[
  g, kg, mg, oz, lb, //
  ml, l, tsp, tbsp, flOz, cup, //
  pieces, //
  pinch, dash, toTaste,
];

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

/// Multiplies [q] by [factor], keeping the unit.
///
/// [UnitFamily.imprecise] quantities are returned unchanged: a recipe scaled ×2
/// still calls for a pinch, not two (invariant 3 — never invent a number).
Quantity scale(Quantity q, num factor) {
  if (q.unit.family == UnitFamily.imprecise) return q;
  return Quantity(q.amount * factor, q.unit);
}
