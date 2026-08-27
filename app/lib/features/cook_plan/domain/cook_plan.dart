/// Cook-plan domain — the DERIVED batch view (spec §4).
///
/// PURE DART (invariant 2): no `package:flutter`. The cook plan is a pure
/// function of the week's meals plus each recipe's shelf life — nothing here is
/// persisted (the repository re-derives it on every change). [buildCookPlan]
/// groups the week's meals by recipe; [clusterSessions] splits one recipe into
/// [CookSession]s bounded by its fridge shelf life (`keeps_for_days`), with a
/// freezer *merge* (spec §4 stretch, built): a freezable recipe's later
/// instance folds into one session — cook once, freeze the far share — instead
/// of opening a second session.
///
/// Days are 0=Monday..6=Sunday (matching `plan_entry.day_of_week`). The cook
/// day is the earliest covered day (display-only this step). Scale factor is
/// the raw `total_portions / servings_base` — honest, not nudged to a whole
/// batch.
library;

// Freezed needs each class's private `._` constructor before the factory (for
// the custom getters), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'dart:math' show min;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'cook_plan.freezed.dart';

/// One planned appearance of a recipe in the week — a `plan_entry` reduced to
/// what batching needs: its [dayOfWeek] (0=Mon..6=Sun), [mealSlot], and the
/// [portions] it demands (the entry's override or its eater count).
@freezed
abstract class CoveredMeal with _$CoveredMeal {
  const factory CoveredMeal({
    required int dayOfWeek,
    required String mealSlot,
    required int portions,
  }) = _CoveredMeal;
}

/// A recipe as it appears across the week, before clustering: its shelf life
/// and every [meals] entry that calls for it. The clustering input.
@freezed
abstract class PlannedRecipe with _$PlannedRecipe {
  const factory PlannedRecipe({
    required String recipeId,
    required String title,
    required double servingsBase,

    /// Fridge shelf life in days; drives clustering. Null = unknown (the recipe
    /// has no shelf-life set yet) → the recipe is never split.
    int? keepsForDays,
    @Default(false) bool freezable,

    /// Freezer shelf life in days (only when [freezable]). Null = no limit.
    int? freezerDays,
    @Default(<CoveredMeal>[]) List<CoveredMeal> meals,
  }) = _PlannedRecipe;
}

/// A derived cook session: one batch to cook on [cookDay], covering [covers].
/// Everything past the stored fields is a pure getter over them.
@freezed
abstract class CookSession with _$CookSession {
  const CookSession._();

  const factory CookSession({
    required String recipeId,
    required String recipeTitle,
    required double servingsBase,
    required int cookDay,
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// The meals this batch covers, ascending by day (may include repeats on a
    /// day — e.g. a lunch and a dinner of the same dish).
    @Default(<CoveredMeal>[]) List<CoveredMeal> covers,
  }) = _CookSession;

  /// Distinct covered days, ascending.
  List<int> get coveredDays {
    final set = {for (final m in covers) m.dayOfWeek};
    return set.toList()..sort();
  }

  /// The last day this batch is eaten.
  int get lastCoveredDay => coveredDays.isEmpty ? cookDay : coveredDays.last;

  /// Portions to cook: the sum of every covered meal's demand.
  int get totalPortions => covers.fold(0, (s, m) => s + m.portions);

  /// The raw batch multiplier — `total_portions / servings_base`. Honest, not
  /// rounded to a whole recipe (whole-ingredient scaling is deferred).
  double get scaleFactor =>
      servingsBase == 0 ? 0 : totalPortions / servingsBase;

  /// Covered days that fall past the fridge window and are therefore served
  /// from the freezer (only meaningful for a [freezable] recipe with a known
  /// [keepsForDays]).
  List<int> get frozenDays {
    final keeps = keepsForDays;
    if (!freezable || keeps == null) return const [];
    return [
      for (final d in coveredDays)
        if (d - cookDay > keeps) d,
    ];
  }

  /// True when this batch relies on freezing to reach a later meal.
  bool get hasFreezerRescue => frozenDays.isNotEmpty;
}

/// Every cook session for one recipe, plus recipe-level rollups the card shows.
@freezed
abstract class RecipeCookPlan with _$RecipeCookPlan {
  const RecipeCookPlan._();

  const factory RecipeCookPlan({
    required String recipeId,
    required String title,
    required double servingsBase,
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,
    @Default(<CookSession>[]) List<CookSession> sessions,
  }) = _RecipeCookPlan;

  /// Total portions of this recipe cooked across the week (all sessions).
  int get totalPortions => sessions.fold(0, (s, x) => s + x.totalPortions);

  /// Distinct days this recipe is eaten across the week, ascending.
  List<int> get days {
    final set = {for (final s in sessions) ...s.coveredDays};
    return set.toList()..sort();
  }

  /// The earliest cook day, used to order the plan.
  int get firstCookDay =>
      sessions.isEmpty ? 0 : sessions.map((s) => s.cookDay).reduce(min);

  /// Split into more than one batch because a later meal outran the fridge
  /// window (and the freezer couldn't rescue it).
  bool get isSplit => sessions.length > 1;

