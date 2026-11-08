/// The cook-plan contract. Pure Dart. The plan is derived ([buildCookPlan]),
/// so nothing here writes: what a cooked batch left is the leftovers'
/// ([LeftoverRepository]).
library;

import 'cook_plan.dart';
import 'leftover_repository.dart';

// One read, but an interface still: tests stand in a fake for the database.
// ignore: one_member_abstracts
abstract interface class CookPlanRepository {
  /// The derived cook plan for the week beginning [weekStart] (the week's own
  /// first day), reacting to local writes. Emits an empty [CookPlan] when the
  /// week has no meals.
  Stream<CookPlan> watchCookPlan(DateTime weekStart);
}
