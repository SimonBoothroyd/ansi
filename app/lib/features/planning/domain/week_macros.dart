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

import '../../../core/units/macros.dart';
import '../../../core/units/portions.dart';
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
}

/// One meal left out of a total, and why. `label` is the dish's title as the
/// week shows it, so the exclusion can be NAMED rather than counted.
typedef ExcludedMeal = ({
  String entryId,
  String label,
  MealExclusion reason,
  RecipeMacroSummary? summary,
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
/// recipe is gone or not loaded); [membersById] carries the factors (an
/// absent member counts 1, as [eatersDemand] says). Day and week totals come
/// from this one function over two entry sets, so a week is never a sum of
/// rounded days.
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

    final label = entry.recipeTitle ?? '(deleted recipe)';
    final factorsSum = eatersDemand(eaters, membersById);
    final demand = demandPortions(entry, membersById);
    if (demand <= 0 ||
        (lensMemberId != null && (eaters.isEmpty || factorsSum <= 0))) {
      excluded.add((
        entryId: entry.id,
        label: label,
        reason: MealExclusion.noEaters,
        summary: null,
      ));
      continue;
    }

    final summary = entry.recipeTitle == null
        ? null
        : summaryFor(entry.recipeId);
    if (summary == null) {
      excluded.add((
        entryId: entry.id,
        label: label,
        reason: MealExclusion.recipeMissing,
        summary: null,
      ));
      continue;
    }
    final perServing = summary.perServing;
    if (perServing == null) {
      excluded.add((
        entryId: entry.id,
        label: label,
        reason: MealExclusion.incomplete,
        summary: summary,
      ));
      continue;
    }

    final servings = lensMemberId == null
        ? demand
        : (membersById[lensMemberId]?.portionFactor ?? 1) *
              (entry.portions == null ? 1 : demand / factorsSum);
    final part = perServing.scaledBy(servings);
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
