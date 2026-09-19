/// Named ingredient measures — the honest count↔basis bridge (spec §4,
/// steps 7.6–7.8).
///
/// Pure Dart, no `package:flutter` (enforced in CI), same as `units.dart`.
///
/// A [Measure] names a real-world unit of ONE ingredient and pins its amount
/// **in the ingredient's basis unit** (ADR-0008): "potato, large = 299 g",
/// "can (400 ml) = 400 ml", "clove = 3 g". Where a density describes a
/// substance (g per ml, any amount), a measure describes a *thing* — so it
/// is the right bridge for count foods, which a liquid density can never
/// describe. The basis ([MacrosBasis], the ingredient's canonical
/// dimension) decides which family the stored amount lives in: per-g
/// ingredients' measures map to mass, per-ml ones to volume.
///
/// Honesty rules (invariant 3):
///
/// - No measure ⇒ no invented amount: a plain count stays a count.
/// - Measures bridge to the **basis family only**. Reaching the other
///   mass/volume family still requires the ingredient's density, exactly
///   like any quantity of that family — a measure never smuggles in a
///   cross-family conversion of its own.
/// - A non-positive (or NaN) `amount` is bad data and converts like a
///   missing density does: a typed [Failure], never `Infinity` or `0`.
library;

import 'package:meta/meta.dart';

import '../result/result.dart';
import 'macros.dart';
import 'units.dart';

/// The provenance families a [Measure.source] can carry, for at-a-glance
/// display (7.7). [unknown] covers pre-0010 rows and unrecognized strings.
enum MeasureSourceKind { usdaPortion, borrowed, typical, manual, unknown }

/// One named measure of one ingredient: `n` of it are `n × amount` of the
/// ingredient's basis unit ([basis] — g or ml, ADR-0008).
///
/// Value-equal on all fields; [id] is the persisted `ingredient_measure.id`
/// (referenced by `recipe_line_item.measure_id` /
/// `shopping_list_contribution.measure_id`).
@immutable
class Measure {
  const Measure({
    required this.id,
    required this.label,
    required this.amount,
    this.basis = MacrosBasis.perG,
    this.sortOrder = 0,
    this.source,
  });

  final String id;

  /// Human label, e.g. `potato, large`, `can (400 ml)`, `clove`.
  final String label;

  /// Amount of one of this measure, in the ingredient's basis unit
  /// (`basis_amount`, migration 0012). Must be positive to convert; a
  /// non-positive value is rejected at conversion time (mirroring how a
  /// non-positive density is), never silently used.
  final double amount;

  /// Which basis unit [amount] is denominated in — the ingredient's
  /// `macros_basis` (the row itself stores no basis: the ingredient's is
  /// the single fact, joined in by every reader so the two can't disagree).
  final MacrosBasis basis;

  final int sortOrder;

  /// Where the amount comes from (step 7.6 provenance, displayed from
  /// 7.7): `usda_fdc:<fdc_id> (<portion>)` for pipeline-derived weights
  /// (`… — borrowed` when a variety borrows a representative food's
  /// portion), `manual` for user-authored rows, `seed:typical` for the few
  /// curated hand rows, null for rows predating the column.
  final String? source;

  /// [source] classified for display. The raw machine string stays in the data;
  /// anything user-facing shows the humanized kind: "USDA portion" /
  /// "borrowed" / "typical" / "yours".
  MeasureSourceKind get sourceKind {
    final s = source;
    if (s == null) return MeasureSourceKind.unknown;
    if (s.startsWith('usda_fdc:')) {
      return s.contains('borrowed')
          ? MeasureSourceKind.borrowed
          : MeasureSourceKind.usdaPortion;
    }
    if (s == 'seed:typical') return MeasureSourceKind.typical;
    if (s == 'manual') return MeasureSourceKind.manual;
    return MeasureSourceKind.unknown;
  }

  @override
  bool operator ==(Object other) =>
      other is Measure &&
      other.id == id &&
      other.label == label &&
      other.amount == amount &&
      other.basis == basis &&
      other.sortOrder == sortOrder &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, label, amount, basis, sortOrder, source);

  @override
  String toString() => 'Measure($label = $amount ${basis.baseUnit.id})';
}

/// How far two amounts may sit apart and still be **the same fact**: one part
/// in a hundred, either side.
///
/// The app has exactly one tolerance for that, and both doors that ask the
/// question use it — an ingredient measure against the row's piece weight
/// (`wholeMeasureOf`, ADR-0016) and a recipe measure against one whole batch
/// (`wholeMeasureOfRecipe`, ADR-0018). One number, so "the same measure"
/// means the same thing wherever it is said.
const kWholeMeasureTolerance = 0.01;

/// [label] as the household wrote it: trimmed, with any run of inner
/// whitespace read as one space.
///
/// **Case is theirs.** Nothing here lower-cases: the measures editor never
/// has, and a silent case change is the kind of edit that makes a person doubt
/// what else was changed. The seed's own style — all lower case, singular, a
/// container word carrying its shelf size (`can (14.5 oz)`) — is a thing the
/// doors *suggest*, not a thing this function imposes.
///
/// Both kinds of word are read by it, at every door either is authored at: a
/// row's measures editor, *keep as a measure* on a receipt's pack, a recipe's
/// MEASURES list, the ＋ on a component's dock. Otherwise ` Can ` and `Can`
/// become two rows of one word, which the merge-on-read rule then hides one of
/// rather than fixing.
String measureLabelAsAuthored(String label) =>
    label.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Converts [amount] of [measure] into [to], via the measure's stored basis
/// amount.
///
/// - To a unit of the basis family: `amount × measure.amount`, then the
///   ratio table (no density needed — the measure IS the bridge).
/// - Across the mass↔volume boundary: only with [densityGPerMl] (the
///   measure yields a basis-family quantity; crossing still needs the
///   ingredient's density) — without one, `unit/no_density`.
/// - To [UnitFamily.count] or [UnitFamily.imprecise]: `unit/incompatible` —
///   a measure is not interchangeable with a bare count.
/// - A non-positive/NaN [Measure.amount] is `measure/invalid_amount`:
///   dividing or multiplying by it would fabricate a number (invariant 3).
Result<Quantity> convertMeasure(
  double amount,
  Measure measure, {
  required Unit to,
  double? densityGPerMl,
}) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(measure.amount > 0)) {
    return const Err(
      Failure(
        'measure/invalid_amount',
        'a measure needs a positive basis amount',
      ),
    );
  }
  return convert(
    Quantity(amount * measure.amount, measure.basis.baseUnit),
    to: to,
    densityGPerMl: densityGPerMl,
  );
}

/// Converts a basis-family (or, with [densityGPerMl], cross-family)
/// quantity [q] into a count of [measure] — "674 g ≈ 2.25 × potato, large".
///
/// The inverse of [convertMeasure], with the same honesty rules: an invalid
/// basis amount is `measure/invalid_amount`; crossing mass↔volume needs a
/// density; count and imprecise quantities never resolve into a measure
/// (`unit/incompatible`).
Result<double> amountInMeasure(
  Quantity q,
  Measure measure, {
  double? densityGPerMl,
}) {
  if (!(measure.amount > 0)) {
    return const Err(
      Failure(
        'measure/invalid_amount',
        'a measure needs a positive basis amount',
      ),
    );
  }
  final inBasis = convert(
    q,
    to: measure.basis.baseUnit,
    densityGPerMl: densityGPerMl,
  );
  return switch (inBasis) {
    Ok(:final value) => Ok(value.amount / measure.amount),
    Err(:final failure) => Err(failure),
  };
}
