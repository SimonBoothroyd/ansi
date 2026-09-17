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
/// **A meal that is a bare ingredient is not costed**, and is named with the
/// unpriced lines. A snack has a price the same way a line does, but it is not
/// a recipe and this is the recipes' summation; naming it keeps the gap
/// visible until the receipts phase gives a snack its own reading.
library;

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
  /// ingredient meal's own label. Distinct, because the same unpriced
  /// ingredient in three recipes is one thing to go and price.
  List<String> unpriced,
});

/// Sums `perServing × servings` over [entries], exactly as `sumPlannedMacros`
/// does — see that function for what `servings` means under a lens.
///
/// [costFor] hands back a recipe's cost summary (null when the recipe is gone
/// or not loaded); such a meal is excluded and its title named, because a meal
/// this device cannot resolve is not a meal that costs nothing.
PlannedCost sumPlannedCost(
  Iterable<PlanEntry> entries, {
  required RecipeCostSummary? Function(String recipeId) costFor,
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

    final label =
        entry.title ??
        (entry.isIngredient ? '(deleted ingredient)' : '(deleted recipe)');
    final factorsSum = eatersDemand(eaters, membersById);
    final demand = demandPortions(entry, membersById);
    if (demand <= 0 ||
        (lensMemberId != null && (eaters.isEmpty || factorsSum <= 0))) {
      // Nobody is down to eat it, so there is no demand to multiply. Not a
      // pricing gap — nothing is named, the way the macros name nothing.
      continue;
    }

    // A bare ingredient meal is not a recipe, so it has no recipe cost. It is
    // named rather than skipped: the figure above must not read as if it
    // covered it.
    if (entry.isIngredient) {
      name(label);
      continue;
    }
    final summary = entry.recipeTitle == null ? null : costFor(entry.recipeId!);
    if (summary == null) {
      name(label);
      continue;
    }
    final perServing = summary.perServingCents;
    if (perServing == null) {
      // The recipe's own refusal, passed through by name: these are the lines
      // a person can go and price to make the week's figure whole.
      for (final note in summary.unpriced) {
        name(note.name);
      }
      continue;
    }

    final servings = lensMemberId == null
        ? demand
        : (membersById[lensMemberId]?.portionFactor ?? 1) *
              (entry.portions == null ? 1 : demand / factorsSum);
    total = (total ?? 0) + perServing * servings;
    counted++;
  }

  return (
    cents: total,
    counted: counted,
    considered: considered,
    unpriced: List.unmodifiable(unpriced),
  );
}
