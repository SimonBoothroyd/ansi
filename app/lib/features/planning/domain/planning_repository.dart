/// The planning persistence contract — PURE DART (invariant 2). The data layer
/// implements it over PowerSync's local SQLite; ViewModels depend only on this.
///
/// A week is addressed by its Monday (`weekStart`); the repository lazily
/// creates the `week_plan` row on the first write. Mutations are small and
/// targeted (add / remove a meal, retarget its eaters) — no whole-week replace.
library;

import 'planning.dart';

abstract interface class PlanningRepository {
  /// The week beginning [weekStart] (a Monday) with its meals, reacting to
  /// local writes. Emits `null` until the week has its first entry (the empty
  /// state), then a [WeekPlan] whose entries are newest-first within a slot.
  Stream<WeekPlan?> watchWeek(DateTime weekStart);

  /// The most recent week strictly before [weekStart] that has meals, for the
  /// "copy last week" affordance and the empty-week reference list. Null when
  /// there is no earlier planned week.
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart);

  /// Every household member (the eater roster), ordered for display. Members
  /// are server-owned — created at onboarding (`ensure_onboarded`, migration
  /// 0007) and synced down; the app never writes them.
  Future<List<Member>> members();

  /// The most recent planned date (week Monday + day offset) per recipe,
  /// across every week — the recipe picker rows' "last planned" recency
  /// (step 7.7). Recipes never planned are absent from the map.
  Stream<Map<String, DateTime>> watchLastPlanned();

  /// Adds a meal to the week beginning [weekStart], creating the week if
  /// needed. A null [portions] tracks the eater count (spec §8). Returns the
  /// new entry id.
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  });

  /// Replaces the eaters on an entry (demand = |eaterIds|).
  Future<void> setEaters(String entryId, List<String> eaterIds);

  /// Soft-deletes a planned meal.
  Future<void> removeEntry(String entryId);

  /// Copies every meal from [mostRecentWeekBefore] into the week beginning
  /// [weekStart] (creating it if needed). Returns the number of meals copied;
  /// 0 when there is no earlier week to copy.
  Future<int> copyLastWeek(DateTime weekStart);
}
