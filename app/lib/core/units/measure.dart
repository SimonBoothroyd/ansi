/// Named ingredient measures — the honest count↔mass bridge (spec §4,
/// step 7.6).
///
/// Pure Dart, no `package:flutter` (enforced in CI), same as `units.dart`.
///
/// A [Measure] names a real-world unit of ONE ingredient and pins its mass:
/// "potato, large = 299 g", "can (400 ml) = 400 g", "clove = 3 g". Where a
/// density describes a substance (g per ml, any amount), a measure describes a
/// *thing* — so it is the right bridge for count foods, which a liquid density
/// can never describe.
///
/// Honesty rules (invariant 3):
///
/// - No measure ⇒ no invented grams: a plain count stays a count.
/// - Measures bridge to **mass only**. Reaching volume still requires the
///   ingredient's density (grams → ml), exactly like any other mass — a
///   measure never smuggles in a volume conversion of its own.
/// - A non-positive (or NaN) `grams` is bad data and converts like a missing
///   density does: a typed [Failure], never `Infinity` or `0`.
library;

import 'package:meta/meta.dart';

import '../result/result.dart';
import 'units.dart';

/// One named measure of one ingredient: `amount` of it weigh
/// `amount × grams` grams.
///
/// Value-equal on all fields; [id] is the persisted `ingredient_measure.id`
/// (referenced by `recipe_line_item.measure_id` /
/// `shopping_list_contribution.measure_id`).
@immutable
class Measure {
  const Measure({
    required this.id,
    required this.label,
    required this.grams,
    this.sortOrder = 0,
    this.source,
  });

  final String id;

  /// Human label, e.g. `potato, large`, `can (400 ml)`, `clove`.
  final String label;

  /// Mass of one of this measure, in grams. Must be positive to convert; a
  /// non-positive value is rejected at conversion time (mirroring how a
  /// non-positive density is), never silently used.
  final double grams;

  final int sortOrder;

  /// Where the gram weight comes from (step 7.6 provenance, displayed from
  /// 7.7): `usda_fdc:<fdc_id> (<portion>)` for pipeline-derived weights
  /// (`… — borrowed` when a variety borrows a representative food's portion),
  /// `manual` for user-authored rows, `seed:typical` for the few curated
  /// hand rows, null for rows predating the column.
  final String? source;

  @override
  bool operator ==(Object other) =>
      other is Measure &&
      other.id == id &&
      other.label == label &&
      other.grams == grams &&
      other.sortOrder == sortOrder &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, label, grams, sortOrder, source);

  @override
  String toString() => 'Measure($label = $grams g)';
}

/// Converts [amount] of [measure] into [to], via the measure's gram weight.
///
/// - To a [UnitFamily.mass] unit: `amount × grams`, then the ratio table.
/// - To a [UnitFamily.volume] unit: only with [densityGPerMl] (the measure
///   gives grams; grams→ml still needs the ingredient's density) — without
///   one, `unit/no_density`, same as any mass→volume conversion.
/// - To [UnitFamily.count] or [UnitFamily.imprecise]: `unit/incompatible` —
///   a measure is not interchangeable with a bare count.
/// - A non-positive/NaN [Measure.grams] is `measure/invalid_grams`: dividing
///   or multiplying by it would fabricate a number (invariant 3).
Result<Quantity> convertMeasure(
  double amount,
  Measure measure, {
  required Unit to,
  double? densityGPerMl,
}) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(measure.grams > 0)) {
    return const Err(
      Failure(
        'measure/invalid_grams',
        'a measure needs a positive gram weight',
      ),
    );
  }
  return convert(
    Quantity(amount * measure.grams, g),
    to: to,
    densityGPerMl: densityGPerMl,
  );
}

/// Converts a mass (or, with [densityGPerMl], volume) quantity [q] into a
/// count of [measure] — "674 g ≈ 2.25 × potato, large".
///
/// The inverse of [convertMeasure], with the same honesty rules: an invalid
/// gram weight is `measure/invalid_grams`; volume needs a density; count and
/// imprecise quantities never resolve into a measure (`unit/incompatible`).
Result<double> amountInMeasure(
  Quantity q,
  Measure measure, {
  double? densityGPerMl,
}) {
  if (!(measure.grams > 0)) {
    return const Err(
      Failure(
        'measure/invalid_grams',
        'a measure needs a positive gram weight',
      ),
    );
  }
  final grams = convert(q, to: g, densityGPerMl: densityGPerMl);
  return switch (grams) {
    Ok(:final value) => Ok(value.amount / measure.grams),
    Err(:final failure) => Err(failure),
  };
}
