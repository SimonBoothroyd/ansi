/// A set of changes to the plan written together or not at all: what an
/// Ask Ansi proposal card writes on Confirm. Pure Dart.
///
/// Every change that touches an existing meal carries the meal as the card
/// showed it ([PlanChange.expected]). The write re-reads each one inside its
/// transaction and refuses the whole set when any differs
/// ([PlanChangedError]), so a card never overwrites an edit made after it was
/// drawn.
library;

import 'package:meta/meta.dart';

import '../../../core/units/units.dart';
import 'planning.dart';

/// What a new meal is: exactly one of the three plan-entry kinds.
@immutable
sealed class PlanTarget {
  const PlanTarget();
}

final class PlanRecipeTarget extends PlanTarget {
  const PlanRecipeTarget(this.recipeId);
  final String recipeId;
}

/// A bare ingredient and one portion of it. With no [quantity] the meal
/// states no amount and buys nothing until one is set on the Week. With
/// [measureId] the amount is a count of that measure and [unit] is the count
/// fallback, as the Week stores it.
final class PlanIngredientTarget extends PlanTarget {
  const PlanIngredientTarget(
    this.ingredientId, {
    this.quantity,
    this.unit,
    this.measureId,
  }) : assert(
         (quantity == null) == (unit == null),
         'an amount is a number and a unit together',
       );
  final String ingredientId;
  final double? quantity;
  final Unit? unit;
  final String? measureId;
}

final class PlanOutTarget extends PlanTarget {
  const PlanOutTarget(this.label);
  final String label;
}

@immutable
sealed class PlanChange {
  const PlanChange();

  /// The meal this change acts on, as it stood when the change was drawn;
  /// null for an add.
  PlanEntry? get expected;
}

/// A new meal on [dayOfWeek] of the week beginning [weekStart].
final class PlanAdd extends PlanChange {
  const PlanAdd({
    required this.weekStart,
    required this.dayOfWeek,
    required this.mealSlot,
    required this.target,
    required this.eaterIds,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final String mealSlot;
  final PlanTarget target;
  final List<String> eaterIds;

  @override
  PlanEntry? get expected => null;
}

/// The meal [expected] taken off the plan.
final class PlanRemove extends PlanChange {
  const PlanRemove(this.expected);

  @override
  final PlanEntry expected;
}

/// The meal [expected] moved to another day or slot, possibly in another
/// week. Written as a remove and an add of the same meal, eaters, amount and
/// portions, as the Week moves a meal between days.
final class PlanMove extends PlanChange {
  const PlanMove(
    this.expected, {
    required this.weekStart,
    required this.dayOfWeek,
    required this.mealSlot,
  });

  @override
  final PlanEntry expected;
  final DateTime weekStart;
  final int dayOfWeek;
  final String mealSlot;
}

/// The meal [expected] eaten by [eaterIds] instead.
final class PlanSetEaters extends PlanChange {
  const PlanSetEaters(this.expected, this.eaterIds);

  @override
  final PlanEntry expected;
  final List<String> eaterIds;
}

/// What [memberId] had instead of the meal [expected]. The plan is untouched:
/// the substitute is never cooked or bought, and replaces the member's tick
/// or an earlier substitute (`PlanningRepository.setInstead`).
final class PlanHadInstead extends PlanChange {
  const PlanHadInstead(
    this.expected, {
    required this.memberId,
    required this.meal,
  });

  @override
  final PlanEntry expected;
  final String memberId;
  final InsteadMeal meal;
}

/// A meal a change set touches was edited, moved or removed after the set
/// was drawn. Nothing was written.
class PlanChangedError implements Exception {
  const PlanChangedError(this.entryId);
  final String entryId;
  @override
  String toString() => 'a planned meal changed since the card was drawn';
}
