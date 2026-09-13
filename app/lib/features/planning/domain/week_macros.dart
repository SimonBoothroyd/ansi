/// Honest macros for a SET of planned meals — PURE DART (invariant 2).
///
/// The week redesign's D4, as one rule applied at three scopes (a day, the
/// week, and either of those under a person's lens):
///
/// > A meal-set total shows the sum of the meals that **resolved**, is labelled
/// > with its **own denominator** (`1 of 2 meals`), and **names every excluded
/// > meal**. When nothing resolves, no number is drawn at all — the badge and
/// > the reasons, exactly as the recipe macro panel refuses. An **empty** set
/// > is a third state — `no meals` — never `0 kcal`.
///
/// Why that is not invariant 3 bending. On the recipe page the scope is fixed
/// ("this recipe's macros") and a partial sum lies about it. Here the scope is
/// *a set of meals whose label states it*, and each meal is an independently
/// honest unit — the same doctrine as the shopping list, which already sums
/// what it can and shows provenance for every part. The teeth are that the
/// denominator is mandatory (no bare number, ever) and that an exclusion is
/// NAMED, not counted.
///
/// This file computes nothing about a recipe. The per-serving figure is
/// already produced by [summarizeRecipeMacros], and re-deriving it here would
/// create exactly the "three surfaces that can drift" problem
/// `shared/incomplete_macros.dart` exists to prevent. The excluded meal
/// carries its [RecipeMacroSummary] so the UI prints the shared
/// `incompleteNote`, in its exact words.
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
  /// Its recipe's own macro summary is incomplete (a stub line, an
  /// unconvertible line, an unresolved sub-recipe …). The reason WORDS come
  /// from `incompleteNote` on the excluded meal's summary — never re-invented
  /// here.
  incomplete,

  /// The recipe behind the entry is gone, or its macros were never loaded.
  /// There is nothing to sum and nothing to say about why.
  recipeMissing,

  /// Nobody is down to eat it (and no portions override says otherwise), so
  /// there is no demand to multiply — and, under a person's lens, nothing to
  /// divide by. Never a division by zero, never a silent zero.
  noEaters,

  /// The meal is a bare INGREDIENT (step 8.14) whose one portion cannot be
  /// weighed honestly — a stub row with no macros, a row this device has never
  /// synced, an amount that never reached the row's basis, or no amount at
  /// all. The reason WORDS come from the excluded meal's `lineReason`, through
  /// the shared `incompleteLineNote` — so a snack says `stub ingredient` in
  /// exactly the words a stub recipe LINE says it (A-D5 / B-D3).
  ingredientNotCounted,
}

/// One meal left out of a total, and why. `label` is the dish's title as the
/// week shows it, so the exclusion can be NAMED rather than counted.
typedef ExcludedMeal = ({
  String entryId,
  String label,
  MealExclusion reason,
  RecipeMacroSummary? summary,

  /// Set only for [MealExclusion.ingredientNotCounted]: the per-line reason
  /// whose wording an excluded SNACK borrows, so the week's refusal and a
  /// recipe page's refusal are one vocabulary.
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

  /// The sum over the meals that resolved. **Null when nothing resolved, and
  /// null when the set is empty** — never a zero standing in for an absence.
  ///
  /// Its `fiber` obeys [Macros.fiber]'s every-addend rule at this scope too: a
  /// week states fibre only when every meal it counted did. The meal is still
  /// counted — an unstated fibre is not an exclusion, and the denominator does
  /// not move.
  final Macros? total;

  /// Meals that joined [total].
  final int counted;

  /// Meals in scope, after the lens. The denominator the label must state.
  final int considered;

  /// The servings [total] was multiplied over: the whole demand of every
  /// counted meal under Everyone, and under a person's lens their weighted
  /// share of it (P-D5). With [demand], the lens's own denominator — `¾ of
  /// 1¾ portions`.
  final double servings;

  /// The full demand of the counted meals — everyone's portions, whoever's
  /// lens this is. Equal to [servings] under Everyone.
  final double demand;

  /// Every meal in scope that did not join the total, named.
  final List<ExcludedMeal> excluded;

  /// Distinct days that put something into [total] — the week average's own
  /// denominator (`6 of 7 days`).
  final int daysContributing;

  /// Nothing was in scope: a day with no meals, or a lens under which this
  /// person eats nothing. A third state, not a zero.
  bool get isEmpty => considered == 0;

  /// Meals were in scope and NONE resolved: draw no number, show the badge
  /// and the reasons.
  bool get isRefused => !isEmpty && total == null;

  /// A total that is honest but short — it must print its denominator and
  /// name what it left out.
  bool get isPartial => total != null && excluded.isNotEmpty;

  /// The per-day average over [daysContributing], or null when there is no
  /// total to average.
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

/// The lens's denominator, named (P-D5): `Jun · ¾ of 1¾ portions`. Null when
/// there is no total to attribute (the refusals print their own words) — and
/// null under Everyone, whose share is the whole and needs no second number.
String? portionShareLine(MealSetMacros macros, {required String? lensName}) {
  if (lensName == null || macros.total == null) return null;
  return '$lensName · ${formatFraction(macros.servings)} of '
      '${formatPortions(macros.demand)}';
}

/// One portion of an INGREDIENT meal, weighed — or the reason it cannot be
/// (step 8.14 / B-D3).
///
/// The rule is the recipe summation's own, applied to one amount instead of a
/// line: the row must have macros, the entry must state an amount, and that
/// amount must reach the row's basis unit (a measure through its stored
/// weight, a cross-basis amount through the density). Nothing is invented at
/// any step — a stub contributes nothing and says so, in the words a stub LINE
/// uses.
///
/// The returned macros are what ONE portion is worth; the caller multiplies by
/// the entry's demand, exactly as it multiplies a recipe's per-serving figure
/// (A-D3 — a snack carries eaters and multiplies).
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
    // An unresolved measure reads as its honest count fallback — a count
    // cannot join a mass/volume total, so the snack is unweighable until the
    // measure row syncs in. Nothing is broken to fix, so it is NOT
    // `needsWeight`: since ADR-0015 that word sends the household to the
    // ingredient's form to enter a number nothing is missing. It degrades
    // the way the recipe engine degrades the same line — unconvertible, in
    // the density's words — until the row syncs in.
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
    // A bare count with nothing weighing it is fixed on the ingredient (its
    // piece weight), so it keeps its own word — the same split the recipe
    // panel makes.
    Err() => (
      perPortion: null,
      reason: unit.family == UnitFamily.count
          ? MacroLineReason.needsWeight
          : MacroLineReason.needsDensity,
    ),
  };
}

