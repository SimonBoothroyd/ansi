/// A [CookPlanRepository] that hands back one canned plan.
///
/// Every screen that draws a week reads its cook markers back off the plan, so
/// a host that doesn't override this one reaches for a real database to draw a
/// row. Construct from a built [CookPlan], or from the planned recipes and let
/// [buildCookPlan] cluster them exactly as the repository does.
library;

import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';

class FakeCookPlanRepository implements CookPlanRepository {
  FakeCookPlanRepository([this.plan = const CookPlan()]);

  FakeCookPlanRepository.of(List<PlannedRecipe> recipes)
    : plan = buildCookPlan(recipes);

  final CookPlan plan;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) => Stream.value(plan);

  /// The answers [watchLeftovers] hands out, keyed like the real ones.
  Map<String, LeftoverAnswer> leftovers = const {};

  @override
  Stream<Map<String, LeftoverAnswer>> watchLeftovers(DateTime weekStart) =>
      Stream.value(leftovers);

  /// Every `(entryId, answer)` handed to [setLeftover], in order.
  final leftoverWrites = <(String, LeftoverAnswer?)>[];

  @override
  Future<void> setLeftover(String entryId, LeftoverAnswer? answer) async =>
      leftoverWrites.add((entryId, answer));
}
