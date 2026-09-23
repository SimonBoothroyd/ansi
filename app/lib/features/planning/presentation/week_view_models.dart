/// Riverpod view models for the Week screen.
///
/// [currentWeekStart] is the week containing [Today]; [ViewedWeekStart] is the
/// week on screen, keep-alive so it survives tab switches and does not jump at
/// midnight. Views write through the keep-alive [planningRepositoryProvider]
/// directly: a throwaway notifier is disposed across a picker sheet's async
/// gap.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/week_shape.dart';
import '../../account/data/household_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/price.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import '../domain/week_cost.dart';
import '../domain/week_macros.dart';

part 'week_view_models.g.dart';

/// The wall clock, overridable in tests. Keep-alive because [Today] is.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

/// The current local calendar day (midnight, date-only).
///
/// Re-fires from a [Timer] armed for the next local midnight and from an
/// [AppLifecycleListener] on resume, since a sleeping phone suspends timers.
/// Listeners are told only when the day changes.
@Riverpod(keepAlive: true)
class Today extends _$Today {
  @override
  DateTime build() {
    final now = ref.watch(clockProvider);
    Timer? timer;
    void arm() {
      final at = now();
      // The local constructor normalises day + 1 across month and year ends.
      final midnight = DateTime(at.year, at.month, at.day + 1);
      timer = Timer(midnight.difference(at), () {
        state = _dateOf(now());
        arm();
      });
    }

    arm();
    final lifecycle = AppLifecycleListener(
      onResume: () => state = _dateOf(now()),
    );
    ref
      ..onDispose(() => timer?.cancel())
      ..onDispose(lifecycle.dispose);
    return _dateOf(now());
  }

  static DateTime _dateOf(DateTime at) => DateTime(at.year, at.month, at.day);
}

/// The first day of the week containing [Today]. Moves at midnight; the week on
/// screen ([ViewedWeekStart]) does not.
@riverpod
DateTime currentWeekStart(Ref ref) =>
    ref.watch(weekShapeProvider).weekStartOf(ref.watch(todayProvider));

/// The first day of the week on screen; Cook and Shop derive from it. Defaults
/// to the week containing today, and re-seats there when the household's
/// [WeekShape] changes.
@Riverpod(keepAlive: true)
class ViewedWeekStart extends _$ViewedWeekStart {
  @override
  DateTime build() => ref.watch(weekShapeProvider).weekStartOf(DateTime.now());

  /// The current shape; [build] is what watches it.
  WeekShape get _shape => ref.read(weekShapeProvider);

  /// Jumps to the week containing [date].
  void set(DateTime date) => state = _shape.weekStartOf(date);

  /// Steps [weeks] forward (negative steps back), unbounded: a week's row is
  /// only written on its first meal.
  void step(int weeks) => state = state.add(Duration(days: 7 * weeks));

  /// Returns to the week containing today.
  void today() => state = _shape.weekStartOf(DateTime.now());
}

/// The viewed week with its meals, or null while it has no row (seven empty
/// days).
@riverpod
Stream<WeekPlan?> viewedWeek(Ref ref) => ref
    .watch(planningRepositoryProvider)
    .watchWeek(ref.watch(viewedWeekStartProvider));

/// The household eater roster, live.
@riverpod
Stream<List<Member>> members(Ref ref) =>
    ref.watch(planningRepositoryProvider).watchMembers();

/// The most recent planned week before the viewed one — what "copy last week"
/// copies.
@riverpod
Future<WeekPlan?> lastWeek(Ref ref) => ref
    .watch(planningRepositoryProvider)
    .mostRecentWeekBefore(ref.watch(viewedWeekStartProvider));

/// Most recent planned date per recipe, for the picker's "last planned".
@riverpod
Stream<Map<String, DateTime>> lastPlannedByRecipe(Ref ref) =>
    ref.watch(planningRepositoryProvider).watchLastPlanned();

/// Every override on the viewed week, keyed by recipe id.
@riverpod
Stream<Map<String, List<LineOverride>>> viewedWeekOverrides(Ref ref) => ref
    .watch(weekVariantRepositoryProvider)
    .watchWeekOverrides(ref.watch(viewedWeekStartProvider));

