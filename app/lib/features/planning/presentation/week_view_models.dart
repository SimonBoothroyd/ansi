/// Riverpod ViewModels for the Week screen.
///
/// The week is a **position, not a singleton** (D2/D3). [currentWeekStart] is
/// still the Monday of the week containing today, but its only jobs now are
/// (a) seeding [ViewedWeekStart], (b) the "is this week?" emphasis, and (c) the
/// "back to this week" return. [ViewedWeekStart] is the week being LOOKED AT —
/// app-level and keep-alive, so it survives the bottom nav's `context.go`
/// (which replaces the route) and carries across the Week/Cook/Shop tabs.
/// [viewedWeek] streams that week's meals off the repository.
///
/// Mutations don't need their own notifier — views call the keep-alive
/// `planningRepositoryProvider` directly, which stays valid across the async
/// gaps a picker sheet introduces (see the step-3 notifier-lifecycle note,
/// `[[mise-riverpod-notifier-ref-after-async]]`).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/planning_providers.dart';
import '../domain/planning.dart';

part 'week_view_models.g.dart';

/// The Monday of the week containing today.
///
/// Known wart, pre-existing: `DateTime.now()` in a provider doesn't re-fire at
/// midnight, so "today" is stale until the next rebuild (tracker debt).
@riverpod
DateTime currentWeekStart(Ref ref) => mondayOf(DateTime.now());

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

/// The household eater roster.
@riverpod
Future<List<Member>> members(Ref ref) =>
    ref.watch(planningRepositoryProvider).members();

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