/// What ONE planned meal is worth **as served to the people eating it** — the
/// figure the wide Week prints under a dish in the day pane.
///
/// It is [sumPlannedMacros] over a set of one, and deliberately nothing else:
/// a meal's served figure is `perServing × the portions planned`, which is
/// exactly the multiplication a day total already does per entry, and a second
/// implementation of it in a widget is the drift `shared/incomplete_macros.dart`
/// exists to prevent. Everything else follows for free — the lens (a meal
/// somebody else eats is out of scope and comes back [MealSetMacros.isEmpty]),
/// the refusals (an incomplete recipe, a missing one, no eaters, an unweighable
/// snack) and their exact words.
///
/// So the caller draws the same three states it draws for a day, at the scope
/// of one meal: an absence, a refusal that prints no number at all, or a total
/// whose denominator is `1 meal`.
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
/// * **Everyone** ([lensMemberId] null) — `servings = demandPortions`, the
///   household figure: the override, else Σ of the eaters' portion factors.
/// * **A person's lens** — the entry is in scope only if that member is in
///   `eaterIds`, and `servings` is their own factor — the split the household
///   itself declared — scaled by `override ÷ Σ factors` when an override is
///   set (spec §8 calls the override "big/small appetites", so the override IS
///   eating more, shared out in the same proportions). With every factor at 1
///   this is an even split. An entry with NO eaters cannot be attributed to
///   anyone, so under a person's lens it stays in scope and is excluded WITH A
///   REASON — it might be theirs, and pretending otherwise would quietly
///   shrink the denominator.
///
/// [summaryFor] hands back a recipe's per-serving summary (null when the
/// recipe is gone or not loaded); a bare INGREDIENT meal is weighed from the
/// nutrition it already carries (step 8.14), so no second lookup can go
/// missing. [membersById] carries the factors (an absent member counts 1, as
/// [eatersDemand] says). Day and week totals come from this one function over
/// two entry sets, so a week is never a sum of rounded days.
///
/// A snack multiplies exactly like a dish (A-D3): its stated amount is ONE
/// portion, and the same `servings` figure scales it.
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
      // Out of scope entirely: somebody else's meal. Not an exclusion — it
      // was never this person's to count.
      continue;
    }
    considered++;

    final label =
        entry.title ??
        (entry.isIngredient ? '(deleted ingredient)' : '(deleted recipe)');
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

    // The explicit branch (B-D2). A meal names a recipe or an ingredient, and
    // the two are weighed differently — a recipe hands over a per-SERVING
    // summary somebody else computed, a bare ingredient is weighed here from
    // its own stated amount. Neither may fall through: a null `recipe_id` is
    // an ingredient meal, never a meal to skip.
    final Macros? perPortion;
    if (entry.isIngredient) {
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
    } else {
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
