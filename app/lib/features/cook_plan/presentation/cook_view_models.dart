/// Riverpod ViewModels for the Cook screen.
///
/// [currentCookPlan] streams the derived plan for the viewed week (the week the
/// Week screen shows, not the one containing today). The only state is
/// [WholeBatchDisplay], a per-session display toggle that persists nothing.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/units/portions.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';
import '../domain/leftovers.dart';

part 'cook_view_models.g.dart';

/// The derived cook plan for the viewed week, reacting to plan/recipe changes.
@riverpod
Stream<CookPlan> currentCookPlan(Ref ref) => ref
    .watch(cookPlanRepositoryProvider)
    .watchCookPlan(ref.watch(viewedWeekStartProvider));

/// The stable per-session key the display toggle is filed under (a session
/// has no persisted id — the plan is derived).
String cookSessionKey(CookSession session) =>
    '${session.recipeId}:${session.cookDay}';

/// Whether a session shows the whole batch (×N, with the portions spare)
/// instead of the exact factor. Display-only and ephemeral by design.
@riverpod
class WholeBatchDisplay extends _$WholeBatchDisplay {
  @override
  bool build(String sessionKey) => false;

  // A call, not a setter: the switch asks for a side, it does not assign one.
  // ignore: use_setters_to_change_properties
  void show({required bool whole}) => state = whole;
}

/// What was said about the viewed week's leftovers, keyed by
/// [CookSession.leftoverKey].
@riverpod
Stream<Map<String, LeftoverAnswer>> viewedWeekLeftovers(Ref ref) => ref
    .watch(cookPlanRepositoryProvider)
    .watchLeftovers(ref.watch(viewedWeekStartProvider));

/// The cooked batches of the week beginning [weekStart] with portions still
/// left today, live (plan 0059).
@riverpod
Stream<List<BatchLeftover>> weekBatchLeftovers(Ref ref, DateTime weekStart) =>
    ref
        .watch(cookPlanRepositoryProvider)
        .watchBatchLeftovers(weekStart, today: ref.watch(todayProvider));

/// The leftovers a meal on [day] can be planned from, soonest use-by first:
/// cooked this week or last, still good on [day], and [day] not behind us.
/// Empty while either week loads.
@riverpod
List<BatchLeftover> leftoversGoodOn(Ref ref, DateTime day) {
  final today = ref.watch(todayProvider);
  if (DateTime(day.year, day.month, day.day).isBefore(today)) return const [];
  final shape = ref.watch(weekShapeProvider);
  final week = shape.weekStartOf(day);
  final before = shape.weekStartOf(
    DateTime(week.year, week.month, week.day - 7),
  );
  return [
    for (final w in [before, week])
      for (final left
          in ref.watch(weekBatchLeftoversProvider(w)).asData?.value ??
              const <BatchLeftover>[])
        if (left.isGoodOn(day) && !left.isDueOn(today)) left,
  ]..sort((a, b) => a.useBy.compareTo(b.useBy));
}

/// The viewed week's leftovers in one line for the Week band — `1 portion
/// binned · 2 left`. Null when nothing is left over.
@riverpod
String? weekLeftoverLine(Ref ref) {
  final answers =
      ref.watch(viewedWeekLeftoversProvider).asData?.value ?? const {};
  final leftovers =
      ref
          .watch(weekBatchLeftoversProvider(ref.watch(viewedWeekStartProvider)))
          .asData
          ?.value ??
      const <BatchLeftover>[];
  return leftoverLineFor(answers: answers, leftovers: leftovers);
}

/// [weekLeftoverLine]'s arithmetic, pure: what was binned (the only waste) and
/// eaten after all, by Cook's answers, then what cooked batches still have
/// left ([batchLeftovers]).
String? leftoverLineFor({
  required Map<String, LeftoverAnswer> answers,
  required List<BatchLeftover> leftovers,
}) {
  final binned = answers.values.fold<double>(0, (n, a) => n + a.binned);
  final left = leftovers.fold<double>(0, (n, l) => n + l.portions);
  final parts = [
    if (binned > 0) (binned, 'binned'),
    if (left > 0) (left, 'left'),
  ];
  if (parts.isEmpty) return null;
  final (n, w) = parts.first;
  return [
    '${formatPortions(n)} $w',
    for (final (n, w) in parts.skip(1)) '${formatFraction(n)} $w',
  ].join(' · ');
}
