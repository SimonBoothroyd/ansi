/// Riverpod ViewModels for the Week screen.
///
/// [currentWeekStart] is the active week's Monday; [currentWeek] streams that
/// week's meals off the repository. Mutations don't need their own notifier —
/// views call the keep-alive `planningRepositoryProvider` directly, which stays
/// valid across the async gaps a picker sheet introduces (see the step-3
/// notifier-lifecycle note, `[[mise-riverpod-notifier-ref-after-async]]`).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/planning_providers.dart';
import '../domain/planning.dart';

part 'week_view_models.g.dart';

/// The Monday of the active week (the week containing today).
@riverpod
DateTime currentWeekStart(Ref ref) => mondayOf(DateTime.now());

/// The active week with its meals, or null until its first meal (empty state).
@riverpod
Stream<WeekPlan?> currentWeek(Ref ref) => ref
    .watch(planningRepositoryProvider)
    .watchWeek(ref.watch(currentWeekStartProvider));

/// The household eater roster.
@riverpod
Future<List<Member>> members(Ref ref) =>
    ref.watch(planningRepositoryProvider).members();

/// The most recent earlier week with meals, for the empty-week reference list
/// and the "copy last week" affordance.
@riverpod
Future<WeekPlan?> lastWeek(Ref ref) => ref
    .watch(planningRepositoryProvider)
    .mostRecentWeekBefore(ref.watch(currentWeekStartProvider));
