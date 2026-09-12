/// Riverpod ViewModels for the Week screen.
///
/// The week is a **position, not a singleton** (D2/D3). [currentWeekStart] is
/// still the first day of the week containing today, but its only jobs now are
/// (a) seeding [ViewedWeekStart], (b) the "is this week?" emphasis, and (c) the
/// switcher menu's "This week" return. It derives from [Today], the one place
/// the app asks what day it is, which re-fires at local midnight and on resume
/// — so "today" moves while the app stays open, and ONLY today moves.
/// [ViewedWeekStart] is the week being LOOKED AT — app-level and keep-alive,
/// so it survives the bottom nav's `context.go` (which replaces the route),
/// carries across the Week/Cook/Shop tabs, and does not jump at midnight.
/// [viewedWeek] streams that week's meals off the repository.
///
/// Mutations don't need their own notifier — views call the keep-alive
/// [planningRepositoryProvider] directly, which stays valid across the async
/// gaps a picker sheet introduces — a throwaway notifier does not, because
/// Riverpod disposes it underneath the call.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/week_shape.dart';
import '../../account/data/household_providers.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import '../domain/week_macros.dart';

part 'week_view_models.g.dart';

/// The wall clock, as a seam: production reads [DateTime.now]; a test
/// overrides this with a fixed or scripted clock and drives [Today] across a
/// midnight it chooses. Keep-alive because [Today] is, and a keep-alive
/// provider may only depend on keep-alive providers (riverpod_lint).
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

/// The current LOCAL calendar day — midnight, local time, date-only.
///
/// A `DateTime.now()` read once in a provider is stale from midnight until
/// something else rebuilds the tree, which the TODAY pill made visible. This
/// re-fires twice over: one [Timer] armed for the next local midnight, whose
/// callback re-arms it (a 23- or 25-hour DST day is simply a different wait),
/// and an [AppLifecycleListener] for resume, because a phone asleep in a
/// pocket suspends timers and may wake past several midnights. Keep-alive so
/// the timer outlives the screens that read it; both hooks are released in
/// `onDispose`, which also runs if [clock] is ever overridden mid-flight.
///
/// The state is a value, so listeners are told only when the day actually
/// changes — a resume at 3 pm on the same day is silent.
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

/// The first day of the week containing [Today]. Moves with it, so it is right
/// across midnight and after a resume; the week on screen does not — that is
/// [ViewedWeekStart]'s job, and it is deliberately left alone.
@riverpod
DateTime currentWeekStart(Ref ref) =>
    ref.watch(weekShapeProvider).weekStartOf(ref.watch(todayProvider));

/// The first day of the week on screen. Defaults to the week containing today;
/// the header switcher moves it and Cook/Shop derive from it (D3).
///
/// It watches the household's [WeekShape], so flipping the first day re-seats
/// the screen on the window containing today under the new shape — which is
/// what "this week" means the moment the weeks move.
@Riverpod(keepAlive: true)
class ViewedWeekStart extends _$ViewedWeekStart {
  @override
  DateTime build() => ref.watch(weekShapeProvider).weekStartOf(DateTime.now());

  /// The shape as it stands. [build] is what WATCHES it — these movers only
  /// need the current value to resolve a date into a week.
  WeekShape get _shape => ref.read(weekShapeProvider);

  /// Jumps to the week containing [date].
  void set(DateTime date) => state = _shape.weekStartOf(date);

  /// Steps [weeks] forward (negative steps back). Unbounded in both
  /// directions: a week with no row costs nothing, because the row is only
  /// written on the first meal (`_getOrCreateWeek`).
  void step(int weeks) => state = state.add(Duration(days: 7 * weeks));

  /// Returns to the week containing today.
  void today() => state = _shape.weekStartOf(DateTime.now());
}

/// The viewed week with its meals, or null while it has no row yet — which
/// means "seven empty days", not "a different screen" (D5).
@riverpod
Stream<WeekPlan?> viewedWeek(Ref ref) => ref
    .watch(planningRepositoryProvider)
    .watchWeek(ref.watch(viewedWeekStartProvider));

/// The household eater roster, live — a portion factor set on either phone
/// reaches every Portions row and the Household sheet as it lands.
@riverpod
Stream<List<Member>> members(Ref ref) =>
    ref.watch(planningRepositoryProvider).watchMembers();

/// The most recent planned week before the VIEWED one — what "copy last week"
/// would copy, so it is relative to the week you are standing on.
@riverpod
Future<WeekPlan?> lastWeek(Ref ref) => ref
    .watch(planningRepositoryProvider)
    .mostRecentWeekBefore(ref.watch(viewedWeekStartProvider));

