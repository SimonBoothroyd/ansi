/// Riverpod ViewModels for the Cook screen.
///
/// [currentCookPlan] streams the derived cook plan for the active week (the
/// same Monday the Week screen uses). It's read-only — the plan is derived, so
/// the only state here is [WholeBatchDisplay], the per-session whole-batch
/// display toggle (step 7.6): flipping it shows the nudged ×N on the tile
/// without persisting anything (a deliberate display-level call — see the
/// 0010 exec plan's decision log).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';

part 'cook_view_models.g.dart';

/// The derived cook plan for the active week, reacting to plan/recipe changes.
@riverpod
Stream<CookPlan> currentCookPlan(Ref ref) => ref
    .watch(cookPlanRepositoryProvider)
    .watchCookPlan(ref.watch(currentWeekStartProvider));

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
