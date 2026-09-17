/// The persistence contract for **this week's variant** — PURE DART
/// (invariant 2). The data layer implements it over PowerSync's local SQLite.
///
/// A variant is one set of [LineOverride]s per `(week, recipe)`. The set is
/// written WHOLE: the editor recomputes it from the recipe's lines every save,
/// so the repository's job is to make the stored rows equal the set it is
/// handed — not to apply a patch to whatever was there.
library;

import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../../recipes/domain/recipe_macros.dart';

abstract interface class WeekVariantRepository {
  /// Every override on the week beginning [weekStart], keyed by recipe id and
  /// live — what the dish row's "edited for this week" mark, the cook card's
  /// sub-line and the shopping derivation all read. A recipe with no variant
  /// is absent from the map rather than present and empty.
  Stream<Map<String, List<LineOverride>>> watchWeekOverrides(
    DateTime weekStart,
  );

  /// One recipe's set for that week, as week mode opens on it.
  Future<List<LineOverride>> loadOverrides(DateTime weekStart, String recipeId);

  /// Makes the stored set for `(weekStart, recipeId)` equal [overrides], in
  /// one transaction: rows that are still wanted are updated in place (so a
  /// line keeps one row across many saves), the rest are tombstoned.
  ///
  /// An empty list is "back to the recipe" — it drops the whole variant.
  Future<void> saveOverrides(
    DateTime weekStart,
    String recipeId, {
    required List<LineOverride> overrides,
  });

  /// Ticks one optional line IN for this week, or takes it back out — the
  /// one-tap door, which has no draft and no diff behind it.
  ///
  /// Adds (or removes) a single [LineOverrideAction.include] row inside the
  /// stored set for `(weekStart, recipeId)` and saves that set whole, so the
  /// tap composes with everything else the week already says about the recipe.
  /// Idempotent: asking for the answer the week already gives writes nothing,
  /// and a line the week states its own amount for keeps that amount.
  Future<void> setLineIncluded(
    DateTime weekStart,
    String recipeId,
    String lineId, {
    required bool included,
  });

  /// Macro summaries for the recipes this week actually VARIES: the same
  /// summation the Library runs, over each one's lines after its overrides.
  ///
  /// The week cannot borrow the Library's per-recipe figure for a varied
  /// recipe — a variant makes that figure wrong for the week while leaving it
  /// right on the recipe page and in the Library. A recipe with no variant is
  /// absent, because the Library's figure is still exactly correct for it, and
  /// re-summing every recipe on every week watch would be a second answer to a
  /// question that already has one.
  Stream<Map<String, RecipeMacroSummary>> watchVariantRecipeMacros(
    DateTime weekStart,
  );

  /// The same thing for COST (ADR-0017), for the same reason: a week that
  /// ticks an optional line in has to pay for it, and a week that leaves one
  /// out does not. Absent for a recipe with no variant.
  Stream<Map<String, RecipeCostSummary>> watchVariantRecipeCosts(
    DateTime weekStart,
  );
}
