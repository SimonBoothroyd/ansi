/// The cook-plan contract. Pure Dart. The plan is derived ([buildCookPlan]),
/// so the one thing written is what became of a batch's leftovers.
library;

import 'cook_plan.dart';

abstract interface class CookPlanRepository {
  /// The derived cook plan for the week beginning [weekStart] (the week's own
  /// first day), reacting to local writes. Emits an empty [CookPlan] when the
  /// week has no meals.
  Stream<CookPlan> watchCookPlan(DateTime weekStart);

  /// The answers given for the week's batches, keyed by
  /// [CookSession.leftoverKey], live.
  Stream<Map<String, LeftoverAnswer>> watchLeftovers(DateTime weekStart);

  /// Says what became of the uneaten portions of the batch keyed to
  /// [entryId], or — with null — takes the answer back. Either member may
  /// answer.
  Future<void> setLeftover(String entryId, LeftoverAnswer? answer);
}
