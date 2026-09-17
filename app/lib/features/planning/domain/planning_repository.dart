/// The planning persistence contract — PURE DART (invariant 2). The data layer
/// implements it over PowerSync's local SQLite; ViewModels depend only on this.
///
/// A week is addressed by the date of its own first day (`weekStart`); the
/// repository lazily
/// creates the `week_plan` row on the first write. Mutations are small and
/// targeted (add / remove a meal, retarget its eaters, move it to another
/// slot) — no whole-week replace.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import 'planning.dart';

abstract interface class PlanningRepository {
  /// The week beginning [weekStart] with its meals, reacting to
  /// local writes. Emits `null` until the week has its first entry (the empty
  /// state), then a [WeekPlan] whose entries are newest-first within a slot.
  Stream<WeekPlan?> watchWeek(DateTime weekStart);

  /// The most recent week strictly before [weekStart] that has meals, for the
  /// "copy last week" affordance and the empty-week reference list. Null when
  /// there is no earlier planned week.
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart);

  /// Every household member (the eater roster), ordered for display, live —
  /// the Household sheet's segment and every Portions row read it, so a
  /// factor set on either phone shows on both without a re-open.
  ///
  /// Members are server-owned — created at onboarding (`ensure_onboarded`,
  /// migration 0007) and synced down; the one thing the app writes on them is
  /// the portion factor ([setPortionFactor]).
  Stream<List<Member>> watchMembers();

  /// Sets a member's usual portion: a multiple of one recipe serving in quarter
  /// steps, 0.25–3 ([isValidPortionFactor]; the `0026` check constraint refuses
  /// anything outside the range). Either member may set either's — the row is
  /// household-scoped, not self-scoped.
  Future<void> setPortionFactor(String memberId, double factor);

  /// The most recent planned date (week start + day offset) per recipe,
  /// across every week — the recipe picker rows' "last planned" recency
  /// (step 7.7). Recipes never planned are absent from the map.
  Stream<Map<String, DateTime>> watchLastPlanned();

  /// Adds a RECIPE meal to the week beginning [weekStart], creating the week
  /// if needed. A null [portions] tracks the eater count (spec §8). Returns
  /// the new entry id.
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  });

  /// Adds an INGREDIENT meal — a protein bar, a yoghurt — to the week
  /// beginning [weekStart] (step 8.14 / B-D1). The other half of the entry
  /// XOR: this row names no recipe, and states the amount of ONE portion of
  /// the ingredient instead.
  ///
  /// [quantity] and [unit] are set together or not at all; [measureId] names
  /// the measure the amount is counted in ("1 bar"), in which case [unit]
  /// carries the honest count fallback. It carries eaters and multiplies like
  /// any other entry (A-D3), so [eaterIds] / [portions] mean exactly what they
  /// mean on a dish.
  Future<String> addIngredientEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String ingredientId,
    required List<String> eaterIds,
    double? quantity,
    Unit? unit,
    String? measureId,
    int? portions,
  });

  /// Adds a meal eaten OUT — the words, and the per-portion macros when they
  /// were stated. The third arm of the entry XOR: this row names no recipe and
  /// no ingredient, because there is neither behind it.
  ///
  /// [label] is the meal's whole identity, trimmed and non-empty (the server's
  /// check refuses whitespace). A null [macros] means the figures were not
  /// stated — the meal still fills its slot, and the week names it as
  /// uncounted rather than weighing it at zero. Eaters and [portions] mean
  /// exactly what they mean on a dish: the stated figures are what ONE portion
  /// was worth.
  Future<String> addOutEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String label,
    required List<String> eaterIds,
    Macros? macros,
    int? portions,
  });

  /// Replaces the eaters on an entry (demand = |eaterIds|).
  Future<void> setEaters(String entryId, List<String> eaterIds);

  /// Sets the portions override on an entry. Null tracks |eaters| again
  /// (spec §8) — it is a real value, not "unset", so it is passed explicitly.
  Future<void> setPortions(String entryId, int? portions);

  /// Moves an entry to another slot on the same day. The slot is free text
  /// (spec §8); the caller passes a trimmed, non-empty label. The day is not
  /// a field — a meal changes day by remove-and-re-add.
  Future<void> setMealSlot(String entryId, String mealSlot);

  /// Soft-deletes a planned meal.
  Future<void> removeEntry(String entryId);

  /// Copies every meal from [mostRecentWeekBefore] into the week beginning
  /// [weekStart] (creating it if needed).
  ///
  /// It copies `plan_entry` columns only, so a recipe's **this-week changes**
  /// do not come with it — and the result names each recipe whose variant was
  /// left behind, because a silent drop is the same bug as a silent carry.
  Future<CopyLastWeekResult> copyLastWeek(DateTime weekStart);
}
