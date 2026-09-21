/// Macros for a set of planned meals (a day, a week, either under a person's
/// lens). Pure Dart.
///
/// A total sums the meals that resolved, states its denominator (`1 of 2
/// meals`) and names every excluded meal. When nothing resolves there is no
/// number; an empty set is `no meals`, never `0 kcal`. Per-serving figures come
/// from [summarizeRecipeMacros]; nothing about a recipe is re-derived here.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/portions.dart';
import '../../../core/units/units.dart';
import '../../recipes/domain/recipe_macros.dart';
import 'planning.dart';

/// Why a planned meal could not join a total.
enum MealExclusion {
  /// The recipe's own macro summary is incomplete. The reason wording comes
  /// from `incompleteNote` on the excluded meal's summary.
  incomplete,

  /// The recipe is gone, or its macros were never loaded.
  recipeMissing,

  /// No eaters and no portions override, so there is no demand to multiply.
  noEaters,

  /// A bare ingredient whose portion cannot be weighed: a stub row, an unsynced
  /// row, an amount that does not reach the row's basis, or no amount. The
  /// wording comes from the meal's `lineReason` via `incompleteLineNote`.
  ingredientNotCounted,

  /// A meal eaten out with no stated macros. An unstated fibre alone does not
  /// exclude it.
  outNotStated,
}

/// One meal left out of a total, and why. `label` is the title as the week
/// shows it.
typedef ExcludedMeal = ({
  String entryId,
  String label,
  MealExclusion reason,
  RecipeMacroSummary? summary,

  /// Set only for [MealExclusion.ingredientNotCounted]: the per-line reason
  /// whose wording the excluded snack borrows.
  MacroLineReason? lineReason,
});

/// The honest total of a set of planned meals.
@immutable
class MealSetMacros {
  const MealSetMacros({
    this.total,
    this.counted = 0,
    this.considered = 0,
    this.excluded = const [],
    this.daysContributing = 0,
    this.servings = 0,
    this.demand = 0,
  });

  /// The sum over the meals that resolved; null when none did or the set is
  /// empty. Its `fiber` is stated only when every counted meal stated it
  /// ([Macros.fiber]); an unstated fibre does not exclude the meal.
  final Macros? total;

  /// Meals that joined [total].
  final int counted;

  /// Meals in scope, after the lens. The denominator the label must state.
  final int considered;

  /// The servings [total] was multiplied over: the counted meals' whole demand
  /// under Everyone, a person's weighted share of it under their lens.
  final double servings;

  /// The full demand of the counted meals, whoever's lens this is.
  final double demand;

  /// Every meal in scope that did not join the total, named.
  final List<ExcludedMeal> excluded;

  /// Distinct days that contributed to [total] — the week average's
  /// denominator.
  final int daysContributing;

  /// Nothing was in scope: no meals, or none this person eats.
  bool get isEmpty => considered == 0;

  /// Meals were in scope and none resolved: draw the badge and reasons, no
  /// number.
  bool get isRefused => !isEmpty && total == null;

  /// A total that left meals out; it prints its denominator and names them.
  bool get isPartial => total != null && excluded.isNotEmpty;

  /// The per-day average over [daysContributing], or null without a total.
  Macros? get perDayAverage {
    final t = total;
    if (t == null || daysContributing == 0) return null;
    return t.scaledBy(1 / daysContributing);
  }

  @override
  String toString() =>
      'MealSetMacros($counted of $considered meals, total: $total, '
      'excluded: ${excluded.length}, days: $daysContributing, '
      'servings: $servings of $demand)';
}

/// The lens's denominator: `Jun · ¾ of 1¾ portions`. Null without a total, and
/// under Everyone.
String? portionShareLine(MealSetMacros macros, {required String? lensName}) {
  if (lensName == null || macros.total == null) return null;
  return '$lensName · ${formatFraction(macros.servings)} of '
      '${formatPortions(macros.demand)}';
}

/// One portion of an ingredient meal, weighed, or the reason it cannot be. The
/// row must have macros, the entry must state an amount, and the amount must
/// reach the row's basis unit (a measure through its weight, a cross-basis
/// amount through density). The caller multiplies by the entry's demand.
typedef PortionMacros = ({Macros? perPortion, MacroLineReason? reason});

PortionMacros ingredientPortionMacros(
  PlanEntry entry,
  IngredientNutrition? nutrition,
) {
  final macros = nutrition?.macros;
  if (nutrition == null || macros == null) {
    return (
      perPortion: null,
      reason: nutrition == null
          ? MacroLineReason.unknownIngredient
          : MacroLineReason.stubIngredient,
    );
  }
  final quantity = entry.quantity;
  final unit = entry.unit;
  if (quantity == null || unit == null) {
    return (perPortion: null, reason: MacroLineReason.noAmount);
  }

  final to = nutrition.basis.baseUnit;
  final measure = entry.measure;
  final Result<Quantity> converted;
  if (measure != null) {
    converted = convertMeasure(
      quantity,
      measure,
      to: to,
      densityGPerMl: nutrition.densityGPerMl,
    );
  } else if (entry.measureId != null) {
    // An unresolved measure reads as its count fallback, which cannot join a
    // mass/volume total. Nothing is missing on the ingredient, so this is
    // `needsDensity` (unconvertible), not `needsWeight`, until the measure row
    // syncs. See ADR-0015.
    return (perPortion: null, reason: MacroLineReason.needsDensity);
  } else if (unit.family == UnitFamily.count &&
      pieceMeasureOf(nutrition) != null) {
    // A bare `piece` converts through the row's piece weight (ADR-0015).
    converted = convertMeasure(
      quantity,
      pieceMeasureOf(nutrition)!,
      to: to,
      densityGPerMl: nutrition.densityGPerMl,
    );
  } else {
    converted = convert(
      Quantity(quantity, unit),
      to: to,
      densityGPerMl: nutrition.densityGPerMl,
    );
  }

  return switch (converted) {
    Ok(:final value) => (
      perPortion: macros.scaledBy(value.amount / 100),
      reason: null,
    ),
    // A bare count with no piece weight is fixed on the ingredient, so it keeps
    // `needsWeight`.
    Err() => (
      perPortion: null,
      reason: unit.family == UnitFamily.count
          ? MacroLineReason.needsWeight
          : MacroLineReason.needsDensity,
    ),
  };
}