/// How the week a `?week=` link names holds one recipe: the days it plans it
/// on, and whether the week varies it. Empty `days` means the link is stale (or
/// unparseable), and the recipe page then hides its week door.
typedef WeekRecipePlacement = ({List<int> days, bool edited});

@riverpod
WeekRecipePlacement weekRecipePlacement(
  Ref ref,
  String recipeId,
  String weekKey,
) {
  final weekStart = weekStartOfKey(weekKey, ref.watch(weekShapeProvider));
  if (weekStart == null) return const (days: <int>[], edited: false);
  final plan = ref.watch(weekPlanForProvider(weekKey)).asData?.value;
  final days = <int>{
    for (final e in plan?.entries ?? const <PlanEntry>[])
      if (e.recipeId == recipeId) e.dayOfWeek,
  }.toList()..sort();
  final overrides =
      ref.watch(weekOverridesForProvider(weekKey)).asData?.value ?? const {};
  return (days: days, edited: (overrides[recipeId] ?? const []).isNotEmpty);
}

/// The week [weekKey] names, with its meals.
@riverpod
Stream<WeekPlan?> weekPlanFor(Ref ref, String weekKey) {
  final weekStart = weekStartOfKey(weekKey, ref.watch(weekShapeProvider));
  return weekStart == null
      ? Stream.value(null)
      : ref.watch(planningRepositoryProvider).watchWeek(weekStart);
}

/// That same week's overrides, keyed by recipe id.
@riverpod
Stream<Map<String, List<LineOverride>>> weekOverridesFor(
  Ref ref,
  String weekKey,
) {
  final weekStart = weekStartOfKey(weekKey, ref.watch(weekShapeProvider));
  return weekStart == null
      ? Stream.value(const {})
      : ref.watch(weekVariantRepositoryProvider).watchWeekOverrides(weekStart);
}

/// [variantRecipeMacros] for the week [weekKey] names. A recipe the week does
/// not vary is absent.
@riverpod
Stream<Map<String, RecipeMacroSummary>> weekVariantMacrosFor(
  Ref ref,
  String weekKey,
) {
  final weekStart = weekStartOfKey(weekKey, ref.watch(weekShapeProvider));
  return weekStart == null
      ? Stream.value(const {})
      : ref
            .watch(weekVariantRepositoryProvider)
            .watchVariantRecipeMacros(weekStart);
}

/// The same for cost (ADR-0017).
@riverpod
Stream<Map<String, RecipeCostSummary>> weekVariantCostsFor(
  Ref ref,
  String weekKey,
) {
  final weekStart = weekStartOfKey(weekKey, ref.watch(weekShapeProvider));
  return weekStart == null
      ? Stream.value(const {})
      : ref
            .watch(weekVariantRepositoryProvider)
            .watchVariantRecipeCosts(weekStart);
}

/// Per-recipe cost summaries for the viewed week: the Library's figure,
/// overlaid by the week's own where it varies the recipe.
@riverpod
Map<String, RecipeCostSummary> weekRecipeCosts(Ref ref) => {
  ...?ref.watch(recipeCostsProvider).asData?.value,
  ...?ref.watch(variantRecipeCostsProvider).asData?.value,
};

/// The re-costed figures for the recipes the viewed week varies.
@riverpod
Stream<Map<String, RecipeCostSummary>> variantRecipeCosts(Ref ref) => ref
    .watch(weekVariantRepositoryProvider)
    .watchVariantRecipeCosts(ref.watch(viewedWeekStartProvider));

/// What the viewed week costs to cook under [lens], over the same entries and
/// portions as [weekMacros]. Recipes are priced from their summaries, bare
/// ingredients from the latest vocabulary prices.
@riverpod
PlannedCost weekCost(Ref ref, String? lens) {
  final plan = ref.watch(viewedWeekProvider).asData?.value;
  final costs = ref.watch(weekRecipeCostsProvider);
  final prices =
      ref.watch(costPriceMapProvider).asData?.value ??
      const <String, UnitPrice>{};
  return sumPlannedCost(
    plan?.entries ?? const [],
    costFor: (id) => costs[id],
    priceFor: (id) => prices[id],
    lensMemberId: lens,
    membersById: ref.watch(membersByIdProvider),
  );
}

