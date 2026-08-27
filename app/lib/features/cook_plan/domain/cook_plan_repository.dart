/// The cook-plan read contract — PURE DART (invariant 2). The data layer
/// implements it over PowerSync's local SQLite; ViewModels depend only on this.
///
/// The cook plan is entirely DERIVED (spec §4): there is nothing to write. The
/// repository reads the week's `plan_entry` rows joined to `recipe` shelf life,
/// then hands them to the pure [buildCookPlan]. It reacts to any change to the
/// week or to a covered recipe's shelf life.
library;

import 'cook_plan.dart';

// ignore: one_member_abstracts — an interface for DI/testing, not a callback.
abstract interface class CookPlanRepository {
  /// The derived cook plan for the week beginning [weekStart] (a Monday),
  /// reacting to local writes. Emits an empty [CookPlan] when the week has no
  /// meals (the empty state).
  Stream<CookPlan> watchCookPlan(DateTime weekStart);
}