  /// Any session leans on the freezer.
  bool get usesFreezer => sessions.any((s) => s.hasFreezerRescue);
}

/// The whole derived cook plan: one [RecipeCookPlan] per recipe on the week,
/// ordered by earliest cook day then title.
@freezed
abstract class CookPlan with _$CookPlan {
  const CookPlan._();

  const factory CookPlan({
    @Default(<RecipeCookPlan>[]) List<RecipeCookPlan> recipes,
  }) = _CookPlan;

  bool get isEmpty => recipes.isEmpty;
}

/// Greedy shelf-life clustering for one recipe (spec §4): sort the days the
/// dish appears; start a session at the first; fold each later meal into the
/// current session while it stays within the fridge window
/// ([PlannedRecipe.keepsForDays]); a meal past the window folds in anyway as a
/// *frozen* share when the recipe is [PlannedRecipe.freezable] and the meal is
/// within the freezer window ([PlannedRecipe.freezerDays], null = no limit);
/// otherwise it opens a new session. O(n log n).
///
/// A recipe with no shelf life (unknown) is never split — it yields a single
/// session covering every meal.
List<CookSession> clusterSessions(PlannedRecipe recipe) {
  if (recipe.meals.isEmpty) return const [];

  // Stable ascending sort by day so same-day meals keep their input order.
  final meals = [...recipe.meals]
    ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

  CookSession sessionFrom(int cookDay, List<CoveredMeal> covers) => CookSession(
    recipeId: recipe.recipeId,
    recipeTitle: recipe.title,
    servingsBase: recipe.servingsBase,
    cookDay: cookDay,
    keepsForDays: recipe.keepsForDays,
    freezable: recipe.freezable,
    freezerDays: recipe.freezerDays,
    covers: List.unmodifiable(covers),
  );

  final keeps = recipe.keepsForDays;
  // Unknown shelf life: one session, no splitting (never invent a window).
  if (keeps == null) {
    return [sessionFrom(meals.first.dayOfWeek, meals)];
  }

  final sessions = <CookSession>[];
  var start = meals.first.dayOfWeek;
  var current = <CoveredMeal>[meals.first];

  for (final meal in meals.skip(1)) {
    final gap = meal.dayOfWeek - start;
    final freezerDays = recipe.freezerDays;
    final freezerReaches =
        recipe.freezable && (freezerDays == null || gap <= freezerDays);
    if (gap <= keeps || freezerReaches) {
      current.add(meal);
    } else {
      sessions.add(sessionFrom(start, current));
      start = meal.dayOfWeek;
      current = [meal];
    }
  }
  sessions.add(sessionFrom(start, current));
  return sessions;
}

/// The batch a meal being added would join, for the planner's "same batch"
/// hint. `withDay` is the day of the shared batch (its cook day, or the meal it
/// now cooks alongside); `frozen` is true when the new meal is reached from the
/// freezer within that batch.
typedef BatchHint = ({int withDay, bool frozen});

/// Whether adding a meal of a recipe on [newDay] would share a cook session
/// with meals already planned on [plannedDays] (same recipe), under the
/// recipe's shelf life. Returns the batch it joins, or null when the new meal
/// would be its own cook. Runs the real [clusterSessions] over the combined
/// days so the hint never disagrees with the cook plan.
BatchHint? batchHintFor({
  required List<int> plannedDays,
  required int newDay,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) {
  if (plannedDays.isEmpty) return null;
  final recipe = PlannedRecipe(
    recipeId: 'hint',
    title: '',
    servingsBase: 1,
    keepsForDays: keepsForDays,
    freezable: freezable,
    freezerDays: freezerDays,
    meals: [
      for (final d in [...plannedDays, newDay])
        CoveredMeal(dayOfWeek: d, mealSlot: 'x', portions: 1),
    ],
  );
  for (final session in clusterSessions(recipe)) {
    final days = session.coveredDays;
    if (!days.contains(newDay)) continue;
    final others = days.where((d) => d != newDay).toList();
    if (others.isEmpty) return null;
    final withDay = others.contains(session.cookDay)
        ? session.cookDay
        : others.first;
    return (withDay: withDay, frozen: session.frozenDays.contains(newDay));
  }
  return null;
}

/// Builds the whole derived cook plan from the week's [recipes], ordering the
/// cards by earliest cook day then title.
CookPlan buildCookPlan(List<PlannedRecipe> recipes) {
  final plans = <RecipeCookPlan>[];
  for (final r in recipes) {
    final sessions = clusterSessions(r);
    if (sessions.isEmpty) continue;
    plans.add(
      RecipeCookPlan(
        recipeId: r.recipeId,
        title: r.title,
        servingsBase: r.servingsBase,
        keepsForDays: r.keepsForDays,
        freezable: r.freezable,
        freezerDays: r.freezerDays,
        sessions: sessions,
      ),
    );
  }
  plans.sort((a, b) {
    final c = a.firstCookDay.compareTo(b.firstCookDay);
    return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return CookPlan(recipes: plans);
}
