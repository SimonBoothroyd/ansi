/// The cook-plan read contract. Pure Dart. The plan is derived
/// ([buildCookPlan]), so there is nothing to write.
library;

import 'cook_plan.dart';

// ignore: one_member_abstracts — an interface for DI/testing, not a callback.
abstract interface class CookPlanRepository {
  /// The derived cook plan for the week beginning [weekStart] (the week's own
  /// first day), reacting to local writes. Emits an empty [CookPlan] when the
  /// week has no meals.
  Stream<CookPlan> watchCookPlan(DateTime weekStart);
}
