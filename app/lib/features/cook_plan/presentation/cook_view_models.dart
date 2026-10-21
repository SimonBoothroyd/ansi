/// Riverpod ViewModels for the Cook screen.
///
/// [currentCookPlan] streams the derived plan for the viewed week (the week the
/// Week screen shows, not the one containing today). The only state is
/// [WholeBatchDisplay], a per-session display toggle that persists nothing.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/units/portions.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';

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

/// Whether a session tile shows the whole-batch view (×N + leftover line)
/// instead of the honest raw factor. Display-only and ephemeral by design.
@riverpod
class WholeBatchDisplay extends _$WholeBatchDisplay {
  @override
  bool build(String sessionKey) => false;

  void toggle() => state = !state;
}

/// What was said about the viewed week's leftovers, keyed by
/// [CookSession.leftoverKey].
@riverpod
Stream<Map<String, LeftoverAnswer>> viewedWeekLeftovers(Ref ref) => ref
    .watch(cookPlanRepositoryProvider)
    .watchLeftovers(ref.watch(viewedWeekStartProvider));

/// How many of the viewed week's days are fully behind us: 0 for a week still
/// to come, 7 for one gone. A batch is over once its last day is.
@riverpod
int viewedWeekDaysPassed(Ref ref) {
  final start = ref.watch(viewedWeekStartProvider);
  final today = ref.watch(todayProvider);
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(start.year, start.month, start.day)).inDays;
  return days.clamp(0, 7);
}

/// The viewed week's leftovers in one line for the Week band — `1 portion
/// binned · 1 kept · 2 left` — counting only batches whose days are over.
/// Null when nothing is left over.
@riverpod
String? weekLeftoverLine(Ref ref) {
  final plan = ref.watch(currentCookPlanProvider).asData?.value;
  if (plan == null) return null;
  final answers =
      ref.watch(viewedWeekLeftoversProvider).asData?.value ?? const {};
  return leftoverLineFor(
    plan,
    answers: answers,
    daysPassed: ref.watch(viewedWeekDaysPassedProvider),
  );
}

/// [weekLeftoverLine]'s arithmetic, pure: answered batches by what became of
/// them, unanswered ones as simply left.
String? leftoverLineFor(
  CookPlan plan, {
  required Map<String, LeftoverAnswer> answers,
  required int daysPassed,
}) {
  var kept = 0.0;
  var binned = 0.0;
  var left = 0.0;
  for (final recipe in plan.recipes) {
    for (final s in recipe.mealSessions) {
      if (!s.isOverAfter(daysPassed) || s.uneatenPortions <= 0) continue;
      final a = answers[s.leftoverKey];
      if (a == null) {
        left += s.uneatenPortions;
      } else {
        kept += a.kept;
        binned += a.binned;
      }
    }
  }
  final parts = [
    if (binned > 0) (binned, 'binned'),
    if (kept > 0) (kept, 'kept'),
    if (left > 0) (left, 'left'),
  ];
  if (parts.isEmpty) return null;
  final (n, w) = parts.first;
  return [
    '${formatPortions(n)} $w',
    for (final (n, w) in parts.skip(1)) '${formatFraction(n)} $w',
  ].join(' · ');
}
