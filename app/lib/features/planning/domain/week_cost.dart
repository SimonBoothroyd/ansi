/// What a planned week costs — PURE DART (invariant 2), and the money twin of
/// `sumPlannedMacros`.
///
/// One rule, and it is the week's own: **sum the meals that resolved, and name
/// what kept the rest out.** A recipe with an unpriced line has no cost at all
/// (`summarizeRecipeCost` refuses it, invariant 3), so the meal cannot join the
/// figure — and the band says which lines to go and price rather than quietly
/// understating the week by exactly the things nobody has priced.
///
/// It computes nothing about a recipe. The per-serving figure is already
/// produced by `summarizeRecipeCost`, and re-deriving it here would create the
/// drift `shared/cost_words.dart` exists to prevent. The multiplication is the
/// one `sumPlannedMacros` does — `per serving × the portions planned` — so the
/// two lines of the band share a denominator and can never describe two
/// different weeks.
///
/// **A meal that is a bare ingredient costs what its row costs.** It is weighed
/// the way `ingredientPortionMacros` weighs it — the entry's own amount, unit
/// or measure carried to the row's basis through the one shared conversion —
/// and multiplied by the latest price per unit of that basis. A snack is a line
/// of a recipe that happens to be the whole meal, and pricing it any other way
/// would let the same yoghurt cost two figures depending on which screen asked.
/// It joins the unpriced names only when the row really has no price, or when
/// nothing carries its amount to the basis — the recipe cost's own two reasons,
/// in its own words.
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart';
import '../../ingredients/domain/price.dart';
import '../../recipes/domain/line_basis.dart';
import '../../recipes/domain/recipe_cost.dart';
import 'planning.dart';

/// What a set of planned meals costs, and what it could not price.
typedef PlannedCost = ({
  /// The sum over the meals that resolved, in cents. **Null when nothing
  /// resolved** — never a zero standing in for an absence.
  double? cents,

  /// Meals that joined [cents].
  int counted,

  /// Meals in scope, after the lens — the denominator [counted] is out of.
  int considered,

  /// Every distinct thing that kept a meal out of the figure, named in the
  /// order it was met: an unpriced line of a planned recipe, or a bare
  /// ingredient meal whose own row is unpriced. Distinct, because the same
  /// unpriced ingredient in three recipes is one thing to go and price.
  List<String> unpriced,
});

/// What one portion of a bare INGREDIENT meal costs, or the reason it cannot
/// be said — the money twin of `ingredientPortionMacros`, line for line.
///
/// The walk is the recipe cost's, applied to one amount instead of a line: the
/// row must be known, its amount must reach its basis unit, and something must
/// have been paid for it in that same basis. Nothing is invented at any step,
/// and the reasons are [CostLineReason]'s own — a snack says `no price yet` in
/// exactly the words an unpriced recipe LINE says it.
///
/// The returned figure is what ONE portion is worth; the caller multiplies by
/// the entry's demand, exactly as it multiplies a recipe's per-serving figure.
typedef PortionCost = ({double? cents, CostLineReason? reason});

PortionCost ingredientPortionCost(PlanEntry entry, PriceObservation? price) {
  final nutrition = entry.nutrition;
  final quantity = entry.quantity;
  final unit = entry.unit;
  // The dimension facts alone. Built here rather than borrowed from the macro
  // side, so nothing nutritional is in scope where money is (ADR-0017).
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
    // A measure this device has not synced weighs nothing yet — the amount is
    // a count until the row arrives, and a count joins no mass or volume.
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
    // The fact's own refusals (a pack of nothing, nothing paid), passed
    // through rather than second-guessed.
    Err() => (cents: null, reason: CostLineReason.noPrice),
  };
}

/// Sums `perServing × servings` over [entries], exactly as `sumPlannedMacros`
/// does — see that function for what `servings` means under a lens.
///
/// [costFor] hands back a recipe's cost summary (null when the recipe is gone
/// or not loaded); such a meal is excluded and its title named, because a meal
/// this device cannot resolve is not a meal that costs nothing.
///
/// [priceFor] hands back the latest price paid for one vocabulary row, which
/// is what a bare INGREDIENT meal is costed from. It is required rather than
/// defaulted: a caller that forgot it would name every snack unpriced and read
/// as a household that has priced nothing.
PlannedCost sumPlannedCost(
  Iterable<PlanEntry> entries, {
  required RecipeCostSummary? Function(String recipeId) costFor,
  required PriceObservation? Function(String ingredientId) priceFor,
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
      // Nobody is down to eat it, so there is no demand to multiply. Not a
      // pricing gap — nothing is named, the way the macros name nothing.
      continue;
    }

    // The explicit branch over every kind, as the macros take it. A recipe
    // hands over a per-SERVING figure somebody else computed; a bare
    // ingredient is weighed and priced here from its own stated amount, which
    // is the whole meal; a meal eaten out is neither cooked nor bought, so it
    // is not a cost to cook and not a gap in one — passed over without a name,
    // and leaving the count it never joined.
    final double? perServing;
    switch (entry.kind) {
      case PlanEntryKind.out:
        considered--;
        continue;
      case PlanEntryKind.ingredient:
        // The kind IS the guarantee: a meal is this kind exactly when it
        // names a vocabulary row.
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
          // The recipe's own refusal, passed through by name: these are the
          // lines a person can go and price to make the week whole.
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
