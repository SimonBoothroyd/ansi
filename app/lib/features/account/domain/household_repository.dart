/// The household row's standing facts: which day the week begins on (pure
/// Dart).
library;

import '../../../core/week_shape.dart';

abstract interface class HouseholdRepository {
  /// The household's [WeekShape], live. Emits Monday until the row arrives.
  Stream<WeekShape> watchWeekShape();

  /// Moves the household's week to start on [startsOn] (ISO 1=Mon..7=Sun),
  /// re-homing every week it has planned.
  ///
  /// A server call, not a local write: the flip re-keys `week_plan`,
  /// `plan_entry` and `shopping_list_entry` rows in one transaction, and the
  /// column reaches the device by sync. Idempotent. Throws when the server
  /// cannot be reached or refuses; the household is then unchanged.
  Future<void> setWeekStart(int startsOn);
}
