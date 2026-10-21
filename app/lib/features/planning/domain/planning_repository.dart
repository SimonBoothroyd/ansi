/// The planning persistence contract. Pure Dart.
///
/// A week is addressed by the date of its first day (`weekStart`); its
/// `week_plan` row is created on the first write. Mutations are small and
/// targeted, never a whole-week replace.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/default_amount.dart';
import 'plan_change.dart';
import 'planning.dart';

abstract interface class PlanningRepository {
  /// The week beginning [weekStart] with its meals, live. Emits `null` until
  /// the week has its first entry.
  Stream<WeekPlan?> watchWeek(DateTime weekStart);

  /// The most recent week strictly before [weekStart] that has meals, or null.
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart);

  /// Every household member, ordered for display, live. Members are
  /// server-owned; the app writes only the portion factor ([setPortionFactor]).
  Stream<List<Member>> watchMembers();

  /// Sets a member's usual portion ([isValidPortionFactor]). Either member may
  /// set either's.
  Future<void> setPortionFactor(String memberId, double factor);

  /// The most recent planned date per recipe across every week. Never-planned
  /// recipes are absent.
  Stream<Map<String, DateTime>> watchLastPlanned();

  /// Adds a recipe meal to the week beginning [weekStart], creating the week if
  /// needed. A null [portions] tracks the eater count. Returns the new entry
  /// id.
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  });

  /// Adds an ingredient meal, stating the amount of one portion. [quantity] and
  /// [unit] are set together or not at all; with [measureId], [unit] carries
  /// the count fallback. [eaterIds] and [portions] mean what they mean on a
  /// dish.
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

  /// Adds a meal eaten out. [label] is trimmed and non-empty. A null [macros]
  /// means not stated: the meal fills its slot uncounted. Stated figures are
  /// per portion.
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

  /// Sets the portions override. Null tracks the eater count, so it is passed
  /// explicitly.
  Future<void> setPortions(String entryId, int? portions);

  /// Moves an entry to another slot on the same day. [mealSlot] is a trimmed,
  /// non-empty label.
  Future<void> setMealSlot(String entryId, String mealSlot);

  /// Soft-deletes a planned meal.
  Future<void> removeEntry(String entryId);

  /// Brings back a meal [removeEntry] took away — the same row, so whatever
  /// hangs off it (who ate it) comes back with it.
  Future<void> restoreEntry(String entryId);

  /// Says [memberId] ate the meal at [eatenAt], or — with null — that they did
  /// not. A second call moves the time. Only the member signed in on this
  /// phone may be named: the server refuses anyone else (0055). A tick takes
  /// back whatever they had instead.
  Future<void> setMealEaten(
    String entryId, {
    required String memberId,
    required DateTime? eatenAt,
  });

  /// Says [memberId] had [meal] instead of the planned meal [entryId], or —
  /// with null — that they had nothing else. Replaces what they had said
  /// before, and takes back their tick: a member either ate the meal or had
  /// something else. The substitute is never cooked, bought or costed.
  Future<void> setInstead(
    String entryId, {
    required String memberId,
    required InsteadMeal? meal,
  });

  /// Copies every meal from [mostRecentWeekBefore] into the week beginning
  /// [weekStart]. This-week recipe variants are not copied; the result names
  /// each one left behind.
  Future<CopyLastWeekResult> copyLastWeek(DateTime weekStart);

  /// Writes [changes] in one transaction, in order, or none of them. Each
  /// change that names an existing meal is checked against the meal as it now
  /// stands; any difference throws [PlanChangedError] and nothing is written.
  Future<void> applyPlanChanges(List<PlanChange> changes);

  /// The amount of the latest planned meal of [ingredientId] that stated one,
  /// or null. A sheet and Ask Ansi offer it again (`defaultAmountFor`).
  Future<LastAmount?> lastIngredientAmount(String ingredientId);
}