/// Most recent planned date per recipe, across every week — the picker
/// rows' "last planned" recency (7.7).
@riverpod
Stream<Map<String, DateTime>> lastPlannedByRecipe(Ref ref) =>
    ref.watch(planningRepositoryProvider).watchLastPlanned();

/// Every override on the viewed week, keyed by recipe id — what the dish
/// row's "edited for this week" mark and the cook card's sub-line read, and
/// what the editor's own draft starts from.
@riverpod
Stream<Map<String, List<LineOverride>>> viewedWeekOverrides(Ref ref) => ref
    .watch(weekVariantRepositoryProvider)
    .watchWeekOverrides(ref.watch(viewedWeekStartProvider));

/// How the week a `?week=` link names holds one recipe: the days it plans it
/// on, in order, and whether the week varies it.
///
/// An empty `days` is the GUARD the recipe page's planned-arrival band and its
/// week door both stand on. The link is a fact about where the tap came from,
/// and the week can have moved on since — the meal removed, the link kept in a
/// back stack — so the page asks the week itself rather than trusting the
/// parameter. An unparseable key answers the same way.
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

/// The week [weekKey] names, with its meals — a sibling of [viewedWeek] keyed
/// by the link rather than by what is on screen.
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

/// The re-summed figures for the recipes the week [weekKey] names varies — the
/// sibling of [variantRecipeMacros] keyed by the link rather than by the week
/// on screen, for the recipe page opened from a week that plans it.
///
/// A recipe the week does not vary is absent, and its reader falls back to the
/// Library's figure, which is exactly right for it.
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

/// An ISO `YYYY-MM-DD` week key as the first day of the week it names, or null
/// when it is not a date.
///
/// The key already IS a week start, so [shape] normally changes nothing. It is
/// applied anyway because a `?week=` param can outlive the shape that minted it
/// — a link in a back stack, a household that flipped — and the week a date
/// belongs to is the honest answer to a stale one.
DateTime? weekStartOfKey(String weekKey, WeekShape shape) {
  final date = DateTime.tryParse(weekKey);
  return date == null ? null : shape.weekStartOf(date);
}

/// Per-recipe macro summaries **for the viewed week**, indexed by recipe id.
///
/// The Library's figure underneath, the week's own on top. A recipe the week
/// does not vary is still exactly what `watchRecipes` computed — the same
/// figure the picker rows and the recipe panel show — and a recipe it does
/// vary is re-summed over the week's effective lines, because the Library's
/// number is wrong for this week and right everywhere else.
@riverpod
Map<String, RecipeMacroSummary> weekRecipeMacros(Ref ref) {
  final recipes =
      // Decorative emptiness, weighed (D6): this resolves figures for rows the
      // week already has; an unresolved one simply has none.
      ref.watch(recipeListProvider).asData?.value ?? const <RecipeSummary>[];
  return {
    for (final r in recipes)
      if (r.macros != null) r.id: r.macros!,
    ...ref.watch(variantRecipeMacrosProvider).asData?.value ?? const {},
  };
}

/// The re-summed figures for the recipes the viewed week varies — usually
/// none, in which case the map above is the Library's, untouched.
@riverpod
Stream<Map<String, RecipeMacroSummary>> variantRecipeMacros(Ref ref) => ref
    .watch(weekVariantRepositoryProvider)
    .watchVariantRecipeMacros(ref.watch(viewedWeekStartProvider));

/// What the last copy carried, and what it left behind — held for the week it
/// is about, so moving off that week and back does not re-announce it.
///
/// A **state**, not a toast: it reports a part of an act that did not happen,
/// it stays true until the person does something about it, and it names rows
/// they may want to open. Cleared by reading it once the week moves.
@Riverpod(keepAlive: true)
class LastCopyReport extends _$LastCopyReport {
  @override
  ({DateTime weekStart, CopyLastWeekResult result})? build() => null;

  void record(DateTime weekStart, CopyLastWeekResult result) =>
      state = (weekStart: weekStart, result: result);

  void clear() => state = null;
}

/// The roster keyed by id — the portion factors every demand and lens share is
/// weighted by.
@riverpod
Map<String, Member> membersById(Ref ref) => {
  for (final m in ref.watch(membersProvider).asData?.value ?? const <Member>[])
    m.id: m,
};

/// The viewed week's macros under [lens] (null = Everyone) — D4.
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

/// One day's macros under [lens] — the SAME function over a narrower set, so
/// the week is never a sum of rounded day totals.
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