/// An ISO `YYYY-MM-DD` week key as the first day of its week, or null when it
/// is not a date. [shape] is applied because a link can outlive the shape that
/// minted it.
DateTime? weekStartOfKey(String weekKey, WeekShape shape) {
  final date = DateTime.tryParse(weekKey);
  return date == null ? null : shape.weekStartOf(date);
}

/// Per-recipe macro summaries for the viewed week, by recipe id: the Library's
/// figure, re-summed over the week's effective lines where it varies the
/// recipe.
@riverpod
Map<String, RecipeMacroSummary> weekRecipeMacros(Ref ref) {
  final recipes =
      // An unloaded recipe list simply resolves no figures.
      ref.watch(recipeListProvider).asData?.value ?? const <RecipeSummary>[];
  return {
    for (final r in recipes)
      if (r.macros != null) r.id: r.macros!,
    ...ref.watch(variantRecipeMacrosProvider).asData?.value ?? const {},
  };
}

/// The re-summed figures for the recipes the viewed week varies.
@riverpod
Stream<Map<String, RecipeMacroSummary>> variantRecipeMacros(Ref ref) => ref
    .watch(weekVariantRepositoryProvider)
    .watchVariantRecipeMacros(ref.watch(viewedWeekStartProvider));

/// What the last copy carried and left behind, held for the week it is about. A
/// state rather than a toast, so it stays until the week moves.
@Riverpod(keepAlive: true)
class LastCopyReport extends _$LastCopyReport {
  @override
  ({DateTime weekStart, CopyLastWeekResult result})? build() => null;

  void record(DateTime weekStart, CopyLastWeekResult result) =>
      state = (weekStart: weekStart, result: result);

  void clear() => state = null;
}

/// The roster keyed by id.
@riverpod
Map<String, Member> membersById(Ref ref) => {
  for (final m in ref.watch(membersProvider).asData?.value ?? const <Member>[])
    m.id: m,
};

/// The viewed week's macros under [lens] (null = Everyone).
@riverpod
MealSetMacros weekMacros(Ref ref, String? lens) {
  final plan = ref.watch(viewedWeekProvider).asData?.value;
  final macros = ref.watch(weekRecipeMacrosProvider);
  return sumPlannedMacros(
    plan?.entries ?? const [],
    summaryFor: (id) => macros[id],
    lensMemberId: lens,
    membersById: ref.watch(membersByIdProvider),
  );
}

/// One meal's macros under [lens], as served. Keyed by entry id so it follows
/// the live week; an id the week no longer has reads as an empty set.
@riverpod
MealSetMacros mealMacros(Ref ref, String entryId, String? lens) {
  final plan = ref.watch(viewedWeekProvider).asData?.value;
  final entries = [
    for (final e in plan?.entries ?? const <PlanEntry>[])
      if (e.id == entryId) e,
  ];
  if (entries.isEmpty) return const MealSetMacros();
  final macros = ref.watch(weekRecipeMacrosProvider);
  return servedMealMacros(
    entries.first,
    summaryFor: (id) => macros[id],
    lensMemberId: lens,
    membersById: ref.watch(membersByIdProvider),
  );
}

/// One day's macros under [lens], from the same function as the week's so the
/// week is never a sum of rounded days.
@riverpod
MealSetMacros dayMacros(Ref ref, int dayOfWeek, String? lens) {
  final plan = ref.watch(viewedWeekProvider).asData?.value;
  final macros = ref.watch(weekRecipeMacrosProvider);
  return sumPlannedMacros(
    plan?.entriesForDay(dayOfWeek) ?? const [],
    summaryFor: (id) => macros[id],
    lensMemberId: lens,
    membersById: ref.watch(membersByIdProvider),
  );
}
