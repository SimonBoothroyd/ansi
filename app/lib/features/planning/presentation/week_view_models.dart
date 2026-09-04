/// Riverpod ViewModels for the Week screen.
///
/// The week is a **position, not a singleton** (D2/D3). [currentWeekStart] is
/// still the Monday of the week containing today, but its only jobs now are
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
/// `planningRepositoryProvider` directly, which stays valid across the async
/// gaps a picker sheet introduces (see the step-3 notifier-lifecycle note,
/// `[[mise-riverpod-notifier-ref-after-async]]`).
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:riverpod_annotation/riverpod_annotation.dart';

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

/// The Monday of the week containing [Today]. Moves with it, so it is right
/// across midnight and after a resume; the week on screen does not — that is
/// [ViewedWeekStart]'s job, and it is deliberately left alone.
@riverpod
DateTime currentWeekStart(Ref ref) => mondayOf(ref.watch(todayProvider));

/// The Monday of the week on screen. Defaults to the week containing today;
/// the header switcher moves it and Cook/Shop derive from it (D3).
@Riverpod(keepAlive: true)
class ViewedWeekStart extends _$ViewedWeekStart {
  @override
  DateTime build() => mondayOf(DateTime.now());

  /// Jumps to the week containing [date].
  void set(DateTime date) => state = mondayOf(date);

  /// Steps [weeks] forward (negative steps back). Unbounded in both
  /// directions: a week with no row costs nothing, because the row is only
  /// written on the first meal (`_getOrCreateWeek`).
  void step(int weeks) => state = state.add(Duration(days: 7 * weeks));

  /// Returns to the week containing today.
  void today() => state = mondayOf(DateTime.now());
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

/// Per-recipe macro summaries, indexed by recipe id.
///
/// `watchRecipes()` already carries `macros` on every `RecipeSummary`, so the
/// week needs NO new repository method and no second summation — it reads the
/// same figure the picker rows and the recipe panel show.
@riverpod
Map<String, RecipeMacroSummary> recipeMacrosById(Ref ref) {
  final recipes =
      // Decorative emptiness, weighed (D6): this resolves titles for rows the
      // week already has; an unresolved one falls back to its stored title.
      ref.watch(recipeListProvider).asData?.value ?? const <RecipeSummary>[];
  return {
    for (final r in recipes)
      if (r.macros != null) r.id: r.macros!,
  };
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
  final macros = ref.watch(recipeMacrosByIdProvider);
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
  final macros = ref.watch(recipeMacrosByIdProvider);
  return sumPlannedMacros(
    plan?.entriesForDay(dayOfWeek) ?? const [],
    summaryFor: (id) => macros[id],
    lensMemberId: lens,
    membersById: ref.watch(membersByIdProvider),
  );
}
