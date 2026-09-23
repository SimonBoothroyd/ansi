/// What a planned week costs to cook. Pure Dart. See ADR-0017.
///
/// Sums `per serving × portions` over the meals that resolved, as
/// `sumPlannedMacros` does, and names what kept the rest out. A recipe with an
/// unpriced line has no cost, so its meal is left out whole. A bare ingredient
/// meal is weighed like `ingredientPortionMacros` and priced at the price its
/// row's cost reads (`costPriceOf`), per basis unit.
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart';
import '../../ingredients/domain/price.dart';
import '../../recipes/domain/line_basis.dart';
import '../../recipes/domain/recipe_cost.dart';
import 'planning.dart';

/// What a set of planned meals costs, and what it could not price.
typedef PlannedCost = ({
  /// The sum over the meals that resolved, in cents. Null when none did.
  double? cents,

  /// Meals that joined [cents].
  int counted,

  /// Meals in scope, after the lens — the denominator [counted] is out of.
  int considered,

  /// Each distinct thing that kept a meal out, in the order met: an unpriced
  /// recipe line, or an unpriced ingredient meal.
  List<String> unpriced,
});

/// What one portion of a bare ingredient meal costs, or why it cannot be said,
/// in [CostLineReason]'s terms. The caller multiplies by the entry's demand.
typedef PortionCost = ({double? cents, CostLineReason? reason});

PortionCost ingredientPortionCost(PlanEntry entry, UnitPrice? price) {
  final nutrition = entry.nutrition;
  final quantity = entry.quantity;
  final unit = entry.unit;
  // Only dimension facts are read here, nothing nutritional (ADR-0017).
  if (nutrition == null || quantity == null || unit == null) {
    return (cents: null, reason: CostLineReason.noPathToBasis);
  }
  final row = (
    basis: nutrition.basis,
    densityGPerMl: nutrition.densityGPerMl,
    pieceBasisAmount: nutrition.pieceBasisAmount,
  );

  final measure = entry.measure;
  final double? amount;
  if (measure != null) {
    amount = switch (convertMeasure(
      quantity,
      measure,
      to: row.basis.baseUnit,
      densityGPerMl: row.densityGPerMl,
    )) {
      Ok(:final value) => value.amount,
      Err() => null,
    };
  } else if (entry.measureId != null) {
    // An unsynced measure weighs nothing yet, and a count joins no mass or
    // volume.
    amount = null;
  } else {
    amount = quantityInBasis(quantity, unit, row);
  }
  if (amount == null) {
    return (cents: null, reason: CostLineReason.noPathToBasis);
  }
  if (price == null) return (cents: null, reason: CostLineReason.noPrice);
  if (price.basis != row.basis) {
    return (cents: null, reason: CostLineReason.priceOffBasis);
  }
  final per100 = price.per100;
  return switch (per100) {
    Ok(:final value) => (cents: value.cents * amount / 100, reason: null),
    // The price's own refusals (empty pack, nothing paid) pass through.
    Err() => (cents: null, reason: CostLineReason.noPrice),
  };
}

/// Sums `perServing × servings` over [entries]; see `sumPlannedMacros` for
/// `servings` under a lens.
///
/// [costFor] returns a recipe's cost summary; null (gone or not loaded)
/// excludes the meal by name. [priceFor] returns the price a vocabulary row's
/// cost reads, which ingredient meals are costed from.
PlannedCost sumPlannedCost(
  Iterable<PlanEntry> entries, {
  required RecipeCostSummary? Function(String recipeId) costFor,
  required UnitPrice? Function(String ingredientId) priceFor,
  String? lensMemberId,
  Map<String, Member> membersById = const {},
}) {
  double? total;
  var counted = 0;
  var considered = 0;
  final unpriced = <String>[];

  void name(String what) {
    if (what.isNotEmpty && !unpriced.contains(what)) unpriced.add(what);
  }

  for (final entry in entries) {
    final eaters = entry.eaterIds;
    if (lensMemberId != null &&
        eaters.isNotEmpty &&
        !eaters.contains(lensMemberId)) {
      continue;
    }
    considered++;

    final label = entry.title ?? deletedTargetLabel(entry);
    final factorsSum = eatersDemand(eaters, membersById);
    final demand = demandPortions(entry, membersById);
    if (demand <= 0 ||
        (lensMemberId != null && (eaters.isEmpty || factorsSum <= 0))) {
      // No eaters means no demand; not a pricing gap, so nothing is named.
      continue;
    }

    // Every kind is handled explicitly. A meal eaten out is neither a cost nor
    // a gap: it is skipped unnamed and uncounted.
    final double? perServing;
    switch (entry.kind) {
      case PlanEntryKind.out:
        considered--;
        continue;
      case PlanEntryKind.ingredient:
        // An ingredient meal always names a vocabulary row.
        final priced = ingredientPortionCost(
          entry,
          priceFor(entry.ingredientId!),
        );
        if (priced.cents == null) {
          name(label);
          continue;
        }
        perServing = priced.cents;
      case PlanEntryKind.recipe:
        final summary = entry.recipeTitle == null
            ? null
            : costFor(entry.recipeId!);
        if (summary == null) {
          name(label);
          continue;
        }
        if (summary.perServingCents == null) {
          // The recipe's unpriced lines, passed through by name.
          for (final note in summary.unpriced) {
            name(note.name);
          }
          continue;
        }
        perServing = summary.perServingCents;
    }

    final servings = lensMemberId == null
        ? demand
        : (membersById[lensMemberId]?.portionFactor ?? 1) *
              (entry.portions == null ? 1 : demand / factorsSum);
    total = (total ?? 0) + perServing! * servings;
    counted++;
  }

  return (
    cents: total,
    counted: counted,
    considered: considered,
    unpriced: List.unmodifiable(unpriced),
  );
}