/// One planned meal's macros as served: [sumPlannedMacros] over a set of one,
/// so the lens, the refusals and their wording match the day total.
MealSetMacros servedMealMacros(
  PlanEntry entry, {
  required RecipeMacroSummary? Function(String recipeId) summaryFor,
  String? lensMemberId,
  Map<String, Member> membersById = const {},
}) => sumPlannedMacros(
  [entry],
  summaryFor: summaryFor,
  lensMemberId: lensMemberId,
  membersById: membersById,
);

/// Sums `perServing × servings` over [entries].
///
/// Under Everyone ([lensMemberId] null) `servings` is [demandPortions]. Under a
/// person's lens an entry is in scope only if they eat it, and `servings` is
/// their own factor, scaled by `override ÷ Σ factors` when an override is set.
/// An entry with no eaters stays in scope under a lens and is excluded with a
/// reason.
///
/// [summaryFor] returns a recipe's per-serving summary (null when gone or not
/// loaded). An ingredient meal is weighed from the nutrition it carries and a
/// meal out from its stated figures; both multiply by `servings` like a dish.
/// Day and week totals both come from this function, so a week is never a sum
/// of rounded days.
MealSetMacros sumPlannedMacros(
  Iterable<PlanEntry> entries, {
  required RecipeMacroSummary? Function(String recipeId) summaryFor,
  String? lensMemberId,
  Map<String, Member> membersById = const {},
}) {
  Macros? total;
  var counted = 0;
  var considered = 0;
  final excluded = <ExcludedMeal>[];
  final days = <int>{};
  var servingsSum = 0.0;
  var demandSum = 0.0;

  for (final entry in entries) {
    final eaters = entry.eaterIds;
    if (lensMemberId != null &&
        eaters.isNotEmpty &&
        !eaters.contains(lensMemberId)) {
      // Somebody else's meal: out of scope, not an exclusion.
      continue;
    }
    considered++;

    final label = entry.title ?? deletedTargetLabel(entry);
    final factorsSum = eatersDemand(eaters, membersById);
    final demand = demandPortions(entry, membersById);
    if (demand <= 0 ||
        (lensMemberId != null && (eaters.isEmpty || factorsSum <= 0))) {
      excluded.add((
        entryId: entry.id,
        label: label,
        reason: MealExclusion.noEaters,
        summary: null,
        lineReason: null,
      ));
      continue;
    }

    // Every kind is weighed explicitly; a null `recipe_id` is another kind of
    // meal, never one to skip.
    final Macros? perPortion;
    switch (entry.kind) {
      case PlanEntryKind.ingredient:
        final weighed = ingredientPortionMacros(entry, entry.nutrition);
        if (weighed.perPortion == null) {
          excluded.add((
            entryId: entry.id,
            label: label,
            reason: MealExclusion.ingredientNotCounted,
            summary: null,
            lineReason: weighed.reason,
          ));
          continue;
        }
        perPortion = weighed.perPortion;
      case PlanEntryKind.out:
        // The stated per-portion figures, or an absence; nothing is derived.
        final stated = entry.macros;
        if (stated == null) {
          excluded.add((
            entryId: entry.id,
            label: label,
            reason: MealExclusion.outNotStated,
            summary: null,
            lineReason: null,
          ));
          continue;
        }
        perPortion = stated;
      case PlanEntryKind.recipe:
        final summary = entry.recipeTitle == null
            ? null
            : summaryFor(entry.recipeId!);
        if (summary == null) {
          excluded.add((
            entryId: entry.id,
            label: label,
            reason: MealExclusion.recipeMissing,
            summary: null,
            lineReason: null,
          ));
          continue;
        }
        if (summary.perServing == null) {
          excluded.add((
            entryId: entry.id,
            label: label,
            reason: MealExclusion.incomplete,
            summary: summary,
            lineReason: null,
          ));
          continue;
        }
        perPortion = summary.perServing;
    }

    final servings = lensMemberId == null
        ? demand
        : (membersById[lensMemberId]?.portionFactor ?? 1) *
              (entry.portions == null ? 1 : demand / factorsSum);
    final part = perPortion!.scaledBy(servings);
    total = total == null ? part : total + part;
    counted++;
    days.add(entry.dayOfWeek);
    servingsSum += servings;
    demandSum += demand;
  }

  return MealSetMacros(
    total: total,
    counted: counted,
    considered: considered,
    excluded: List.unmodifiable(excluded),
    daysContributing: days.length,
    servings: servingsSum,
    demand: demandSum,
  );
}
