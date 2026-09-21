/// Riverpod ViewModels for the Cook screen.
///
/// [currentCookPlan] streams the derived plan for the viewed week (the week the
/// Week screen shows, not the one containing today). The only state is
/// [WholeBatchDisplay], a per-session display toggle that persists nothing.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

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
